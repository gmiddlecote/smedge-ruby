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

    # Per-process counter of orders created per financial year (FY), used to build
    # the GST-compliant order id like ORD/24-25/00001. Reset on every load.
    class << self
      attr_accessor :fy_order_count
    end

    @fy_order_count = Hash.new(0)

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

    # GST fields
    sig { returns(T.nilable(String)) }
    attr_accessor :place_of_supply

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
      @place_of_supply = client.state
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

    # Record printing for a specific item in this order
    sig { params(item_description: String, quantity: Integer, date: String, note: T.nilable(String)).void }
    def record_item_printing(item_description, quantity, date, note: nil)
      item = @items.find { |i| i.item == item_description }
      raise Smedge::Error, "Item not found: #{item_description}" unless item
      item.record_printing(quantity, date, note: note)
      update_printing_status
    end

    # Record delivery for a specific item in this order
    sig { params(item_description: String, quantity: Integer, date: String, note: T.nilable(String)).void }
    def record_item_delivery(item_description, quantity, date, note: nil)
      item = @items.find { |i| i.item == item_description }
      raise Smedge::Error, "Item not found: #{item_description}" unless item
      item.record_delivery(quantity, date, note: note)
      update_delivery_status
    end

    # Update printing status flag based on items
    def update_printing_status
      all_printed = @items.all?(&:printing_completed)
      any_printing = @items.any? { |i| i.quantity_printed.positive? }
      @status_flags[:awaiting_print] = !any_printing
      @status_flags[:printing] = any_printing && !all_printed
      @status_flags[:printed] = all_printed
    end

    # Update delivery status flag based on items
    def update_delivery_status
      all_delivered = @items.all? { |i| i.delivery_completed && i.quantity_printed.positive? }
      @status_flags[:delivered] = all_delivered
    end

    # Total printed quantity across all items
    sig { returns(Integer) }
    def total_printed
      @items.sum(&:quantity_printed)
    end

    # Total delivered quantity across all items
    sig { returns(Integer) }
    def total_delivered
      @items.sum(&:quantity_delivered)
    end

    # Overall printing progress percentage
    sig { returns(Float) }
    def overall_print_progress
      total_qty = @items.sum(&:quantity)
      return 0.0 if total_qty.zero?
      (total_printed.to_f / total_qty * 100).round(2)
    end

    # Overall delivery progress percentage
    sig { returns(Float) }
    def overall_delivery_progress
      tp = total_printed
      return 0.0 if tp.zero?
      (total_delivered.to_f / tp * 100).round(2)
    end

    # Calculate GST for all items based on place of supply
    sig { void }
    def calculate_gst
      @items.each do |item|
        item.calculate_gst(place_of_supply: @place_of_supply, client_state: @client&.state)
      end
    end

    # Total taxable value across all items
    sig { returns(Integer) }
    def total_taxable_value_paise
      @items.sum(&:taxable_value_paise)
    end

    # Total CGST across all items
    sig { returns(Integer) }
    def total_cgst_paise
      @items.sum(&:cgst_paise)
    end

    # Total SGST across all items
    sig { returns(Integer) }
    def total_sgst_paise
      @items.sum(&:sgst_paise)
    end

    # Total IGST across all items
    sig { returns(Integer) }
    def total_igst_paise
      @items.sum(&:igst_paise)
    end

    # Total GST across all items
    sig { returns(Integer) }
    def total_gst_paise
      @items.sum(&:total_gst_paise)
    end

    # Total with GST across all items
    sig { returns(Integer) }
    def total_with_gst_paise
      @items.sum(&:total_with_gst_paise)
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
      puts "  GSTIN: #{client.gstin}" if client.gst_registered?
      puts "  State: #{client.state}" if client.state
      puts "  Place of Supply: #{place_of_supply}" if place_of_supply
      print "\n\n"
      return puts "No order items" if @items.empty?

      rows = build_order_rows

      # Calculate grand total
      grand_total = @items.sum { |item| item.quantity * item.rate }

      # Add separator and total row
      rows << :separator
      rows << ["", "", "Grand Total", pastel.white(Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(grand_total)))]
      unless @discount.zero?
        rows << ["", "", pastel.bright_yellow("Discount"), pastel.bright_yellow(Utils::CurrencyFormatter.format_money_in_indian_style(@discount))]
        rows << ["", "", pastel.white("Net Total"), pastel.white(Utils::CurrencyFormatter.format_money_in_indian_style(total_amount_after_discount))]
      end
      puts render_table(rows)

      # GST Summary
      if total_gst_paise > 0
        puts "\n  GST Summary:"
        puts "  Taxable Value: #{Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(total_taxable_value_paise))}"
        puts "  CGST: #{Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(total_cgst_paise))}"
        puts "  SGST: #{Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(total_sgst_paise))}"
        puts "  IGST: #{Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(total_igst_paise))}"
        puts "  Total GST: #{Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(total_gst_paise))}"
        puts "  Grand Total (with GST): #{Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(total_with_gst_paise))}"
      end

      # Printing/Delivery Summary
      if total_printed > 0 || total_delivered > 0
        puts "\n  Production Summary:"
        puts "  Total Printed: #{total_printed} (#{overall_print_progress}%)"
        puts "  Total Delivered: #{total_delivered} (#{overall_delivery_progress}%)"
      end
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

    # Build "ORD/YY-YY/NNNNN" using a per-financial-year serial number.
    def generate_order_id
      fy_start_year = date.month >= 4 ? date.year : date.year - 1
      fy_end_year = fy_start_year + 1
      fy_suffix = "#{fy_start_year.to_s[-2, 2]}-#{fy_end_year.to_s[-2, 2]}"

      fy_key = "FY#{fy_suffix}"
      self.class.fy_order_count ||= Hash.new(0)
      self.class.fy_order_count[fy_key] += 1
      serial = format("%05d", self.class.fy_order_count[fy_key])
      @order_id = "ORD/#{fy_suffix}/#{serial}"
    end
  end
end