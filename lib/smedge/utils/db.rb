# frozen_string_literal: true
# typed: strict

require "date"
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
      path = db_path
      if defined?(@db_path) && @db_path != path && defined?(@db)
        @db.disconnect
        @db = nil
      end

      @db_path = path
      @db ||= T.let(
        Sequel.sqlite(path == ":memory:" ? "file::memory:?cache=shared" : path, foreign_keys: true),
        Sequel::Database
      )
    end

    sig { returns(String) }
    def db_path
      ENV.fetch("SMEDGE_DB", DEFAULT_DB_PATH)
    end

    sig { void }
    def init_db
      # Enable foreign key enforcement
      db.run("PRAGMA foreign_keys = ON")

      # Run migrations
      run_migrations

      # Legacy migration helpers for existing databases
      migrate_cents_to_paise!
    end

    sig { void }
    def reset_schema
      warn "[DB] Resetting schema, dropping tables..."
      # Disable foreign keys to allow dropping tables with FK constraints
      db.run("PRAGMA foreign_keys = OFF")
      # Drop in reverse dependency order to avoid FK constraint errors
      db.drop_table? :printing_logs
      db.drop_table? :delivery_logs
      db.drop_table? :order_items
      db.drop_table? :orders
      db.drop_table? :transactions
      db.drop_table? :credit_ledger_entries
      db.drop_table? :clients
      db.drop_table? :schema_migrations
      db.run("PRAGMA foreign_keys = ON")
      warn "[DB] Tables dropped, reinitializing..."
      init_db
    end

    # Run all pending migrations
    sig { void }
    def run_migrations
      # Migration directory is at project_root/db/migrate
      # __dir__ = /path/to/project/lib/smedge/utils
      # So we need to go up 3 levels: ../../../db/migrate
      migration_dir = File.expand_path(File.join(__dir__, "..", "..", "..", "db", "migrate"))
      warn "[DB] Migration dir: #{migration_dir}, exists: #{Dir.exist?(migration_dir)}"
      return unless Dir.exist?(migration_dir)

      # Create schema_migrations table if it doesn't exist
      db.create_table?(:schema_migrations) do
        String :version, null: false, primary_key: true
        DateTime :applied_at, default: Sequel::CURRENT_TIMESTAMP
      end

      applied = db[:schema_migrations].select_map(:version)
      warn "[DB] Applied migrations: #{applied}"
      files = Dir.glob(File.join(migration_dir, "*.rb"))
      warn "[DB] Migration files: #{files}"
      Dir.glob(File.join(migration_dir, "*.rb")).each do |file|
        version = File.basename(file, ".rb").split("_").first
        warn "[DB] Processing migration: #{file} (version: #{version})"
        next if applied.include?(version)

        # Execute migration directly
        db.transaction do
          db.instance_eval(File.read(file), file)
        end
        db[:schema_migrations].insert(version: version, applied_at: Sequel::CURRENT_TIMESTAMP)
        warn "[DB] Applied migration: #{version}"
      end
    end
    sig { returns(T::Array[Client]) }
    def load_clients
      db[:clients].order(:id).all.map do |row|
        Client.new(
          row[:name],
          row[:email],
          row[:id],
          gstin: row[:gstin],
          state: row[:state],
          address: row[:address],
          city: row[:city],
          pincode: row[:pincode]
        )
      end
    end

    sig { params(id: Integer).returns(T.nilable(Client)) }
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
        order.id = row[:id]
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

    sig { returns(Integer) }
    def count_clients
      db[:clients].count
    end

    sig { params(id: Integer).returns(T.nilable(Order)) }
    def find_order(id)
      row = db[:orders].where(id: id).first
      return unless row
      
      client = find_client(row[:client_id])
      return unless client

      order = Order.new(row[:date].strftime("%d-%m-%Y"), client, row[:discount_paise])
      order.id = row[:id]
      order.order_id = row[:order_id] if row[:order_id]
      order.place_of_supply = row[:place_of_supply]
      db[:order_items].where(order_id: row[:id]).order(:id).each do |item_row|
        item = OrderItem.new(item_row[:description], item_row[:quantity])
        item.setrate(item_row[:rate_paise])
        item.quantity_printed = item_row[:quantity_printed] || 0
        item.quantity_delivered = item_row[:quantity_delivered] || 0
        item.printing_completed = item_row[:printing_completed] || false
        item.delivery_completed = item_row[:delivery_completed] || false
        item.hsn_code = item_row[:hsn_code]
        item.sac_code = item_row[:sac_code]
        item.gst_rate_percent = item_row[:gst_rate_percent] || 18
        item.taxable_value_paise = item_row[:taxable_value_paise] || 0
        item.cgst_paise = item_row[:cgst_paise] || 0
        item.sgst_paise = item_row[:sgst_paise] || 0
        item.igst_paise = item_row[:igst_paise] || 0
        db[:delivery_logs].where(order_item_id: item_row[:id]).order(:delivered_date, :id).each do |log|
          item.delivery_logs << {
            quantity: log[:quantity_delivered],
            date: log[:delivered_date]&.strftime("%d-%m-%Y"),
            note: log[:note]
          }
        end
        order.add_item(item)
      end
      order
    end

    # Load all transaction rows and return them as arrays of Income and Expense
    # objects. No longer attaches to clients - callers should do that if needed.
    sig { params(clients: T::Array[Client]).returns({ incomes: T::Array[Income], expenses: T::Array[Expense] }) }
    def load_transactions(clients)
      by_id = clients.to_h { |client| [T.must(client.id), client] }
      incomes = []
      expenses = []

      db[:transactions].each do |row|
        client = by_id[row[:client_id]]
        next unless client

        date = row[:date]&.strftime("%d-%m-%Y")
        if row[:type] == "income"
          income = Income.new(
            client: client,
            amount: row[:amount_paise],
            mode: row[:mode],
            note: row[:note],
            date: date,
            order_id: row[:order_id]
          )
          incomes << income
          client.add_credit(income)
        else
          expense = Expense.new(
            client: client,
            amount: row[:amount_paise],
            mode: row[:mode],
            note: row[:note],
            date: date
          )
          expenses << expense
          client.add_debit(expense)
        end
      end

      { incomes: incomes, expenses: expenses }
    end

    # Rebuild Order objects with their items and re-attach linked payments.
    # The GST-compliant order_id stored on each row is authoritative; the
    # in-memory fy_order_count is still advanced so newly created orders
    # continue the per-financial-year serial sequence.
    sig { params(clients: T::Array[Client]).returns(T::Array[Order]) }
    def load_orders(clients)
      Smedge::Order.fy_order_count = Hash.new(0)
      by_id = clients.to_h { |client| [T.must(client.id), client] }

      orders = db[:orders].order(:date, :id).all.filter_map do |row|
        client = by_id[row[:client_id]]
        next unless client

        order = Order.new(row[:date].strftime("%d-%m-%Y"), client, row[:discount_paise])
        order.id = row[:id]
        order.order_id = row[:order_id] if row[:order_id]
        db[:order_items].where(order_id: row[:id]).order(:id).each do |item_row|
          item = OrderItem.new(item_row[:description], item_row[:quantity])
          item.setrate(item_row[:rate_paise])
          item.quantity_printed = item_row[:quantity_printed] || 0
          item.quantity_delivered = item_row[:quantity_delivered] || 0
          item.printing_completed = item_row[:printing_completed] || false
          item.delivery_completed = item_row[:delivery_completed] || false
          # GST fields
          item.hsn_code = item_row[:hsn_code]
          item.sac_code = item_row[:sac_code]
          item.gst_rate_percent = item_row[:gst_rate_percent] || 18
          item.taxable_value_paise = item_row[:taxable_value_paise] || 0
          item.cgst_paise = item_row[:cgst_paise] || 0
          item.sgst_paise = item_row[:sgst_paise] || 0
          item.igst_paise = item_row[:igst_paise] || 0
          order.add_item(item)
        end
        order
      end

      # Query payments linked to orders from the database instead of using Income.all
      payments_by_order = T.let({}, T::Hash[Integer, T::Array[Income]])
      db[:transactions].where(type: "income").exclude(order_id: nil).each do |row|
        client = by_id[row[:client_id]]
        next unless client

        date = row[:date]&.strftime("%d-%m-%Y")
        income = Income.new(
          client: client,
          amount: row[:amount_paise],
          mode: row[:mode],
          note: row[:note],
          date: date,
          order_id: row[:order_id]
        )
        (payments_by_order[income.order_id] ||= T.let([], T::Array[Income])) << income
      end

      orders.each do |order|
        next unless order.id

        payments = payments_by_order[order.id]
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
      
      # Generate GST-compliant order_id like the Order model does
      fy_start_year = order_date.month >= 4 ? order_date.year : order_date.year - 1
      fy_end_year = fy_start_year + 1
      fy_suffix = "#{fy_start_year.to_s[-2, 2]}-#{fy_end_year.to_s[-2, 2]}"
      fy_key = "FY#{fy_suffix}"
      Smedge::Order.fy_order_count ||= Hash.new(0)
      Smedge::Order.fy_order_count[fy_key] += 1
      serial = format("%05d", Smedge::Order.fy_order_count[fy_key])
      order_id_str = "ORD/#{fy_suffix}/#{serial}"
      
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
          discount_paise: order.discount.cents,
          order_id: order_id_str
        )
        order.id = order_id
        order.order_id = order_id_str
        items.each do |item|
          db[:order_items].insert(
            order_id: order_id,
            description: item[:description],
            quantity: item[:quantity],
            rate_paise: item[:rate],
            quantity_printed: 0,
            quantity_delivered: 0,
            printing_completed: false,
            delivery_completed: false,
            hsn_code: item[:hsn_code],
            sac_code: item[:sac_code],
            gst_rate_percent: item[:gst_rate_percent] || 18,
            taxable_value_paise: 0,
            cgst_paise: 0,
            sgst_paise: 0,
            igst_paise: 0
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

      if order_id
        order = db[:orders].where(id: order_id).first
        raise Smedge::Error, "Order not found: #{order_id}" unless order
        raise Smedge::Error, "Order belongs to a different customer" unless order[:client_id] == client.id
      end
      
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
    # Seed the database from a YAML file. Assumes the schema has already been
    # initialized (e.g. via `reset_schema` or `init_db`).
    def seed_from_yaml(yaml_file_path)
      data = YAML.safe_load_file(yaml_file_path, aliases: true) || {}

      client_ids = T.let({}, T::Hash[String, Integer])
      (data["clients"] || []).each do |client_hash|
        id = db[:clients].insert(
          name: client_hash["name"],
          email: client_hash["email"],
          gstin: client_hash["gstin"],
          state: client_hash["state"],
          address: client_hash["address"],
          city: client_hash["city"],
          pincode: client_hash["pincode"]
        )
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

        # Generate a GST-compliant order_id (ORD/YY-YY/NNNNN) like create_order
        date_str = order_hash["date"]
        date = parse_date(date_str)
        next unless date

        fy_start_year = date.month >= 4 ? date.year : date.year - 1
        fy_end_year = fy_start_year + 1
        fy_suffix = "#{fy_start_year.to_s[-2, 2]}-#{fy_end_year.to_s[-2, 2]}"
        fy_start = Date.new(fy_start_year, 4, 1)
        fy_end = Date.new(fy_end_year, 3, 31)

        # Serial counts existing orders in the same financial year
        existing_count = db[:orders]
                         .where(Sequel[:date] >= fy_start)
                         .where(Sequel[:date] <= fy_end)
                         .count
        serial = format("%05d", existing_count + 1)
        order_id_str = "ORD/#{fy_suffix}/#{serial}"

        order_id = db[:orders].insert(
          client_id: client_id,
          date: date,
          discount_paise: order_hash["discount"].to_i,
          order_id: order_id_str
        )
        (order_hash["items"] || []).each do |item|
          db[:order_items].insert(
            order_id: order_id,
            description: item["description"],
            quantity: item["quantity"],
            rate_paise: item["rate"],
            quantity_printed: 0,
            quantity_delivered: 0,
            printing_completed: false,
            delivery_completed: false,
            hsn_code: item["hsn_code"],
            sac_code: item["sac_code"],
            gst_rate_percent: item["gst_rate_percent"] || 18,
            taxable_value_paise: 0,
            cgst_paise: 0,
            sgst_paise: 0,
            igst_paise: 0
          )
        end
      end
    end

    sig { params(client_id: Integer, order_ref: String).returns(T.nilable(Integer)) }
    def order_id_for_ref(client_id, order_ref)
      # New format: ORD/YY-YY/NNNNN
      match = %r{\AORD/(\d{2}-\d{2})/(\d+)\z}.match(order_ref.to_s)
      return unless match

      fy_suffix = match[1]
      sequence = match[2].to_i
      order = db[:orders].where(client_id: client_id, order_id: "ORD/#{fy_suffix}/#{format("%05d", sequence)}").first
      order && order[:id]
    rescue ArgumentError
      nil
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

    sig { params(table: Symbol, column: Symbol).void }
    def add_index_unless_exists(table, column)
      indexed_columns = db.indexes(table).values.map { |index| index[:columns] }
      return if indexed_columns.include?([column])

      db.alter_table(table) { add_index column }
    end

    sig { params(date: T.nilable(String)).returns(T.nilable(Date)) }
    def parse_date(date)
      return unless date

      Utils::DateParser.parse(date)
    end

    # Record printing progress for an order item
    sig do
      params(
        order_item_id: Integer,
        quantity: Integer,
        date: String,
        note: T.nilable(String)
      ).void
    end
    def record_printing(order_item_id:, quantity:, date:, note: nil)
      raise Smedge::Error, "Printing quantity must be positive" if quantity <= 0

      item = db[:order_items].where(id: order_item_id).first
      raise Smedge::Error, "Order item not found" unless item

      db.transaction do
        # Add printing log
        db[:printing_logs].insert(
          order_item_id: order_item_id,
          quantity_printed: quantity,
          printed_date: Utils::DateParser.parse(date),
          note: note,
          created_at: Sequel::CURRENT_TIMESTAMP
        )

        # Update order_item
        new_printed = (item[:quantity_printed] || 0) + quantity
        printing_completed = new_printed >= item[:quantity]
        db[:order_items].where(id: order_item_id).update(
          quantity_printed: new_printed,
          printing_completed: printing_completed
        )
      end
    end

    # Record delivery for an order item
    sig do
      params(
        order_item_id: Integer,
        quantity: Integer,
        date: String,
        note: T.nilable(String)
      ).void
    end
    def record_delivery(order_item_id:, quantity:, date:, note: nil)
      raise Smedge::Error, "Delivery quantity must be positive" if quantity <= 0

      item = db[:order_items].where(id: order_item_id).first
      raise Smedge::Error, "Order item not found" unless item

      printed = item[:quantity_printed] || 0
      delivered = (item[:quantity_delivered] || 0) + quantity
      raise Smedge::Error, "Cannot deliver more than printed quantity" if delivered > printed

      db.transaction do
        # Add delivery log
        db[:delivery_logs].insert(
          order_item_id: order_item_id,
          quantity_delivered: quantity,
          delivered_date: Utils::DateParser.parse(date),
          note: note,
          created_at: Sequel::CURRENT_TIMESTAMP
        )

        # Update order_item
        delivery_completed = delivered >= (item[:quantity_printed] || 0)
        db[:order_items].where(id: order_item_id).update(
          quantity_delivered: delivered,
          delivery_completed: delivery_completed
        )
      end
    end

    # Get printing logs for an order item
    sig { params(order_item_id: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def get_printing_logs(order_item_id)
      db[:printing_logs].where(order_item_id: order_item_id).order(:printed_date, :id).all
    end

    # Get delivery logs for an order item
    sig { params(order_item_id: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def get_delivery_logs(order_item_id)
      db[:delivery_logs].where(order_item_id: order_item_id).order(:delivered_date, :id).all
    end
  end
end
