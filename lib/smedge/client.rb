# frozen_string_literal: true
# typed: strict

module Smedge
  # A customer. Holds everything received from them (credits / incomes) and
  # everything paid out on their behalf (debits / expenses). A client's
  # available credit is the sum of credits minus whatever has been used.
  class Client
    extend T::Sig

    # Database id (nil for objects created outside the persistence layer).
    sig { returns(T.nilable(Integer)) }
    attr_reader :id

    sig { returns(String) }
    attr_accessor :name

    sig { returns(T.nilable(String)) }
    attr_accessor :email

    sig { returns(T::Array[Income]) }
    attr_reader :credits

    sig { returns(T::Array[Expense]) }
    attr_reader :debits

    sig { params(name: String, email: T.nilable(String), id: T.nilable(Integer)).void }
    def initialize(name, email = nil, id = nil)
      @id = id
      @name = name
      @email = email
      @credits = T.let([], T::Array[Income])
      @debits = T.let([], T::Array[Expense])
    end

    sig { params(income: Income).returns(Income) }
    def add_credit(income)
      @credits << income
      income
    end

    sig { params(expense: Expense).returns(Expense) }
    def add_debit(expense)
      @debits << expense
      expense
    end

    # Money received from the client that is still unspent against orders.
    sig { returns(Money) }
    def available_credit
      @credits.sum(T.let(Utils::CurrencyFormatter.new_money(0), Money), &:amount)
    end

    # Total money spent on this client's behalf (expenses recorded against them).
    sig { returns(Money) }
    def total_debits
      @debits.sum(T.let(Utils::CurrencyFormatter.new_money(0), Money), &:amount)
    end

    # Draw down credits balance to pay up to +amount+ of an order's balance.
    # Credits are consumed oldest-first and mutated in place; returns the
    # amount actually covered (may be less than +amount+).
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
      puts "Client ID: #{@id}" if @id
      puts "Client name: #{@name}"
      puts "Email: #{@email}" if @email
      puts "Available credit: #{available_credit.format}"
      puts "Total debits: #{@debits.sum(Money.new(0), &:amount).format}"
    end
  end
end
