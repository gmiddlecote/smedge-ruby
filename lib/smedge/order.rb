# frozen_string_literal: true

require "date"
require "tty-table"
require "money"
require "pastel"

module Smedge
  # order class
  class Order

    # Class-level accessor for the class instance variable
    class << self
      attr_accessor :daily_order_count
    end

    # Initialize class instance variable
    @daily_order_count = Hash.new(0)

    attr_accessor :order_id, :date, :client, :items, :income, :status_flags, :discount

    def initialize(date, client, discount = 0)
      @date = Smedge::Utils::DateParser.parse(date)
      @client = client
      @discount = Smedge::Utils::CurrencyFormatter.new_money(discount || 0)
      @items = []
      @income = []
      self.generate_order_id
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

    def add_payment(income)
      raise Smedge::Error, "Receipt order ID mismatch" if income.order_id && income.order_id != @order_id

      @income << income
    end

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
          order_id: @order_id
        )
    end

    def total_received
      @income.sum(&:amount)
    end

    def total_amount_before_discount
      @items.map(&:total).reduce(Smedge::Utils::CurrencyFormatter.new_money(0), :+)
    end

    def total_amount_after_discount
      total_amount_before_discount - @discount
    end

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
      print pastel.on_blue("#{client.name}")
      print "\n\n"
      return puts "No order items" if @items.empty?

      rows = self.build_order_rows

      # Calculate grand total
      grand_total = @items.sum { |item| item.quantity * item.rate }

      # Add seperator and total row
      rows << :separator
      rows << ["", "", "Grand Total", pastel.white(format_money_in_indian_style(Money.new(grand_total)))]
      unless @discount.zero?
        rows << ["", "", pastel.bright_yellow("Discount"), pastel.bright_yellow(format_money_in_indian_style(@discount))]
        rows << ["", "", pastel.white("Net Total"), pastel.white(format_money_in_indian_style(total_amount_after_discount))]
      end
      puts render_table(rows)
    end

    private

    def build_order_rows
      @items.map do |item|
        [
          item.item,
          item.quantity,
          format_money_in_indian_style(item.rate),
          format_money_in_indian_style(item.quantity * item.rate)
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

    def generate_order_id
      key = date.strftime("%d%m%Y")
      self.class.daily_order_count[key] += 1
      serial = format("%03d", self.class.daily_order_count[key])
      @order_id = "ORD-#{key}-#{serial}"
    end
  end
end
