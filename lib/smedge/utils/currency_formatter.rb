# frozen_string_literal: true

# typed: strict

module Smedge
  module Utils
    # Formatting helpers around the money gem. Amounts are paise everywhere;
    # these produce "₹ 1,00,000.00" style strings with Indian digit grouping.
    module CurrencyFormatter
      extend T::Sig

      # Build a Money value from a paise amount (default currency is INR).
      sig { params(amount: Integer).returns(Money) }
      def self.new_money(amount)
        Money.new(amount)
      end

      # Format +amount+ (Money or Integer paise) with Indian-style thousand
      # grouping, right-padded to +width+ for aligned CLI tables.
      sig do
        params(
          amount: T.any(Money, Integer),
          width: T.nilable(Integer),
          pad_char: T.nilable(String)
        ).returns(String)
      end
      def self.format_money_in_indian_style(amount, width: nil, pad_char: " ")
        amount = Money.new(amount) if amount.is_a?(Integer)

        # Turn a paise amount into a float f of rupees (paise / 100) for formatting.
        amount_with_paise = amount.cents.to_f / 100.0
        int, decimal = format("%.2f", amount_with_paise).split(".")

        # Indian grouping: last 3 digits, then groups of 2 (e.g. 1,00,000).
        int = T.must(int).reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        int = int.gsub(/(\d+),(\d{2})$/, '\\1,\\2')

        formatted_number = "#{int}.#{decimal}"

        padding_length = width ? [0, width - formatted_number.length].max : 0
        pad = T.must(pad_char)
        padded = "#{pad * padding_length}#{formatted_number}"

        "₹#{padded}"
      end
    end
  end
end
