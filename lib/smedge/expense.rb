# frozen_string_literal: true

# expense.rb
require_relative "utils/date_parse"
require_relative "utils/currency_formatter"
include Smedge::Utils::CurrencyFormatter

module Smedge
  # Expense Class
  class Expense < Transaction
    @@all = []

    def initialize(date:, amount:, mode:, note:, client: nil)
      super(date, amount, mode, note, client)
      @@all << self
    end

    def self.all
      @@all
    end
  end
end
