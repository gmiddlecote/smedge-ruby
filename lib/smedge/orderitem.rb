# typed: true

module Smedge
  # Order  Item class
  class OrderItem
    extend T::Sig

    attr_accessor :item, :quantity, :rate

    sig { params(item: String, quantity: Integer).void }
    def initialize(item, quantity)
      @item = item
      @quantity = quantity
      @rate = Smedge::Utils::CurrencyFormatter.new_money(0)
    end

    sig { params(rate: Integer).void }
    def setrate(rate)
      @rate = rate
    end

    sig { returns(Money) }
    def total
      Smedge::Utils::CurrencyFormatter.new_money(@quantity * @rate)
    end

    sig { void }
    def displayorder
      puts "Item: #{item} Quantity: #{quantity} Rate: #{rate} Total: #{quantity * rate}"
    end
  end
end
