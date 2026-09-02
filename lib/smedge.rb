# frozen_string_literal: true
# typed: true

# smedge.rb — entry point for the Smedge library (accounting, orders, reports).

# Load Gemfile-declared dependencies, Sorbet runtime types, and the domain
# model files below so that `require "smedge"` is everything a caller needs.
require "bundler/setup"
require "sorbet-runtime"
T.unsafe(Bundler).require("development")

require_relative "smedge/version"
require_relative "smedge/order"
require_relative "smedge/client"
require_relative "smedge/orderitem"
require_relative "smedge/transaction"
require_relative "smedge/expense"
require_relative "smedge/income"
require_relative "smedge/utils/currency_formatter"
require_relative "smedge/utils/date_parse"
require_relative "smedge/utils/display_helper"
require_relative "smedge/utils/db"

# Restrict I18n to :en (used by the money gem for currency symbols).
I18n.available_locales = %i[en]
I18n.enforce_available_locales = true
I18n.locale = :en

# Money is the currency value type. Amounts are stored as paise (fractional
# units) and rounded half-up; the default currency is the Indian Rupee.
# (1 is BigDecimal::ROUND_HALF_UP — kept as a literal so RBI gaps in the
# bigdecimal gem can't break the type check.)
Money.rounding_mode = 1
Money.default_currency = Money::Currency.new("INR")
Money.default_formatting_rules = {
  symbol: true,
  thousands_separator: ",",
  decimal_mark: ".",
  symbol_position: :before, # or :after
  sign_before_symbol: true
}

# Namespace for all Smedge domain objects.
module Smedge
  # Base error raised for invalid input and model violations; rescued by the
  # CLI and web layers so they can present a friendly message.
  class Error < StandardError; end
end
