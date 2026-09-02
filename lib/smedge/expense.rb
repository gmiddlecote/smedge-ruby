# frozen_string_literal: true

# expense.rb
require_relative "utils/date_parse"
require_relative "utils/currency_formatter"

# module Expense
module Smedge
  # Expense Class
  class Expense < Transaction
    class << self
      attr_reader :all
    end

    @all = []

    def initialize(date:, amount:, mode:, note:, client: nil)
      super(date, amount, mode, note, client)
      self.class.all << self
    end
  end
end
