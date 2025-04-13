module Smedge
  # Order  Item class
  class OrderItem
    attr_accessor :item, :quantity, :rate

    def initialize(item, quantity)
      @item = item
      @quantity = quantity
    end

    def setrate(rate)
      @rate = rate
    end

    def displayorder
      puts "Item: #{item} Quantity: #{quantity} Rate: #{rate} Total: #{quantity * rate}"
    end
  end
end
