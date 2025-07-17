# frozen_string_literal: true

# typed: strict

module Smedge
  # Order  Item class
  class OrderItem
    extend T::Sig

    sig { returns(String) }
    attr_accessor :item

    sig { returns(Integer) }
    attr_accessor :quantity

    sig { returns(Money) }
    attr_reader :rate

    sig { params(item: String, quantity: Integer).void }
    def initialize(item, quantity)
      @item = item
      @quantity = quantity
      @rate = T.let(Smedge::Utils::CurrencyFormatter.new_money(0), Money)
    end

    sig { params(rate: Integer).void }
    def setrate(rate)
      @rate = Utils::CurrencyFormatter.new_money(rate)
    end

    sig { returns(Money) }
    def total
      @rate * @quantity
    end

    sig { void }
    def displayorder
      formatted_rate = Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(@rate)
      formatted_total = Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(total)

      puts "Item: #{item} Quantity: #{quantity} Rate: #{formatted_rate} Total: #{formatted_total}"
    end
  end
end
