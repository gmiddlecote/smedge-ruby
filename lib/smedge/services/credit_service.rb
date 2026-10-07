# frozen_string_literal: true
# typed: true

require "bigdecimal"

module Smedge
  # Handles client credit ledger: immutable entries, consumption, queries
  class CreditService
    extend T::Sig

    sig { params(value: T.untyped).returns(Integer) }
    def self.rupees_to_paise(value)
      value = value.to_s.strip
      raise Smedge::Error, "Invalid amount: #{value.inspect}" if value.empty?

      (BigDecimal(value) * 100).round
    rescue ArgumentError
      raise Smedge::Error, "Invalid amount: #{value.inspect}"
    end

    # Create a new credit entry (payment received, not linked to order)
    sig { params(client: Client, amount_paise: Integer, date: String, mode: String, note: T.nilable(String)).returns(Income) }
    def self.record_credit(client:, amount_paise:, date:, mode:, note: nil)
      raise Smedge::Error, "Amount must be positive" if amount_paise <= 0

      Income.new(
        client: client,
        amount: amount_paise,
        date: date,
        mode: mode,
        note: note,
        order_id: nil
      )
    end

    # Consume available credit against an amount, returning consumed entries
    # Returns array of { income: Income, consumed_paise: Integer, consumption_entry: Income }
    sig { params(client: Client, amount_paise: Integer).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.consume_credit(client:, amount_paise:)
      raise Smedge::Error, "Amount must be positive" if amount_paise <= 0

      consumed = []
      remaining = amount_paise

      client.credits.each do |credit|
        break if remaining <= 0
        next if credit.amount.cents <= 0
        next if credit.auto_applied_credit?

        available = credit.amount.cents
        consumed_paise = [available, remaining].min

        # Create a new immutable ledger entry for the consumption
        consumption_entry = Income.new(
          client: credit.client,
          amount: consumed_paise,
          date: Date.today.strftime("%d-%m-%Y"),
          mode: "credit",
          note: "Auto-applied to order",
          order_id: nil # Will be set by caller
        )

        consumed << { income: credit, consumed_paise: consumed_paise, consumption_entry: consumption_entry }
        remaining -= consumed_paise
      end

      raise Smedge::Error, "Insufficient credit" if remaining.positive?

      consumed
    end

    # Get all unconsumed credit entries for a client
    sig { params(client: Client).returns(T::Array[Income]) }
    def self.available_entries(client)
      client.credits.select { |c| c.amount.cents.positive? && !c.auto_applied_credit? }
    end

    # Calculate total available credit
    sig { params(client: Client).returns(Money) }
    def self.total_available(client)
      client.credits.sum(Money.new(0), &:amount)
    end

    # Credit flow calculation for orders (used by web dashboard)
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
