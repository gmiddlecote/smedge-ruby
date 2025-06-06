module Smedge
  # Order  Item class
  class OrderItem
    attr_accessor :item, :quantity, :rate

    def initialize(item, quantity)
      @item = item
      @quantity = quantity
      @rate = Smedge::Utils::CurrencyFormatter.new_money(0)
    end

    def setrate(rate)
      @rate = rate
    end

    def total
      Smedge::Utils::CurrencyFormatter.new_money(@quantity * @rate)
    end

    def displayorder
      puts "Item: #{item} Quantity: #{quantity} Rate: #{rate} Total: #{quantity * rate}"
    end
  end
end
