# frozen_string_literal: true
# typed: true

require_relative "credit_service"

module Smedge
  # Handles order lifecycle: creation, status transitions, credit application
  class OrderService
    extend T::Sig

    # Create a new order with items
    sig do
      params(
        date: String,
        client: Client,
        discount_paise: Integer,
        items: T::Array[T::Hash[Symbol, T.untyped]]
      ).returns(Order)
    end
    def self.create_order(date:, client:, discount_paise:, items:)
      order = Order.new(date, client, discount_paise)
      items.each do |item|
        order_item = OrderItem.new(item[:description], item[:quantity])
        order_item.setrate(item[:rate])
        order.add_item(order_item)
      end
      order
    end

    # Apply client's available credit to an order
    # Returns the credit consumption entries created
    sig { params(order: Order).returns(T::Array[Income]) }
    def self.apply_credit(order)
      credit_consumed = CreditService.consume_credit(client: order.client, amount_paise: order.balance_due.cents)
      
      credit_consumed.map do |entry|
        consumption_entry = entry[:consumption_entry]
        consumption_entry.order_id = order.id || order.order_id
        order.income << consumption_entry
        consumption_entry
      end
    end

    # Update order status flag
    sig { params(order: Order, flag: Symbol, value: T::Boolean).void }
    def self.update_status(order, flag, value: true)
      order.update_flag(flag, value: value)
    end

    # Check if order can be transitioned to a status
    sig { params(order: Order, target_status: Symbol).returns(T::Boolean) }
    def self.can_transition?(order, target_status)
      workflow = {
        awaiting_design: [],
        awaiting_material: [:awaiting_design],
        awaiting_print: [:awaiting_design, :awaiting_material],
        printing: [:awaiting_print],
        printed: [:printing],
        delivered: [:printed]
      }
      
      required = workflow[target_status] || []
      required.all? { |req| order.status_flags[req] }
    end

    # Get next available statuses
    sig { params(order: Order).returns(T::Array[Symbol]) }
    def self.available_transitions(order)
      all_statuses = %i[awaiting_design awaiting_material awaiting_print printing printed delivered]
      all_statuses.select { |s| can_transition?(order, s) && !order.status_flags[s] }
    end
  end
end