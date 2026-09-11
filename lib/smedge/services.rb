# frozen_string_literal: true
# typed: strict

module Smedge
  module Services
    extend T::Sig

    sig { params(payload: T.untyped).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.build_items(payload)
      return [] unless payload.is_a?(Hash)

      descriptions = Array(payload["description"])
      quantities = Array(payload["quantity"])
      rates = Array(payload["rate"])

      descriptions.each_index.filter_map do |i|
        description = descriptions[i].to_s.strip
        quantity = quantities[i].to_s
        rate = rates[i].to_s
        next if description.empty? && quantity.empty? && rate.empty?

        raise Smedge::Error, "Item ##{i + 1}: description is required" if description.empty?

        { description: description, quantity: Integer(quantity), rate: Smedge::Web.rupees_to_paise(rate) }
      end
    rescue ArgumentError
      raise Smedge::Error, "Item quantity must be a whole number"
    end

    sig { params(client: Client, orders: T::Array[Order]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.calculate_credit_flow(client, orders)
      running = client.available_credit
      orders.map do |order|
        balance = order.balance_due
        used = [balance, running].min
        before = running
        running -= used
        { order: order, credit_before: before, credit_after: running, balance_due: balance }
      end
    end
  end
end
