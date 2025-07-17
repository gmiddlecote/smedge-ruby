# frozen_string_literal: true

# typed: strict

# client.rb

module Smedge
  # Client class
  class Client
    extend T::Sig

    sig { returns(String) }
    attr_accessor :name

    sig { returns(T.nilable(String)) }
    attr_accessor :email

    sig { returns(T::Array[Income]) }
    attr_accessor :credits

    sig { returns(T::Array[Expense]) }
    attr_accessor :debits

    sig { params(name: String, email: T.nilable(String)).void }
    def initialize(name, email = nil)
      @name = name
      @email = email
      @credits = T.let([], T::Array[Income]) # Array of Income < Transaction objects with no order_id
      @debits = T.let([], T::Array[Expense]) # Array of Expense < Transaction objects
    end

    sig { params(income: Income).returns(T::Array[Income]) }
    def add_credit(income)
      @credits << income
    end

    sig { params(expense: Expense).returns(T::Array[Expense]) }
    def add_debit(expense)
      @debits << expense
    end

    sig { returns(Money) }
    def available_credit
      @credits.sum(T.let(Utils::CurrencyFormatter.new_money(0), Money), &:amount)
    end

    sig { params(amount: Money).returns(Money) }
    def use_credit(amount)
      used = T.let(Money.new(0), Money)

      @credits.each do |credit_payment|
        break if used >= amount

        remaining_needed = amount - used
        available = T.let(credit_payment.amount, Money)

        if available >= remaining_needed
          credit_payment.amount -= remaining_needed
          used += remaining_needed
        else
          used += available
          credit_payment.amount = Money.new(0)
        end
      end
      used
    end

    sig { void }
    def details
      puts "Client name: #{name}"
    end
  end
end
