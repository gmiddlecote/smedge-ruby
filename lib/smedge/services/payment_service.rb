# frozen_string_literal: true
# typed: true

require_relative "credit_service"

module Smedge
  # Handles payment processing: recording, linking to orders, credit creation
  class PaymentService
    extend T::Sig

    # Record a payment linked to an order
    sig do
      params(
        client: Client,
        amount_paise: Integer,
        date: String,
        mode: String,
        note: T.nilable(String),
        order: Order
      ).returns(Income)
    end
    def self.record_payment(client:, amount_paise:, date:, mode:, note: nil, order:)
      raise Smedge::Error, "Amount must be positive" if amount_paise <= 0
      raise Smedge::Error, "Order required" unless order

      income = Income.new(
        client: client,
        amount: amount_paise,
        date: date,
        mode: mode,
        note: note,
        order_id: order.id
      )
      order.add_payment(income)
      income
    end

    # Record a payment as account credit (not linked to order)
    sig do
      params(
        client: Client,
        amount_paise: Integer,
        date: String,
        mode: String,
        note: T.nilable(String)
      ).returns(Income)
    end
    def self.record_credit(client:, amount_paise:, date:, mode:, note: nil)
      CreditService.record_credit(client: client, amount_paise: amount_paise, date: date, mode: mode, note: note)
    end

    # Apply payment to order balance (for overpayments creating credit)
    sig { params(order: Order, amount_paise: Integer).void }
    def self.apply_overpayment(order, amount_paise)
      balance = order.balance_due.cents
      if amount_paise > balance
        overpayment = amount_paise - balance
        CreditService.record_credit(
          client: order.client,
          amount_paise: overpayment,
          date: Date.today.strftime("%d-%m-%Y"),
          mode: "credit",
          note: "Overpayment on order #{order.order_id}"
        )
      end
    end

    # Get all payments for an order
    sig { params(order: Order).returns(T::Array[Income]) }
    def self.payments_for_order(order)
      order.income.select { |i| i.order_id == order.id }
    end

    # Get total paid for an order
    sig { params(order: Order).returns(Money) }
    def self.total_paid(order)
      payments_for_order(order).sum(Money.new(0), &:amount)
    end
  end
end