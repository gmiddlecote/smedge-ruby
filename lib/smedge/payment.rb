# frozen_string_literal: true

# payment.rb
require "date"
require "money"

module Smedge
  # Payment Class
  class Payment
    attr_accessor :client, :amount, :payment_date, :mode, :note, :order_id

    def initialize(client:, amount:, payment_date:, mode:, note: "", order_id: nil)
      @client = client
      @amount = Money.new(amount)
      @payment_date = Date.parse(payment_date)
      @mode = mode
      @note = note
      @order_id = order_id
    end

    def extra?
      order_id.nil?
    end
  end
end
