# frozen_string_literal: true

module Smedge
  # Client class
  class Client
    attr_accessor :name, :credits

    def initialize(name)
      @name = name
      @credits = [] # Array of Payment objects with no order_id
    end

    def add_credit(payment)
      @credits << payment
    end

    def available_credit
      @credits.sum(&:amount)
    end

    def use_credit(amount)
      used = Money.new(0)
      @credits.each do |credit_payment|
        break if used >= amount

        remaining_needed = amount - used
        available = credit_payment.amount

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

    def details
      puts "Client name: #{name}"
    end
  end
end
