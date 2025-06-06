# frozen_string_literal: true

module Smedge
  module Utils
    # Currency
    module CurrencyFormatter
      # # Format currency
      # def format_currency(amount)
      #   whole, decimal = format("%.2f", amount).split(".")
      #   # Indian-style comma formatting
      #   if whole.length > 3
      #     last_three = whole[-3, 3]
      #     other_digits = whole[0...-3]
      #     formatted = other_digits.reverse.gsub(/(\d{2})(?=\d)/, '\\1,').reverse
      #     whole = "#{formatted},#{last_three}"
      #   end
      #   "₹#{whole}.#{decimal}"
      # end

      # new money object
      def new_money(amount)
        Money.new(amount, "INR")
      end

      # Add Commas
      def format_money_in_indian_style(money, width: 10, pad_char: ' ')
        money = Money.new(money, "INR") if money.is_a?(Integer) || money.is_a?(Float)

        amount = money.cents / 100.0
        int, decimal = ("%.2f" % amount).split(".")

        int = int.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        int = int.gsub(/(\d+),(\d{2})$/, '\\1,\\2')

        formatted_number = "#{int}.#{decimal}"
        padded = "#{pad_char * (16 - formatted_number.length)}#{formatted_number}"

        "₹#{padded}"
      end
    end
  end
end
