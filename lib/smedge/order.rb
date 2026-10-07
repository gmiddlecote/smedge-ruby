# frozen_string_literal: true

# typed: true

require "date"
require "tty-table"
require "money"
require "pastel"

module Smedge
  # A sale made to a Client: a dated collection of OrderItems with an optional
  # discount. Payment (Income) records can be attached, giving a balance_due.
  class Order
    extend T::Sig

    # Per-process counter of orders created per date (yyyyMMdd), used to build
    # the human-readable order id like ORD-05092026-001. Reset on every load.
    class << self
      attr_accessor :daily_order_count
    end

    @daily_order_count = Hash.new(0)

    sig { returns(String) }
    attr_accessor :order_id

    sig { returns(T.nilable(Integer)) }
    attr_accessor :id

    sig { returns(T.nilable(Date)) }
    attr_accessor :date

    sig { returns(Client) }
    attr_accessor :client

    sig { returns(T::Array[OrderItem]) }
    attr_accessor :items

    sig { returns(T::Array[Income]) }
    attr_accessor :income

    sig { returns(Hash) }
    attr_accessor :status_flags

    sig { returns(Money) }
    attr_accessor :discount

    # date is a "dd-mm-yyyy" string; discount is an amount in paise.
    sig { params(date: String, client: Client, discount: Integer).void }
    def initialize(date, client, discount = 0)
      @date = Utils::DateParser.parse(date)
      @client = client
      @discount = Utils::CurrencyFormatter.new_money(discount)
      @items = T.let([], T::Array[OrderItem])
      @income = T.let([], T::Array[Income])
      generate_order_id
      @status_flags = {
        awaiting_design: false,
        awaiting_material: false,
        awaiting_print: false,
        printing: false,
        printed: false,
        delivered: false
      }
    rescue ArgumentError => e
      raise Smedge::Error, "Error: #{e.message}"
    end

    def update_flag(flag, value: true)
      raise Smedge::Error, "Invalid status flag: #{flag}" unless @status_flags.key?(flag.to_sym)

      @status_flags[flag.to_sym] = value
    end

    def display_flags
      @status_flags.map { |k, v| "#{k}: #{v ? "✔" : "✖"}" }.join(", ")
    end

    # Attach a received payment to this order. Payments linked to another
    # order (or explicitly tagged for a different one) are rejected.
    def add_payment(income)
      expected_order_id = id || @order_id
      if income.order_id && income.order_id != expected_order_id
        raise Smedge::Error, "Receipt order ID mismatch"
      end

      @income << income
    end

    # Spend the client's available credit against the remaining balance,
    # recording the spent amount as an auto-applied credit payment.
    def apply_client_credit
      amount_to_cover = balance_due
      return if amount_to_cover <= 0

      credit_used_amount = client.use_credit(amount_to_cover)
      return if credit_used_amount.cents <= 0

      @income << Income.new(
        client: @client,
        amount: credit_used_amount.cents,
        date: Date.today.strftime("%d-%m-%Y"),
        mode: "credit",
        note: "Auto-applied to client credit",
        order_id: id || @order_id
      )
    end

    # Sum of payments received against this order.
    def total_received
      @income.sum(&:amount)
    end

    # Sum of all line items (quantity x rate) before any discount.
    def total_amount_before_discount
      @items.map(&:total).reduce(Smedge::Utils::CurrencyFormatter.new_money(0), :+)
    end

    def total_amount_after_discount
      total_amount_before_discount - @discount
    end

    # What the client still owes after discount and received payments.
    def balance_due
      total_amount_after_discount - total_received
    end

    def add_item(item)
      @items << item
    end

    def display_order
      pastel = Pastel.new
      print pastel.white("\nOrder: ")
      print pastel.on_blue("#{@order_id} ")
      print pastel.white("Date: ")
      print pastel.on_blue("#{@date.strftime("%d-%b-%Y")} ")
      print pastel.white("Client: ")
      print pastel.on_blue(client.name.to_s)
      print "\n\n"
      return puts "No order items" if @items.empty?

      rows = build_order_rows

      # Calculate grand total
      grand_total = @items.sum { |item| item.quantity * item.rate }

      # Add seperator and total row
      rows << :separator
      rows << ["", "", "Grand Total", pastel.white(Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(grand_total)))]
      unless @discount.zero?
        rows << ["", "", pastel.bright_yellow("Discount"), pastel.bright_yellow(Utils::CurrencyFormatter.format_money_in_indian_style(@discount))]
        rows << ["", "", pastel.white("Net Total"), pastel.white(Utils::CurrencyFormatter.format_money_in_indian_style(total_amount_after_discount))]
      end
      puts render_table(rows)
    end

    private

    def build_order_rows
      @items.map do |item|
        [
          item.item,
          item.quantity,
          Utils::CurrencyFormatter.format_money_in_indian_style(item.rate),
          Utils::CurrencyFormatter.format_money_in_indian_style(item.quantity * item.rate)
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
      table = TTY::Table.new(header, [:separator] + rows)
      table.render(:unicode, padding: [0, 2, 0, 2], alignments: %i[left right right right])
    end

    public

    # Build "ORD-DDMMYYYY-SSS" using a per-date serial number.
    def generate_order_id
      key = date.strftime("%d%m%Y")
      self.class.daily_order_count[key] += 1
      serial = format("%03d", self.class.daily_order_count[key])
      @order_id = "ORD-#{key}-#{serial}"
    end
  end
end
