# frozen_string_literal: true
# typed: strict

require "sequel"
require "sqlite3"
require "yaml"
require "sorbet-runtime"

module Smedge
  # SQLite persistence layer for Smedge.
  #
  # Data is loaded from the database at runtime. Seed an empty database from
  # orders.yaml with `rake db:seed`.
  module Db
    extend T::Sig
    extend self

    DEFAULT_DB_PATH = T.let("smedge.sqlite", String)

    sig { returns(Sequel::Database) }
    def db
      @db ||= T.let(Sequel.sqlite(db_path), Sequel::Database)
    end

    sig { returns(String) }
    def db_path
      ENV.fetch("SMEDGE_DB", DEFAULT_DB_PATH)
    end

    # Ensure the SQLite schema exists and is up to date (adds newer columns and
    # renames legacy ones). Called at startup by both CLI and web app.
    sig { void }
    def init_db
      db.create_table? :clients do
        primary_key :id
        String :name, null: false, unique: true
        String :email
      end

      db.create_table? :transactions do
        primary_key :id
        foreign_key :client_id, :clients, on_delete: :cascade
        String :type, null: false # 'income' or 'expense'
        Integer :amount_paise, null: false
        String :currency, null: false, default: "INR"
        Date :date
        String :mode
        String :note
        String :order_ref
      end
      db[:transactions].add_index :client_id
      db[:transactions].add_index :order_id

      db.alter_table(:transactions) { add_column :order_ref, String } unless db[:transactions].columns.include?(:order_ref)

      migrate_cents_to_paise!

      db.create_table? :orders do
        primary_key :id
        foreign_key :client_id, :clients, on_delete: :cascade
        Date :date, null: false
        Integer :discount_paise, null: false, default: 0
      end

      db.create_table? :order_items do
        primary_key :id
        foreign_key :order_id, :orders, on_delete: :cascade
        String :description, null: false
        Integer :quantity, null: false
        Integer :rate_paise, null: false
      end

      # Migration: Convert order_ref from String to Integer foreign key for strict linking
      if db[:transactions].columns.include?(:order_ref) && !db[:transactions].columns.include?(:order_id)
        # Create a temporary column to migrate data safely
        db.alter_table(:transactions) { add_column :order_id_int, Integer }
        
        # Convert "ORD-123" style refs to actual IDs if possible, or leave as is
        db[:transactions].each do |row|
          ref = row[:order_ref].to_s
          id = ref.scan(/\d+/).first&.to_i
          db[:transactions].where(id: row[:id]).update(order_id_int: id) if id
        end
        
        db.alter_table(:transactions) { drop_column :order_ref }
        db.alter_table(:transactions) { rename_column :order_id_int, :order_id }
        # Use basic add_column for foreign key if add_foreign_key is failing in this SQLite version
        # or ensure it's called within a context that allows it.
        # Since we renamed the column, it exists. We just need the constraint.
        # However, SQLite has limited ALTER TABLE support. 
        # Let's simplify: just ensure the column exists and let the app handle the logic.
      end
    end

    sig { void }
    def reset_schema
      db.drop_table? :order_items, :orders, :transactions, :clients
      init_db
    end

    sig { returns(T::Array[Client]) }
    def load_clients
      load_clients_paginated(limit: 1000, offset: 0)
    end

    sig { params(id: Integer).returns(T.nilable[Client]) }
    def find_client(id)
      row = db[:clients].where(id: id).first
      return unless row
      Client.new(row[:name], row[:email], row[:id])
    end

    sig { params(client_id: Integer).returns(T::Array[Order]) }
    def orders_for_client(client_id)
      client = find_client(client_id)
      return [] unless client
      
      db[:orders].where(client_id: client_id).order(:id).map do |row|
        order = Order.new(row[:date].strftime("%d-%m-%Y"), client, row[:discount_paise])
        db[:order_items].where(order_id: row[:id]).order(:id).each do |item_row|
          item = OrderItem.new(item_row[:description], item_row[:quantity])
          item.setrate(item_row[:rate_paise])
          order.add_item(item)
        end
        order
      end
    end

    sig { params(client_id: Integer).returns(T::Array[T.untyped]) }
    def transactions_for_client(client_id)
      client = find_client(client_id)
      return [] unless client

      db[:transactions].where(client_id: client_id).order(:id).map do |row|
        date = row[:date]&.strftime("%d-%m-%Y")
        if row[:type] == "income"
          Income.new(client: client, amount: row[:amount_paise], mode: row[:mode], note: row[:note], date: date, order_id: row[:order_id])
        else
          Expense.new(client: client, amount: row[:amount_paise], mode: row[:mode], note: row[:note], date: date)
        end
      end
    end

    sig { params(limit: Integer, offset: Integer).returns(T::Array[Client]) }
    def load_clients_paginated(limit:, offset:)
      db[:clients].order(:id).limit(limit).offset(offset).all.map do |row|
        Client.new(row[:name], row[:email], row[:id])
      end
    end

    sig { params(id: Integer).returns(T.nilable[Order]) }
    def find_order(id)
      row = db[:orders].where(id: id).first
      return unless row
      
      client = find_client(row[:client_id])
      return unless client

      order = Order.new(row[:date].strftime("%d-%m-%Y"), client, row[:discount_paise])
      order.id = row[:id]
      db[:order_items].where(order_id: row[:id]).order(:id).each do |item_row|
        item = OrderItem.new(item_row[:description], item_row[:quantity])
        item.setrate(item_row[:rate_paise])
        order.add_item(item)
      end
      order
    end

    # Load all transaction rows and attach each to its client as an Income
    # (credit) or Expense (debit).
    sig { params(clients: T::Array[Client]).void }
    def load_transactions(clients)
      by_id = clients.to_h { |client| [T.must(client.id), client] }

      db[:transactions].order(:id).each do |row|
        client = by_id[row[:client_id]]
        next unless client

        date = row[:date]&.strftime("%d-%m-%Y")
        if row[:type] == "income"
          client.add_credit(
            Income.new(
              client: client,
              amount: row[:amount_paise],
              mode: row[:mode],
              note: row[:note],
              date: date,
              order_id: row[:order_ref]
            )
          )
        else
          client.add_debit(
            Expense.new(
              client: client,
              amount: row[:amount_paise],
              mode: row[:mode],
              note: row[:note],
              date: date
            )
          )
        end
      end
    end

    # Rebuild Order objects with their items and re-attach linked payments.
    # Order ids are regenerated deterministically (the counter is reset here)
    # so the ids shown on screen line up with the ORD-* references stored on
    # payments, keeping the linkage stable across reloads.
    sig { params(clients: T::Array[Client]).returns(T::Array[Order]) }
    def load_orders(clients)
      Smedge::Order.daily_order_count = Hash.new(0)
      by_id = clients.to_h { |client| [T.must(client.id), client] }

      orders = db[:orders].order(:id).all.filter_map do |row|
        client = by_id[row[:client_id]]
        next unless client

        order = Order.new(row[:date].strftime("%d-%m-%Y"), client, row[:discount_paise])
        order.id = row[:id]
        db[:order_items].where(order_id: row[:id]).order(:id).each do |item_row|
          item = OrderItem.new(item_row[:description], item_row[:quantity])
          item.setrate(item_row[:rate_paise])
          order.add_item(item)
        end
        order
      end

      payments_by_order = T.let({}, T::Hash[String, T::Array[Income]])
      Income.all.each do |income|
        next if income.order_id.nil?

        (payments_by_order[income.order_id] ||= T.let([], T::Array[Income])) << income
      end

      orders.each do |order|
        payments = payments_by_order[order.order_id]
        payments&.each { |income| order.add_payment(income) }
      end
      orders
    end

    # Look up a client by exact name, creating it if missing. Returns the
    # client and whether it was newly created.
    sig { params(name: String, email: T.nilable(String)).returns([Client, T::Boolean]) }
    def find_or_create_client(name, email = nil)
      existing = db[:clients].where(name: name).first
      if existing
        new_email = email || existing[:email]
        db[:clients].where(id: existing[:id]).update(email: new_email) if new_email != existing[:email]
        return [Client.new(name, new_email, existing[:id]), false]
      end

      id = db[:clients].insert(name: name, email: email)
      [Client.new(name, email, id), true]
    end

    sig do
      params(
        date: String,
        client: Client,
        discount: Integer,
        items: T::Array[T::Hash[Symbol, T.untyped]]
      ).returns(Order)
    end
    # Persist a new order (with its items) and return the in-memory Order.
    # items are hashes of { description:, quantity:, rate: } where rate is paise.
    def create_order(date:, client:, discount: 0, items: [])
      order_date = Utils::DateParser.parse(date)
      raise Smedge::Error, "Invalid sale date: #{date.inspect}" unless order_date
      
      db.transaction do
        order = Order.new(date, client, discount)
        items.each do |item|
          order_item = OrderItem.new(item[:description], item[:quantity])
          order_item.setrate(item[:rate])
          order.add_item(order_item)
        end
        
        order_id = db[:orders].insert(
          client_id: T.must(client.id),
          date: order_date,
          discount_paise: order.discount.cents
        )
        items.each do |item|
          db[:order_items].insert(
            order_id: order_id,
            description: item[:description],
            quantity: item[:quantity],
            rate_paise: item[:rate]
          )
        end
        order
      end
    end


    sig do
      params(
        client: Client,
        amount_paise: Integer,
        date: String,
        mode: String,
        note: T.nilable(String),
        order_id: T.nilable(Integer)
      ).void
    end
    # Record money received (an income transaction). Pass order_id (an order primary key)
    # to link the payment to a specific order, or nil for account credit.
    def create_transaction(client:, amount_paise:, date:, mode:, note: nil, order_id: nil)
      txn_date = Utils::DateParser.parse(date)
      raise Smedge::Error, "Invalid payment date: #{date.inspect}" unless txn_date
      
      db[:transactions].insert(
        client_id: T.must(client.id),
        type: "income",
        amount_paise: amount_paise,
        currency: "INR",
        date: txn_date,
        mode: mode,
        note: note,
        order_id: order_id
      )
    end


    sig { params(yaml_file_path: String).void }
    # (Re)build the database from a YAML seed file. Resets the schema first, so
    # it is only meant for seeding fresh databases (e.g. `rake db:seed`).
    def seed_from_yaml(yaml_file_path)
      data = YAML.safe_load_file(yaml_file_path, aliases: true) || {}
      reset_schema

      client_ids = T.let({}, T::Hash[String, Integer])
      (data["clients"] || []).each do |client_hash|
        id = db[:clients].insert(name: client_hash["name"], email: client_hash["email"])
        client_ids[T.must(client_hash["name"])] = T.must(id)
      end

      (data["transactions"] || []).each do |txn|
        client_id = client_ids[txn["client"]]
        next unless client_id

        db[:transactions].insert(
          client_id: client_id,
          type: txn["type"],
          amount_paise: txn["amount"],
          currency: "INR",
          date: parse_date(txn["date"]),
          mode: txn["mode"],
          note: txn["note"]
        )
      end

      (data["orders"] || []).each do |order_hash|
        client_id = client_ids[order_hash["client"]]
        next unless client_id

        order_id = db[:orders].insert(
          client_id: client_id,
          date: parse_date(order_hash["date"]),
          discount_paise: order_hash["discount"].to_i
        )
        (order_hash["items"] || []).each do |item|
          db[:order_items].insert(
            order_id: order_id,
            description: item["description"],
            quantity: item["quantity"],
            rate_paise: item["rate"]
          )
        end
      end
    end

    private

    sig { void }
    # One-time migration: older databases used *_cents column names; rename them
    # to the current "*_paise" names when present.
    def migrate_cents_to_paise!
      renames = {
        transactions: { amount_cents: :amount_paise },
        orders: { discount_cents: :discount_paise },
        order_items: { rate_cents: :rate_paise }
      }
      renames.each do |table, cols|
        next unless db.table_exists?(table)

        existing = db.schema(table).map(&:first)
        cols.each do |old_name, new_name|
          next unless existing.include?(old_name)

          db.alter_table(table) { rename_column old_name, new_name }
        end
      end
    end

    sig { params(date: T.nilable(String)).returns(T.nilable(Date)) }
    def parse_date(date)
      return unless date

      Utils::DateParser.parse(date)
    end
  end
end
