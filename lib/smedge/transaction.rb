# frozen_string_literal: true

# typed: strict

module Smedge
  # Base class for money movements (Income received, Expense paid). Holds the
  # amount, date, mode (cash/bank/...) and an optional note for a client.
  class Transaction
    extend T::Sig

    sig { returns(T.nilable(Date)) }
    attr_accessor :date

    sig { returns(Money) }
    attr_accessor :amount

    sig { returns(String) }
    attr_accessor :mode

    sig { returns(T.nilable(String)) }
    attr_accessor :note

    sig { returns(Client) }
    attr_accessor :client

    sig { params(date: String, amount: Integer, mode: String, note: T.nilable(String), client: Client).void }
    def initialize(date, amount, mode, note, client)
      begin
        @date = Smedge::Utils::DateParser.parse(date)
      rescue Date::Error
        warn "Invalid date format: #{date.inspect} for client: #{client.name}"
        @date = nil
      end
      @amount = Smedge::Utils::CurrencyFormatter.new_money(amount)
      @mode = mode
      @note = note
      @client = client
    end

    # CLI report: group transactions by "Month Year", print income and expense
    # tables per month, then running totals and net profit. Optionally filtered
    # to a single client via +client_name+.
    # pastel is kept T.untyped: Pastel's color methods are dynamic (method_missing).
    sig { params(pastel: T.untyped, client_name: T.nilable(String)).void }
    def self.display_income_and_expense_by_month(pastel: nil, client_name: nil)
      income_data = Income.all.select { |r| r.date && (client_name.nil? || r.client.name == client_name) }
      expense_data = Expense.all.select { |r| r.date && (client_name.nil? || r.client.name == client_name) }

      grouped = (income_data + expense_data).group_by { |r| r.date.strftime("%B %Y") }

      grand_income = T.let(Money.new(0), Money)
      grand_expense = T.let(Money.new(0), Money)

      grouped.sort_by { |month_year, _| Date.strptime(month_year, "%B %Y") }.each do |month_year, records|
        puts pastel&.on_bright_red("\n#{month_year}") || "\n#{month_year}"

        income = records.select { |r| r.is_a?(Income) && r.amount.cents.positive? }
        expense = records.select { |r| r.is_a?(Expense) && r.amount.cents.positive? }

        income_total = T.let(Money.new(0), Money)
        expense_total = T.let(Money.new(0), Money)

        if income.any?
          puts pastel&.green("\nIncome:") || "\nIncome:"
          income_table = TTY::Table.new(
            ["#", "Client", "Amount", "Date", "Mode", "Note"],
            income.map.with_index do |r, i|
              income_total += r.amount
              [
                i + 1,
                r.client.name,
                Utils::CurrencyFormatter.format_money_in_indian_style(r.amount),
                r.date.strftime("%d-%m-%Y"),
                r.mode,
                r.note
              ]
            end
          )
          puts income_table.render(:unicode, padding: [0, 1])
          puts pastel&.yellow("Income Total: #{Utils::CurrencyFormatter.format_money_in_indian_style(income_total)}") || "Income Total: #{Utils::CurrencyFormatter.format_money_in_indian_style(income_total)}"
        end

        if expense.any?
          puts pastel&.red("\nExpenses:") || "\nExpenses:"
          expense_table = TTY::Table.new(
            ["#", "Client", "Amount", "Date", "Mode", "Note"],
            expense.map.with_index do |r, i|
              expense_total += r.amount
              [
                i + 1,
                r.client.name,
                Utils::CurrencyFormatter.format_money_in_indian_style(r.amount),
                r.date.strftime("%d-%m-%Y"),
                r.mode,
                r.note
              ]
            end
          )
          puts expense_table.render(:unicode, padding: [0, 1])
          puts pastel&.yellow("Expense Total: #{Utils::CurrencyFormatter.format_money_in_indian_style(expense_total)}") || "Expense Total: #{Utils::CurrencyFormatter.format_money_in_indian_style(expense_total)}"
        end

        profit = income_total - expense_total
        puts pastel ? pastel.bright_blue("\nProfit: #{Utils::CurrencyFormatter.format_money_in_indian_style(profit)}") : "\nProfit: #{Utils::CurrencyFormatter.format_money_in_indian_style(profit)}"

        grand_income += income_total
        grand_expense += expense_total
      end

      grand_profit = grand_income - grand_expense
      puts pastel&.magenta("\nNet Income: #{Utils::CurrencyFormatter.format_money_in_indian_style(grand_income)}") || "\nNet Income: #{Utils::CurrencyFormatter.format_money_in_indian_style(grand_income)}"
      puts pastel&.magenta("Net Expense: #{Utils::CurrencyFormatter.format_money_in_indian_style(grand_expense)}") || "Net Expense: #{Utils::CurrencyFormatter.format_money_in_indian_style(grand_expense)}"
      puts pastel&.bold("\nNet Profit: #{Utils::CurrencyFormatter.format_money_in_indian_style(grand_profit)}") || "\nNet Profit: #{Utils::CurrencyFormatter.format_money_in_indian_style(grand_profit)}"
    end
  end
end
