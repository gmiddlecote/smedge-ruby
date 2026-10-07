# frozen_string_literal: true

# typed: strict

module Smedge
  # One line of an order: a description, quantity and unit rate.
  # Tracks printing progress and delivery status per line item.
  class OrderItem
    extend T::Sig

    sig { returns(String) }
    attr_accessor :item

    sig { returns(Integer) }
    attr_accessor :quantity

    sig { returns(Money) }
    attr_reader :rate

    # GST fields
    sig { returns(T.nilable(String)) }
    attr_accessor :hsn_code

    sig { returns(T.nilable(String)) }
    attr_accessor :sac_code

    sig { returns(Integer) }
    attr_accessor :gst_rate_percent

    sig { returns(Integer) }
    attr_accessor :taxable_value_paise

    sig { returns(Integer) }
    attr_accessor :cgst_paise

    sig { returns(Integer) }
    attr_accessor :sgst_paise

    sig { returns(Integer) }
    attr_accessor :igst_paise

    # Printing tracking
    sig { returns(Integer) }
    attr_accessor :quantity_printed

    sig { returns(Integer) }
    attr_accessor :quantity_delivered

    sig { returns(T::Boolean) }
    attr_accessor :printing_completed

    sig { returns(T::Boolean) }
    attr_accessor :delivery_completed

    # Printing logs (quantity, date, note)
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    attr_accessor :printing_logs

    # Delivery logs (quantity, date, note)
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    attr_accessor :delivery_logs

    sig { params(item: String, quantity: Integer).void }
    def initialize(item, quantity)
      @item = item
      @quantity = quantity
      @rate = T.let(Smedge::Utils::CurrencyFormatter.new_money(0), Money)
      @quantity_printed = 0
      @quantity_delivered = 0
      @printing_completed = false
      @delivery_completed = false
      @printing_logs = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
      @delivery_logs = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
      @hsn_code = nil
      @sac_code = nil
      @gst_rate_percent = 18
      @taxable_value_paise = 0
      @cgst_paise = 0
      @sgst_paise = 0
      @igst_paise = 0
      @printing_logs = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
      @delivery_logs = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
    end

    sig { params(rate: Integer).void }
    def setrate(rate)
      @rate = Utils::CurrencyFormatter.new_money(rate)
      calculate_gst
    end

    # Line subtotal: rate x quantity.
    sig { returns(Money) }
    def total
      @rate * @quantity
    end

    # Calculate GST based on rate, quantity, and client/order place of supply
    sig { params(place_of_supply: T.nilable(String), client_state: T.nilable(String)).void }
    def calculate_gst(place_of_supply: nil, client_state: nil)
      return if @rate.cents == 0 || @quantity == 0

      @taxable_value_paise = total.cents

      # Determine if IGST or CGST+SGST applies
      # IGST for inter-state, CGST+SGST for intra-state
      is_interstate = place_of_supply && client_state && place_of_supply != client_state

      gst_amount = (@taxable_value_paise * @gst_rate_percent) / 100

      if is_interstate
        @igst_paise = gst_amount
        @cgst_paise = 0
        @sgst_paise = 0
      else
        @cgst_paise = gst_amount / 2
        @sgst_paise = gst_amount - @cgst_paise
        @igst_paise = 0
      end
    end

    # Total GST amount
    sig { returns(Integer) }
    def total_gst_paise
      @cgst_paise + @sgst_paise + @igst_paise
    end

    # Total with GST
    sig { returns(Integer) }
    def total_with_gst_paise
      @taxable_value_paise + total_gst_paise
    end

    # Record printing progress for this item
    # @param quantity [Integer] number of items printed
    # @param date [String] "dd-mm-yyyy" format
    # @param note [String] optional note
    sig { params(quantity: Integer, date: String, note: T.nilable(String)).void }
    def record_printing(quantity, date, note: nil)
      raise Smedge::Error, "Printing quantity must be positive" if quantity <= 0
      raise Smedge::Error, "Cannot print more than ordered quantity" if @quantity_printed + quantity > @quantity

      @quantity_printed += quantity
      @printing_logs << {
        quantity: quantity,
        date: date,
        note: note
      }
      @printing_completed = @quantity_printed >= @quantity
    end

    # Record delivery for this item
    # @param quantity [Integer] number of items delivered
    # @param date [String] "dd-mm-yyyy" format
    # @param note [String] optional note
    sig { params(quantity: Integer, date: String, note: T.nilable(String)).void }
    def record_delivery(quantity, date, note: nil)
      raise Smedge::Error, "Delivery quantity must be positive" if quantity <= 0
      raise Smedge::Error, "Cannot deliver more than printed quantity" if @quantity_delivered + quantity > @quantity_printed

      @quantity_delivered += quantity
      @delivery_logs << {
        quantity: quantity,
        date: date,
        note: note
      }
      @delivery_completed = @quantity_delivered >= @quantity_printed
    end

    # Remaining to print
    sig { returns(Integer) }
    def remaining_to_print
      @quantity - @quantity_printed
    end

    # Remaining to deliver
    sig { returns(Integer) }
    def remaining_to_deliver
      @quantity_printed - @quantity_delivered
    end

    # Print progress percentage
    sig { returns(Float) }
    def print_progress_percentage
      return 0.0 if @quantity.zero?
      (@quantity_printed.to_f / @quantity * 100).round(2)
    end

    # Delivery progress percentage
    sig { returns(Float) }
    def delivery_progress_percentage
      return 0.0 if @quantity_printed.zero?
      (@quantity_delivered.to_f / @quantity_printed * 100).round(2)
    end

    # Line subtotal: rate x quantity.
    sig { returns(Money) }
    def total
      @rate * @quantity
    end

    sig { params(rate: Integer).void }
    def setrate(rate)
      @rate = Utils::CurrencyFormatter.new_money(rate)
      calculate_gst
    end

    sig { void }
    def displayorder
      formatted_rate = Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(@rate)
      formatted_total = Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(total)

      puts "Item: #{item} Quantity: #{quantity} Rate: #{formatted_rate} Total: #{formatted_total}"
      puts "  HSN/SAC: #{@hsn_code || @sac_code || 'N/A'}"
      puts "  GST Rate: #{@gst_rate_percent}%"
      puts "  Taxable Value: #{Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(@taxable_value_paise))}"
      puts "  CGST: #{Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(@cgst_paise))}"
      puts "  SGST: #{Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(@sgst_paise))}"
      puts "  IGST: #{Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(@igst_paise))}"
      puts "  Total with GST: #{Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(total_with_gst_paise))}"
      puts "  Printed: #{quantity_printed}/#{quantity} (#{print_progress_percentage}%)"
      puts "  Delivered: #{quantity_delivered}/#{quantity_printed} (#{delivery_progress_percentage}%)"
      unless printing_logs.empty?
        puts "  Printing Log:"
        printing_logs.each do |log|
          note_str = log[:note] ? "(#{log[:note]})" : ""
          puts "    #{log[:date]}: #{log[:quantity]} pcs #{note_str}"
        end
      end
      return if delivery_logs.empty?
      puts "  Delivery Log:"
      delivery_logs.each do |log|
        note_str = log[:note] ? "(#{log[:note]})" : ""
        puts "    #{log[:date]}: #{log[:quantity]} pcs #{note_str}"
      end
    end
  end
end