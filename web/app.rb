# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:development, :web)
require "sinatra/base"
require "bigdecimal"
require "securerandom"
require_relative "../lib/smedge"
require_relative "../lib/smedge/services"

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
      enable :sessions
      # Start the SQLite schema/migrations once at boot (this covers both the
      # `ruby web/app.rb` and `rackup config.ru` entry points).
      Smedge::Db.init_db
    end

    # Reload all customers, orders and transactions before each request.
    before do
      @clients, @orders = reload_all
    end

    # Dashboard: summary cards, monthly line chart and recent orders.
    get "/" do
      @recent_orders = @orders.sort_by(&:date).reverse.first(5)
      @summary = monthly_summary
      erb :index
    end

    # List all customers.
    get "/clients" do
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

    # List all orders, newest first.
    get "/orders" do
      @orders = @orders.sort_by(&:date).reverse
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

    get "/sales/new" do
      erb :sales_new
    end

    # Create a sale. Dates arrive as ISO "yyyy-mm-dd" from the HTML date input
    # and are converted to the "dd-mm-yyyy" everywhere else.
    post "/sales" do
      client_name = params["client"].to_s.strip
      raise Smedge::Error, "Customer name is required" if client_name.empty?
      
      date = params["date"].to_s.strip
      raise Smedge::Error, "Sale date is required" if date.empty?
      
      date = Date.parse(date).strftime("%d-%m-%Y")
      items = Smedge::Services.build_items(params["item"])
      raise Smedge::Error, "Add at least one item" if items.empty?
      
      discount = params["discount"].to_s.strip
      discount_paise = discount.empty? ? 0 : rupees_to_paise(discount)
      
      client, = Smedge::Db.find_or_create_client(client_name)
      order = Smedge::Db.create_order(date: date, client: client, discount: discount_paise, items: items)
      session[:notice] = "Sale #{order.order_id} added for #{client.name}"
      redirect "/clients/#{client.id}"
    rescue Smedge::Error, ArgumentError => e
      @error = e.message
      @form = params
      erb :sales_new
    end


    get "/payments/new" do
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
    rescue Smedge::Error, ArgumentError => e
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
      
      csv_string = "Date,Type,Amount,Mode,Note\n"
      
      # Credits (Income)
      Smedge::Db.transactions_for_client(@client.id).each do |txn|
        type = txn.is_a?(Smedge::Income) ? "Payment" : "Debit"
        amount = money(txn.amount)
        csv_string << "#{txn.date},#{type},#{amount},#{txn.mode},#{txn.note}\n"
      end
      
      csv_string
    end


    not_found do
      status 404
      "Page not found"
    end

    helpers do
      # Global error handler for Smedge errors
      error Smedge::Error do
        @error = env["sinatra.error"].message
        erb :error # Or a generic error view
      end

      # Drop in-memory records and reload from the database, so one request
      # never carries over state from another (Income/Expense live in class-level
      # arrays and must be reset first).
      def reload_all
        Smedge::Income.reset_all
        Smedge::Expense.reset_all
        clients = Smedge::Db.load_clients
        Smedge::Db.load_transactions(clients)
        [clients, Smedge::Db.load_orders(clients)]
      end

      # Per-month income/expense totals (newest month first) for the dashboard
      # cards and the line chart.
      def monthly_summary
        income = Smedge::Income.all.select { |record| record.date && record.amount.cents.positive? }
        expense = Smedge::Expense.all.select { |record| record.date && record.amount.cents.positive? }

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

    # ... [Keep existing helpers] ...
    # Delete the old build_items and credit_flow methods
    # def build_items(payload)
    # ...
    # end
    # def credit_flow(client)
    # ...
    # end


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

      # Safe HTML link to a client's detail page.
      def link_to_client(client)
        name = Rack::Utils.escape_html(client.name.to_s)
        %(<a href="/clients/#{client.id}">#{name}</a>)
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
