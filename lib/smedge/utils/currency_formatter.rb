# frozen_string_literal: true

module Smedge
  module Utils
    # Currency
    module CurrencyFormatter
      # Format currency
      def format_currency(amount)
        whole, decimal = format("%.2f", amount).split(".")
        # Indian-style comma formatting
        if whole.length > 3
          last_three = whole[-3, 3]
          other_digits = whole[0...-3]
          formatted = other_digits.reverse.gsub(/(\d{2})(?=\d)/, '\\1,').reverse
          whole = "#{formatted},#{last_three}"
        end
        "₹#{whole}.#{decimal}"
      end

      # Add Commas
      def format_money_in_indian_style(money)
        amount = money.cents / 100.0
        int, decimal = ("%.2f" % amount).split(".")

        int = int.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        int = int.gsub(/(\d+),(\d{2})$/, '\\1,\\2')

        "₹#{int}.#{decimal}"
      end
    end
  end
end
