# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:development, :web)
require "sinatra/base"
require "rack/protection"
require "bigdecimal"
require "json"
require "securerandom"
require_relative "../lib/smedge"
require_relative "../lib/smedge/pdf_generator"

module Smedge
  # Web interface for Smedge: dashboard, customers, orders, sales and payments.
  # Data is reloaded fresh from SQLite before every request so multiple
  # processes (web + CLI) can safely share the same database.
  class Web < Sinatra::Base
    configure do
      set :root, File.expand_path(__dir__)
      set :views, File.expand_path("views", __dir__)
      set :public_folder, File.expand_path("public", __dir__)
      set :port, 4567
      # Session cookies are signed; SMEDGE_SECRET keeps them valid across
      # restarts (a random one is generated when the env var is absent).
      set :session_secret, ENV.fetch("SMEDGE_SECRET", SecureRandom.hex(32))
      set :host_authorization, { permitted_hosts: [] }
      set :show_exceptions, false
      use Rack::Protection::AuthenticityToken
      enable :sessions
      # Database initialization is deferred to first request to allow tests
      # to control schema initialization via Smedge::Db.reset_schema
    end

    # HTTP Basic Authentication - runs before each request
    before do
      protected!
    end

    # HTTP Basic Authentication helper
    def protected!
      username = ENV.fetch("SMEDGE_AUTH_USERNAME", "admin")
      password = ENV.fetch("SMEDGE_AUTH_PASSWORD", "changeme")
      return unless username && password
      return if authorized?(username, password)
      headers["WWW-Authenticate"] = %(Basic realm="Smedge Admin")
      halt 401, "Not authorized\n"
    end

    def authorized?(username, password)
      @auth ||= Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? && @auth.basic? && @auth.credentials &&
        @auth.credentials == [username, password]
    end

    # Dashboard: summary cards, monthly line chart and recent orders.
    get "/" do
      clients, orders = reload_all
      @orders = orders
      @clients = clients
      @recent_orders = orders.sort_by(&:date).reverse.first(5)
      @summary = monthly_summary
      erb :index
    end

    # List all customers.
    get "/clients" do
      _, orders = reload_all
      @orders = orders
      page = (params["page"] || 1).to_i
      per_page = 20
      offset = (page - 1) * per_page

      @clients = Smedge::Db.load_clients_paginated(limit: per_page, offset: offset)
      @total_clients = Smedge::Db.count_clients
      @current_page = page
      @total_pages = (@total_clients.to_f / per_page).ceil

      erb :clients
    end

    # Customer detail: their payments, expenses and per-order credit flow.
    get "/clients/:id" do
      _, orders = reload_all
      @orders = orders
      @client = Smedge::Db.find_client(params["id"].to_i)
      halt 404, "Client not found" unless @client
      halt 404, "Client has no id in database" unless @client.id

      @client_orders = @orders.select { |order| order.client.id == @client.id }

      # Manually attach transactions to the client object for the view
      transactions = Smedge::Db.transactions_for_client(@client.id)
      transactions.each do |txn|
        if txn.is_a?(Smedge::Income)
          @client.add_credit(txn)
        elsif txn.is_a?(Smedge::Expense)
          @client.add_debit(txn)
        end
      end

      @credit_flow = Smedge::Services.calculate_credit_flow(@client, @client_orders)
      erb :client
    end

    # Order detail: itemized list and associated payments.
    get "/orders/:id/edit" do
      @order = Smedge::Db.find_order(params["id"].to_i)
      halt 404, "Order not found" unless @order
      clients, _ = reload_all
      @clients = clients
      erb :orders_edit
    end

    # Update an order (metadata: client, date, discount, invoice, tax)
    post "/orders/:id" do
      db = Smedge::Db.db
      order = Smedge::Db.find_order(params["id"].to_i)
      halt 404, "Order not found" unless order

      client_name = params["client"].to_s.strip
      raise Smedge::Error, "Customer name is required" if client_name.empty?

      date_str = params["date"].to_s.strip
      raise Smedge::Error, "Sale date is required" if date_str.empty?

      date = Date.parse(date_str).strftime("%d-%m-%Y")
      discount = params["discount"].to_s.strip
      discount_paise = discount.empty? ? 0 : rupees_to_paise(discount)
      invoice_number = params["invoice_number"].to_s.strip
      invoice_number = nil if invoice_number.empty?
      tax_rate = params["tax_rate"].to_f

      client, = Smedge::Db.find_or_create_client(client_name)
      tax_amount_paise = if invoice_number.nil? || tax_rate <= 0
        0
      else
        order_amount_paise = order.total_amount_after_discount.cents
        split = Smedge::TaxService.send(:calculate_split, client_state: client.state, business_state: "", rate_percent: tax_rate)
        Smedge::TaxService.tax_amounts(amount_paise: order_amount_paise, rate_percent: tax_rate, split: split).first
      end

      db[:orders].where(id: order.id).update(
        client_id: client.id,
        date: Date.parse(date_str),
        discount_paise: discount_paise,
        invoice_number: invoice_number,
        tax_amount_paise: tax_amount_paise
      )

      # Process line items: delete checked, update existing, insert new
      deleted_ids = Array(params["delete_item"]).map { |v| v.to_i }.reject { |v| v == 0 }
      db[:order_items].where(order_id: order.id).where(id: deleted_ids).delete unless deleted_ids.empty?

      kept_ids = []
      items_payload = params["item"] || []
      # Handle both array-of-hashes and hash-from-single-row forms
      if items_payload.is_a?(Hash) && items_payload.key?("description")
        items_payload = [items_payload]
      end
      Array(items_payload).each do |sub|
        next unless sub.is_a?(Hash)
        desc = (sub["description"] || "").to_s.strip
        qty = (sub["quantity"] || "").to_s.strip.to_i
        rate_str = (sub["rate"] || "").to_s
        item_id = sub["id"].to_s.strip.to_i
        next if desc.empty? || qty <= 0 || rate_str.strip.empty?
        rate_paise = rupees_to_paise(rate_str)

        # Recompute GST breakdown through the domain object so stored
        # taxable_value / cgst / sgst / igst stay consistent with rate+qty.
        item = Smedge::OrderItem.new(desc, qty)
        item.setrate(rate_paise)
        item.calculate_gst(
          place_of_supply: order.place_of_supply,
          client_state: client.state
        )

        if item_id > 0
          db[:order_items].where(id: item_id, order_id: order.id).update(
            description: desc,
            quantity: qty,
            rate_paise: rate_paise,
            taxable_value_paise: item.taxable_value_paise,
            cgst_paise: item.cgst_paise,
            sgst_paise: item.sgst_paise,
            igst_paise: item.igst_paise
          )
          kept_ids << item_id
        else
          new_id = db[:order_items].insert(
            order_id: order.id,
            description: desc,
            quantity: qty,
            rate_paise: rate_paise,
            gst_rate_percent: item.gst_rate_percent,
            taxable_value_paise: item.taxable_value_paise,
            cgst_paise: item.cgst_paise,
            sgst_paise: item.sgst_paise,
            igst_paise: item.igst_paise
          )
          kept_ids << new_id
        end
      end
      # Delete rows serving neither an updated nor a newly inserted item,
      # nor flagged through the checkbox (covers browser-side row removals).
      survivors = db[:order_items].where(order_id: order.id).select_map(:id)
      to_delete = survivors - kept_ids - deleted_ids
      db[:order_items].where(order_id: order.id, id: to_delete).delete unless to_delete.empty?

      session[:notice] = "Order #{order.order_id} updated"
      redirect "/orders/#{order.id}"
    rescue Smedge::Error, ArgumentError, Sequel::DatabaseError => e
      @error = e.message
      @form = params
      @order = Smedge::Db.find_order(params["id"].to_i)
      _, clients = reload_all
      @clients = clients
      erb :orders_edit
    end

    get "/orders/:id" do
      @order = Smedge::Db.find_order(params["id"].to_i)
      halt 404, "Order not found" unless @order

      # Find payments explicitly linked to this order
      @payments = Smedge::Db.db[:transactions]
                               .where(order_id: @order.id, type: "income")
                               .all.map do |row|
        Smedge::Income.new(
          client: @order.client,
          amount: row[:amount_paise],
          mode: row[:mode],
          note: row[:note],
          date: row[:date]&.strftime("%d-%m-%Y"),
          order_id: row[:order_id]
        )
      end
      erb :order_detail
    end

    # Download order receipt as PDF
    get "/orders/:id/receipt" do
      @order = Smedge::Db.find_order(params["id"].to_i)
      halt 404, "Order not found" unless @order

      @payments = Smedge::Db.db[:transactions]
                               .where(order_id: @order.id, type: "income")
                               .all.map do |row|
        Smedge::Income.new(
          client: @order.client,
          amount: row[:amount_paise],
          mode: row[:mode],
          note: row[:note],
          date: row[:date]&.strftime("%d-%m-%Y"),
          order_id: row[:order_id]
        )
      end

      pdf = Smedge::PdfGenerator.receipt(@order, @payments)
      content_type "application/pdf"
      attachment "receipt_#{@order.order_id.gsub("/", "_")}.pdf"
      pdf
    end

    # Download order invoice as PDF (for unpaid orders)
    get "/orders/:id/invoice" do
      @order = Smedge::Db.find_order(params["id"].to_i)
      halt 404, "Order not found" unless @order

      pdf = Smedge::PdfGenerator.invoice(@order)
      content_type "application/pdf"
      attachment "invoice_#{@order.order_id.gsub("/", "_")}.pdf"
      pdf
    end

    # List all orders, newest first.
    get "/orders" do
      _, orders = reload_all
      @orders = orders.sort_by(&:date).reverse
      erb :orders
    end

    get "/customers/new" do
      erb :customers_new
    end

    # Create a customer (or reuse an existing one with the same name).
    post "/customers" do
      name = params["name"].to_s.strip
      email = params["email"].to_s.strip
      raise Smedge::Error, "Customer name is required" if name.empty?

      client, created = Smedge::Db.find_or_create_client(name, email.empty? ? nil : email)
      session[:notice] = created ? "Customer added: #{client.name}" : "Customer already exists: #{client.name}"
      redirect "/clients/#{client.id}"
    rescue Smedge::Error => e
      @error = e.message
      @name = params["name"]
      @email = params["email"]
      erb :customers_new
    end

    get "/clients/:id/edit" do
      @client = Smedge::Db.find_client(params["id"].to_i)
      halt 404, "Client not found" unless @client
      erb :customers_edit
    end

    # Update a customer (or create if new name)
    post "/clients/:id" do
      client = Smedge::Db.find_client(params["id"].to_i)
      halt 404, "Client not found" unless client

      name = params["name"].to_s.strip
      email = params["email"].to_s.strip
      gstin = params["gstin"].to_s.strip
      state = params["state"].to_s.strip
      address = params["address"].to_s.strip
      city = params["city"].to_s.strip
      pincode = params["pincode"].to_s.strip

      raise Smedge::Error, "Customer name is required" if name.empty?

      # Update client fields
      client.name = name
      client.email = email.empty? ? nil : email
      client.gstin = gstin.empty? ? nil : gstin
      client.state = state.empty? ? nil : state
      client.address = address.empty? ? nil : address
      client.city = city.empty? ? nil : city
      client.pincode = pincode.empty? ? nil : pincode

      # Persist changes
      db = Smedge::Db.db
      db[:clients].where(id: client.id).update(
        name: client.name,
        email: client.email,
        gstin: client.gstin,
        state: client.state,
        address: client.address,
        city: client.city,
        pincode: client.pincode
      )

      session[:notice] = "Customer updated: #{client.name}"
      redirect "/clients/#{client.id}"
    rescue Smedge::Error => e
      @error = e.message
      @client = client
      erb :customers_edit
    end

    get "/sales/new" do
      _, _ = reload_all
      @clients = Smedge::Db.load_clients
      erb :sales_new
    end

    # Create a sale. Dates arrive as ISO "yyyy-mm-dd" from the HTML date input
    # and are converted to the "dd-mm-yyyy" everywhere else.
    post "/sales" do
      db = Smedge::Db.db
      client_name = params["client"].to_s.strip
      raise Smedge::Error, "Customer name is required" if client_name.empty?

      date = params["date"].to_s.strip
      raise Smedge::Error, "Sale date is required" if date.empty?

      date = Date.parse(date).strftime("%d-%m-%Y")
      items = Smedge::Services.build_items(params["item"])
      raise Smedge::Error, "Add at least one item" if items.empty?

      discount = params["discount"].to_s.strip
      discount_paise = discount.empty? ? 0 : rupees_to_paise(discount)

      gstin = params["gstin"].to_s.strip
      state = params["state"].to_s.strip
      client, created = Smedge::Db.find_or_create_client(client_name, nil, gstin.empty? ? nil : gstin, state.empty? ? nil : state)
      invoice_number = params["invoice_number"].to_s.strip
      tax_rate = params["tax_rate"].to_f
      # Apply per-item HSN from items input if present
      items_hash = {}
      if params["item"].is_a?(Array) && params["item"].first.is_a?(Hash)
        params["item"].each_with_index do |sub, i|
          desc = (sub["description"] || "").to_s
          qty = (sub["quantity"] || "").to_i
          rate = CreditService.rupees_to_paise((sub["rate"] || "0").to_s)
          hsn = (sub["hsn"] || "").to_s
          next if desc.empty? || qty <= 0
          items_hash[i] = { description: desc, quantity: qty, rate: rate, hsn: hsn }
        end
      else
        items.each_with_index do |it, i|
          items_hash[i] = it[:description].to_s.empty? ? nil : it
        end
      end
      valid_items = items_hash.compact.values
      raise Smedge::Error, "Add at least one item" if valid_items.empty?
      # Build order with HSN + tax on line items
      order = Smedge::Order.new(date, client, discount_paise)
      valid_items.each do |it|
        oi = Smedge::OrderItem.new(it[:description], it[:quantity])
        oi.setrate(it[:rate])
        oi.set_hsn(it[:hsn])
        order.add_item(oi)
      end
      invoice_number ||= nil
      tax_amount_paise = if gstin.strip.empty? || tax_rate <= 0
        0
      else
        tax_service_compute = Smedge::TaxService.send(:calculate_split, client_state: client.state, business_state: "", rate_percent: tax_rate)
        order_amount_paise = order.total_amount_after_discount.cents
        Smedge::TaxService.tax_amounts(amount_paise: order_amount_paise, rate_percent: tax_rate, split: tax_service_compute).first
      end
      order.invoice_number = invoice_number
      order.tax_amount_paise = tax_amount_paise
      db_result = db.transaction do
        order_id = db[:orders].insert(
            client_id: client.id,
            date: Date.parse(date),
            discount_paise: order.discount.cents,
            order_id: order.order_id,
            invoice_number: invoice_number,
            tax_amount_paise: tax_amount_paise
          )
          order.id = order_id
          valid_items.each do |it|
            db[:order_items].insert(
              order_id: order_id,
              description: it[:description],
              quantity: it[:quantity],
              rate_paise: it[:rate],
              hsn_code: it[:hsn]
            )
          end
          order
        end
      session[:notice] = "Sale #{order.order_id} added for #{client.name}"
      redirect "/clients/#{client.id}"
    rescue Smedge::Error, ArgumentError, Sequel::DatabaseError => e
      @error = e.message
      @form = params
      _, clients = reload_all
      @clients = clients
      erb :sales_new
    end


    get "/payments/new" do
      _, orders = reload_all
      @orders = orders
      @clients = Smedge::Db.load_clients
      @client_name = params["client"]
      erb :payments_new
    end

    # Record money received: rupee input is converted to paise, then persisted
    # as an income transaction, optionally linked to a sale via order_id.
    post "/payments" do
      client_name = params["client"].to_s.strip
      raise Smedge::Error, "Customer name is required" if client_name.empty?

      amount = params["amount"].to_s.strip
      raise Smedge::Error, "Payment amount is required" if amount.empty?

      amount_paise = rupees_to_paise(amount)
      raise Smedge::Error, "Payment amount must be more than 0" if amount_paise <= 0

      date = params["date"].to_s.strip
      raise Smedge::Error, "Payment date is required" if date.empty?

      date = Date.parse(date).strftime("%d-%m-%Y")
      mode = params["mode"].to_s.strip
      mode = "bank" if mode.empty?
      note = params["note"].to_s.strip
      note = nil if note.empty?
      order_id = params["order_id"].to_s.strip
      order_id = (order_id.empty? ? nil : order_id.to_i)

      client, = Smedge::Db.find_or_create_client(client_name)
      Smedge::Db.create_transaction(client: client, amount_paise: amount_paise, date: date, mode: mode, note: note, order_id: order_id)
      message = "Payment recorded: #{money(Money.new(amount_paise))} for #{client.name}"
      message += " against order ##{order_id}" if order_id
      session[:notice] = message
      redirect "/clients/#{client.id}"
    rescue Smedge::Error, ArgumentError, Sequel::DatabaseError => e
      @error = e.message
      @form = params
      erb :payments_new
    end

    # Export client statement to CSV
    get "/clients/:id/export" do
      @client = Smedge::Db.find_client(params["id"].to_i)
      halt 404, "Client not found" unless @client

      content_type "text/csv"
      attachment "statement_#{@client.name.downcase.gsub(" ", "_")}.csv"

      # Use Ruby's CSV library for proper CSV generation
      require "csv"
      csv_string = CSV.generate do |csv|
        csv << %w[Date Type Amount Mode Note]

        # Get transactions for this client
        transactions = Smedge::Db.transactions_for_client(@client.id)
        transactions.each do |txn|
          type = txn.is_a?(Smedge::Income) ? "Payment" : "Debit"
          amount = money(txn.amount)
          csv << [txn.date, type, amount, txn.mode, txn.note]
        end
      end

      csv_string
    end

    # ── Customer-facing JSON API ────────────────────────────────────────────
    # JSON endpoints for a mobile/partner frontend. Amounts are integers in
    # paise (1/100 of a rupee) alongside Indian-formatted display strings.
    #
    # NOTE: these endpoints are intentionally served from the same Sinatra
    # process and are NOT authenticated yet — customer auth must be added
    # before exposing them beyond a trusted network.

    # Client summary: identity plus current credit and debit totals.
    get "/api/clients/:id" do
      clients, _ = reload_all
      @clients = clients
      client = clients.find { |c| c.id == params["id"].to_i }
      halt 404 unless client

      json_response(client_payload(client))
    end

    # Client's order history (newest first) with running balance info.
    get "/api/clients/:id/orders" do
      clients, orders = reload_all
      @clients = clients
      @orders = orders
      client = clients.find { |c| c.id == params["id"].to_i }
      halt 404 unless client

      orders = @orders.select { |order| order.client.id == client.id }
                      .sort_by(&:date).reverse
                      .map { |order| order_summary_payload(order) }
      json_response(orders: orders)
    end

    # Client's payment statement: every income and expense, newest first.
    get "/api/clients/:id/payments" do
      clients, orders = reload_all
      @clients = clients
      @orders = orders
      client = clients.find { |c| c.id == params["id"].to_i }
      halt 404 unless client

      payments = (client.credits.map { |payment| payment_payload(payment).merge(type: "income") } +
                  client.debits.map { |payment| payment_payload(payment).merge(type: "expense") })
                 .sort_by { |payment| payment[:date] || "" }
                 .reverse
      json_response(payments: payments)
    end

    # Full order detail: line items, totals, status flags and linked payments.
    get "/api/orders/:id" do
      _, orders = reload_all
      @orders = orders
      order = orders.find { |o| o.id == params["id"].to_i }
      halt 404 unless order

      json_response(order_payload(order))
    end

    not_found do
      status 404
      if request.xhr? || request.accept.include?("application/json") || request.path_info.start_with?("/api/")
        { error: "Not found", path: request.path }.to_json
      else
        erb :not_found
      end
    end

    # Handle Smedge::Error - validation and business logic errors
    error Smedge::Error do
      log_error(env["sinatra.error"])
      status 400
      if request.xhr? || request.accept.include?("application/json")
        { error: "Invalid input. Please review and try again." }.to_json
      else
        erb :error
      end
    end

    # Handle database errors
    error Sequel::DatabaseError do
      log_error(env["sinatra.error"])
      @error = "A database error occurred. Please try again."
      status 500
      if request.xhr? || request.accept.include?("application/json")
        { error: @error }.to_json
      else
        erb :error
      end
    end

    # Handle argument errors (e.g., invalid date parsing)
    error ArgumentError do
      log_error(env["sinatra.error"])
      @error = "Invalid input: #{env["sinatra.error"].message}"
      status 400
      if request.xhr? || request.accept.include?("application/json")
        { error: @error }.to_json
      else
        erb :error
      end
    end

    # Catch-all for unexpected errors
    error do
      log_error(env["sinatra.error"])
      @error = "An unexpected error occurred. Please try again or contact support."
      status 500
      if request.xhr? || request.accept.include?("application/json")
        { error: @error }.to_json
      else
        erb :error
      end
    end

    helpers do
      # Log an error with context
      def log_error(error)
        return unless error
        msg = "[ERROR] #{error.class}: #{error.message}"
        msg += "\n  Path: #{request.path}"
        msg += "\n  Method: #{request.request_method}"
        msg += "\n  Params: #{params.inspect}" unless params.empty?
        msg += "\n  Backtrace: #{error.backtrace.first(5).join("\n  ")}" if error.backtrace
        warn msg
      end

      # Drop in-memory records and reload from the database, so one request
      # never carries over state from another.
      def reload_all
        clients = Smedge::Db.load_clients
        Smedge::Db.load_transactions(clients)
        [clients, Smedge::Db.load_orders(clients)]
      end

      # Per-month income/expense totals (newest month first) for the dashboard
      # cards and the line chart.
      def monthly_summary
        clients = Smedge::Db.load_clients
        transactions = Smedge::Db.load_transactions(clients)
        income = transactions[:incomes].select { |record| record.date && record.amount.cents.positive? }
        expense = transactions[:expenses].select { |record| record.date && record.amount.cents.positive? }

        (income + expense).group_by { |record| record.date.strftime("%B %Y") }
                          .sort_by { |month, _| Date.strptime(month, "%B %Y") }
                          .reverse
                          .map do |month, records|
          month_income = records.select { |record| record.is_a?(Smedge::Income) }
          month_expense = records.select { |record| record.is_a?(Smedge::Expense) }
          {
            month: month,
            income: month_income,
            expense: month_expense,
            income_total: month_income.sum(Money.new(0), &:amount),
            expense_total: month_expense.sum(Money.new(0), &:amount)
          }
        end
      end

      # Convert a user-entered rupee string ("50", "1500.25") to integer paise.
      def rupees_to_paise(value)
        raise Smedge::Error, "Invalid amount: #{value.inspect}" if value.to_s.strip.empty?

        (BigDecimal(value.to_s.strip) * 100).round
      rescue ArgumentError
        raise Smedge::Error, "Invalid amount: #{value.inspect}"
      end

      # Short alias for the Indian-style formatter (strips column padding).
      def money(amount)
        Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(amount).strip
      end

      # Quote a CSV cell when it contains commas, quotes, or newlines so
      # exported statements stay parseable in spreadsheet apps.
      def csv_escape(value)
        value = value.to_s
        if /[",\n\r]/ =~ value then %("#{value.gsub('"', '""')}")
        else
          value
        end
      end

      # Safe HTML link to a client's detail page.
      def link_to_client(client)
        name = Rack::Utils.escape_html(client.name.to_s)
        %(<a href="/clients/#{client.id}">#{name}</a>)
      end

      # Render +payload+ as an API JSON response.
      def json_response(payload)
        content_type :json
        JSON.generate(payload)
      end

      # JSON object for a Money value: integer paise plus a formatted display
      # string in Indian style.
      def money_payload(value)
        money = value.is_a?(Money) ? value : Money.new(value)
        { paise: money.cents, formatted: money(money) }
      end

      def client_payload(client)
        {
          id: client.id,
          name: client.name,
          email: client.email,
          available_credit: money_payload(client.available_credit),
          total_debits: money_payload(client.total_debits)
        }
      end

      def order_summary_payload(order)
        {
          id: order.id,
          order_id: order.order_id,
          date: order.date&.strftime("%d-%m-%Y"),
          status_flags: order.status_flags,
          total: money_payload(order.total_amount_after_discount),
          balance_due: money_payload(order.balance_due)
        }
      end

      def order_payload(order)
        order_summary_payload(order).merge(
          total_before_discount: money_payload(order.total_amount_before_discount),
          discount: money_payload(order.discount),
          received: money_payload(order.total_received),
          items: order.items.map { |item| item_payload(item) },
          payments: order.income.map { |payment| payment_payload(payment) }
        )
      end

      def item_payload(item)
        {
          description: item.item,
          quantity: item.quantity,
          rate: money_payload(item.rate),
          total: money_payload(item.rate * item.quantity)
        }
      end

      def payment_payload(payment)
        {
          amount: money_payload(payment.amount),
          mode: payment.mode,
          note: payment.note,
          date: payment.date&.strftime("%d-%m-%Y"),
          order_id: payment.order_id
        }
      end

      def h(content)
        Rack::Utils.escape_html(content.to_s)
      end

      # "Add payment" URL pre-filled with the client's name.
      def record_payment_href(client)
        "/payments/new?client=#{Rack::Utils.escape_path(client.name.to_s)}"
      end

      # "01-Sep-2026" style date for display.
      def fmt_date(date)
        date&.strftime("%d-%b-%Y")
      end

      # Render the monthly income/expense SVG line chart (dependency-free).
      # summary_data is the monthly_summary output; months are plotted oldest
      # to newest. Returns an empty string when there is no data.
      def line_chart(summary_data)
        rows = summary_data.reverse_each.map do |s|
          {
            month: s[:month],
            short: Date.strptime(s[:month], "%B %Y").strftime("%b %y"),
            income: s[:income_total].cents,
            expense: s[:expense_total].cents
          }
        end
        return "" if rows.empty?

        width = 960
        height = 320
        pad_left = 72
        pad_right = 24
        pad_top = 26
        pad_bottom = 40
        plot_w = width - pad_left - pad_right
        plot_h = height - pad_top - pad_bottom
        max = nice_max(rows.map { |r| [r[:income], r[:expense]].max }.max || 0)
        ticks = 5

        x_at = ->(i) { rows.size == 1 ? pad_left + (plot_w / 2) : pad_left + ((plot_w * i) / (rows.size - 1)) }
        y_at = ->(value) { pad_top + plot_h - (plot_h * value.to_f / max) }

        parts = []
        (0..ticks).each do |t|
          y = pad_top + plot_h - (plot_h * t / ticks)
          parts << %(<line class="gridline" x1="#{pad_left}" y1="#{y}" x2="#{width - pad_right}" y2="#{y}"/>)
          parts << %(<text class="chart-y" x="#{pad_left - 8}" y="#{y + 4}" text-anchor="end">#{compact_label(max * t / ticks)}</text>)
        end
        parts << %(<line class="baseline" x1="#{pad_left}" y1="#{pad_top + plot_h}" x2="#{width - pad_right}" y2="#{pad_top + plot_h}"/>)

        %w[income expense].each do |kind|
          key = kind.to_sym
          color = kind == "income" ? "#16a34a" : "#dc2626"
          coords = rows.each_with_index.map { |r, i| "#{x_at.call(i)},#{y_at.call(r[key])}" }
          parts << %(<polyline class="line #{kind}" fill="none" stroke="#{color}" points="#{coords.join(" ")}"/>)
          rows.each_with_index do |r, i|
            parts << chart_dot(x_at.call(i), y_at.call(r[key]), kind, r)
          end
        end

        rows.each_with_index do |r, i|
          parts << %(<text class="chart-x" x="#{x_at.call(i)}" y="#{height - 16}" text-anchor="middle">#{r[:short]}</text>)
        end

        %(<svg id="monthly-chart" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width} #{height}" role="img" aria-label="Monthly income and expense trend">#{parts.join}</svg>)
      end

      # Invisible circle used as the hover target for the chart tooltip.
      def chart_dot(point_x, point_y, _kind, row)
        %(<circle class="dot" fill="transparent" cx="#{point_x}" cy="#{point_y}" r="8" data-month="#{h(row[:month])}" data-income="#{money(Money.new(row[:income]))}" data-expense="#{money(Money.new(row[:expense]))}"/>)
      end

      # Round a chart maximum up to a "nice" number (1/2/5 x 10^n) so the y-axis
      # gridlines land on round values.
      def nice_max(value)
        return 1 if value <= 0

        magnitude = 10**Math.log10(value).floor
        factor = if (value.to_f / magnitude) <= 1 then 1
                 elsif (value.to_f / magnitude) <= 2 then 2
                 elsif (value.to_f / magnitude) <= 5 then 5
                 else
                   10
                 end
        factor * magnitude
      end

      # Compact paise amount for axis labels: "₹500", "2.5K", "1.2L", "3.0 cr".
      def compact_label(paise)
        rupees = paise.to_f / 100.0
        if rupees >= 1_000_000 then format("%.1f cr", rupees / 1_000_000)
        elsif rupees >= 100_000 then format("%.1fL", rupees / 100_000)
        elsif rupees >= 1_000 then format("%.1fK", rupees / 1_000)
        else
          format("₹%.0f", rupees)
        end
      end
    end

    run! if $PROGRAM_NAME == __FILE__
  end
end
