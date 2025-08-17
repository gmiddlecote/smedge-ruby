# frozen_string_literal: true

# smedge.rb

require "bundler/setup"
Bundler.require
require "sorbet-runtime"
require "sequel"

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
require_relative "smedge/utils/load_data"
require_relative "smedge/utils/db"

# setup localization
I18n.available_locales = %i[en]
I18n.enforce_available_locales = true
I18n.locale = :en
Money.rounding_mode = BigDecimal::ROUND_HALF_UP
Money.default_formatting_rules = {
  symbol: true,
  thousands_separator: ",",
  decimal_mark: ".",
  symbol_position: :before, # or :after
  sign_before_symbol: true
}

# Module Smedge
module Smedge
  class Error < StandardError; end
end
