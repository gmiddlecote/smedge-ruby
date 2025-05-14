# frozen_string_literal: true

require "bundler/setup"
Bundler.require
# require "date"
# require "tty-table"
# require "money"
# require "i18n"
require_relative "smedge/utils/currency_formatter"
require_relative "smedge/version"
require_relative "smedge/order"
require_relative "smedge/client"
require_relative "smedge/orderitem"
require_relative "smedge/payment"
require_relative "smedge/utils/date_parse"

# setup localization
I18n.available_locales = %i[en en-IN]
I18n.default_locale = :'en-IN'
I18n.locale = :'en-IN'

# configure Money Gem
Money.locale_backend = :i18n
Money.default_currency = Money::Currency.new("INR")
Money.rounding_mode = BigDecimal::ROUND_HALF_UP

# Module Smedge
module Smedge
  class Error < StandardError; end
end
