# frozen_string_literal: true
# typed: strict

module Smedge
  # Client Class
  class Client
    extend T::Sig

    sig { returns(T.nilable(Integer)) }
    attr_reader :id

    sig { returns(String) }
    attr_accessor :name

    sig { returns(T.nilable(String)) }
    attr_accessor :email

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
      puts "Client ID: #{@id}" if @id
      puts "Client name: #{@name}"
      puts "Email: #{@email}" if @email
      puts "Available credit: #{available_credit.format}"
      puts "Total debits: #{@debits.sum(Money.new(0), &:amount).format}"
    end
  end
end
