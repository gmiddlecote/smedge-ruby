# frozen_string_literal: true
# typed: strict

module Smedge
  module Utils
    # Currency
    module CurrencyFormatter
      extend T::Sig

      sig { params(amount: Integer).returns(Money) }
      def self.new_money(amount)
        Money.new(amount)
      end

      sig {
        params(
          amount: T.any(Money, Integer),
          width: T.nilable(Integer),
          pad_char: T.nilable(String)
        ).returns(String) }
      def self.format_money_in_indian_style(amount, width: 16, pad_char: " ")

        amount = Money.new(amount) if amount.is_a?(Integer)

        amount_with_cents = amount.cents.to_f / 100.0
        int, decimal = ("%.2f" % amount_with_cents).split(".")

        int = T.must(int).reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        int = int.gsub(/(\d+),(\d{2})$/, '\\1,\\2')

        formatted_number = "#{int}.#{decimal}"

        effective_width = width || 16
        padding_length = [0, effective_width - formatted_number.length].max
        pad = T.must(pad_char)
        padded = "#{pad * padding_length}#{formatted_number}"

        "₹#{padded}"
      end
    end
  end
end
