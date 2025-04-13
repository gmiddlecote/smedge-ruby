# frozen_string_literal: true

require "pastel"
require_relative "currency_formatter"

module Smedge
  module Utils
    # Display Helper
    module DisplayHelper
      include CurrencyFormatter

      def pastel
        @pastel ||= Pastel.new
      end

      def print_available_credit(client, context)
        print pastel.inverse("Available Credit - #{context}".ljust(40))
        credit_display = format_money_in_indian_style(client.available_credit)
        if client.available_credit.positive? || client.available_credit.zero?
          puts pastel.green(credit_display.rjust(15))
        else
          puts pastel.red(credit_display.rjust(15))
        end
      end

      def print_balance_due(order)
        print pastel.inverse("Balance Due".ljust(40))
        balance_due = order.balance_due
        if balance_due.zero?
          puts pastel.inverse.green("Fully paid".ljust(15))
        else
          puts pastel.inverse.red(format_money_in_indian_style(balance_due).rjust(15))
        end
      end

      def print_divider
        puts pastel.bright_yellow("\n**********")
      end
    end
  end
end
