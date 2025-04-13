# frozen_string_literal: true

require "date"
require "tty-table"
require "money"
require "pastel"

module Smedge
  # Order Class
  class Order
    include Smedge::Utils::CurrencyFormatter

    # Class-level accessor for the class instance variable
    class << self
      attr_accessor :daily_order_count
    end

    # Initialize class instance variable
    @daily_order_count = Hash.new(0)

    attr_accessor :order_id, :orderdate, :client, :orderitems, :payments, :status_flags

    def initialize(orderdate, client)
      @orderdate = Date.parse(orderdate)
      @client = client
      @orderitems = []
      @payments = []
      generate_order_id
      @status_flage = {
        awaiting_design: false,
        awaiting_material: false,
        awaiting_print: false,
        printed: false,
        delivered: false
      }
    rescue ArgumentError
      raise Smedge::Error, "Invalid date format: #{orderdate}"
    end

    def update_flag(flag, value: true)
      raise Smedge::Error, "Invalid status flag: #{flag}" unless @status_flage.key?(flag.to_sym)

      @status_flage[flag.to_sym] = value
    end

    def display_flags
      @status_flage.map { |k, v| "#{k}: #{v ? "✔" : "✖"}" }.join(", ")
    end

    def add_payment(payment)
      raise Smedge::Error, "Payment order ID mismatch" if payment.order_id && payment.order_id != @order_id

      @payment << payment
    end

    def apply_client_credit
      total = Money.new(@orderitems.sum { |i| i.quantity * i.rate })
      credit_used_amount = client.use_credit(total)
      @payments << Payment.new(
        client: @client,
        amount: credit_used_amount.cents,
        payment_date: Date.today.to_s,
        mode: "credit",
        note: "Auto-applied to client credit",
        order_id: @order_id
      )
    end

    def total_paid
      @payments.sum(&:amount)
    end

    def balance_due
      total = Money.new(@orderitems.sum { |i| i.quantity * i.rate })
      total - total_paid
    end

    def additem(item)
      @orderitems << item
    end

    def display_order
      pastel = Pastel.new
      puts pastel.bright_yellow("\nOrder: #{@order_id} Date: #{@orderdate.strftime("%d-%b-%Y")} Client: #{client.name}\n")
      return puts "No order items" if @orderitems.empty?

      rows = build_order_rows

      # Calculate grand total
      grand_total = @orderitems.sum { |item| item.quantity * item.rate }

      # Add seperator and total row
      rows << :separator
      rows << ["Grand Total", "", "", pastel.bold(format_money_in_indian_style(Money.new(grand_total)))]
      puts render_table(rows)
    end

    private

    def build_order_rows
      @orderitems.map do |item|
        [
          item.item,
          item.quantity,
          format_money_in_indian_style(Money.new(item.rate)),
          format_money_in_indian_style(Money.new(item.quantity * item.rate))
        ]
      end
    end

    # Render table with sub total column
    def render_table(rows)
      pastel = Pastel.new
      header = [
        pastel.bold.blue("Item"),
        pastel.bold.blue("Quantity"),
        pastel.bold.blue("Rate"),
        pastel.bold.blue("Subtotal")
      ]
      table = TTY::Table.new(header, rows)
      puts table.render(:unicode, padding: [0, 2, 0, 2], alignments: %i[left right right right])
    end

    public

    def generate_order_id
      key = orderdate.strftime("%d%m%Y")
      self.class.daily_order_count[key] += 1
      serial = format("%03d", self.class.daily_order_count[key])
      @order_id = "ORD-#{key}-#{serial}"
    end
  end
end
