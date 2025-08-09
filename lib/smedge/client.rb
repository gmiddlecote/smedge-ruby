# frozen_string_literal: true
# typed: strict

module Smedge
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
      load_transactions if id
    end

    # Database operations
    sig { returns(Client) }
    def save
      if @id
        Db.db[:clients].where(id: @id).update(name: @name, email: @email)
      else
        @id = Db.db[:clients].insert(name: @name, email: @email)
      end
      self
    end

    sig { void }
    def load_transactions
      return unless @id

      Db.db[:transactions].where(client_id: @id).each do |t|
        transaction = Transaction.from_db(t)
        if transaction.is_a?(Income)
          @credits << transaction
        else
          @debits << transaction
        end
      end
    end

    sig { params(income: Income).returns(Income) }
    def add_credit(income)
      income.client_id = @id if @id
      @credits << income
      income.save if @id
      income
    end

    sig { params(expense: Expense).returns(Expense) }
    def add_debit(expense)
      expense.client_id = @id if @id
      @debits << expense
      expense.save if @id
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
        credit_payment.save if @id
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

    # Class methods
    class << self
      extend T::Sig

      sig { params(id: Integer).returns(T.nilable(Client)) }
      def find(id)
        row = Db.db[:clients].where(id: id).first
        row ? new(row[:name], row[:email], row[:id]) : nil
      end

      sig { returns(T::Array[Client]) }
      def all
        Db.db[:clients].all.map { |row| new(row[:name], row[:email], row[:id]) }
      end
    end
  end

  class Transaction
    extend T::Sig

    sig { returns(T.nilable(Integer)) }
    attr_reader :id

    sig { returns(T.nilable(Integer)) }
    attr_accessor :client_id

    sig { returns(Money) }
    attr_accessor :amount

    sig { returns(DateTime) }
    attr_reader :created_at

    sig { params(client_id: T.nilable(Integer), amount: Money, id: T.nilable(Integer), created_at: T.nilable(DateTime)).void }
    def initialize(client_id, amount, id = nil, created_at = nil)
      @id = id
      @client_id = client_id
      @amount = amount
      @created_at = created_at || DateTime.now
    end

    sig { returns(self) }
    def save
      raise "Client ID required" unless @client_id

      data = {
        client_id: @client_id,
        amount_cents: @amount.cents,
        currency: @amount.currency.iso_code,
        type: self.class.name.split('::').last.downcase,
        created_at: @created_at
      }

      @id ? Db.db[:transactions].where(id: @id).update(data) : @id = Db.db[:transactions].insert(data)
      self
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(Transaction) }
    def self.from_db(row)
      money = Money.new(row[:amount_cents], row[:currency])
      klass = case row[:type]
              when 'income' then Income
              when 'expense' then Expense
              else raise "Unknown transaction type: #{row[:type]}"
              end

      klass.new(row[:client_id], money, row[:id], row[:created_at])
    end
  end

  class Income < Transaction; end
  class Expense < Transaction; end
end
