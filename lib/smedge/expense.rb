# frozen_string_literal: true

# typed: true

# expense.rb
require_relative "utils/date_parse"
require_relative "utils/currency_formatter"

# module Expense
module Smedge
  # Money paid out on a client's behalf (recorded as a debit against them).
  class Expense < Transaction
    extend T::Sig

    def initialize(date:, amount:, mode:, note:, client: nil)
      super(date, amount, mode, note, client)
    end
  end
end
