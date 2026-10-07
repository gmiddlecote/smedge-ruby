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
    end

    sig { params(rate: Integer).void }
    def setrate(rate)
      @rate = Utils::CurrencyFormatter.new_money(rate)
    end

    # Line subtotal: rate x quantity.
    sig { returns(Money) }
    def total
      @rate * @quantity
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

    sig { void }
    def displayorder
      formatted_rate = Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(@rate)
      formatted_total = Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(total)

      puts "Item: #{item} Quantity: #{quantity} Rate: #{formatted_rate} Total: #{formatted_total}"
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
