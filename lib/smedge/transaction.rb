# frozen_string_literal: true

# typed: strict

module Smedge
  # Transaction
  class Transaction
    extend T::Sig

    sig { returns(Date) }
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

    def self.display_income_and_expense_by_month(pastel: nil, client_name: nil)
      income_data = Income.all.select { |r| r.date && (client_name.nil? || r.client.name == client_name) }
      expense_data = Expense.all.select { |r| r.date && (client_name.nil? || r.client.name == client_name) }

      grouped = (income_data + expense_data).group_by { |r| r.date.strftime("%B %Y") }

      grand_income = T.let(Money.new(0), Money)
      grand_expense = T.let(Money.new(0), Money)

      grouped.sort_by { |month_year, _| Date.strptime(month_year, "%B %Y") }.each do |month_year, records|
        puts pastel&.on_bright_red("\n#{month_year}") || "\n#{month_year}"

        income = records.select { |r| r.is_a?(Income) && r.amount.cents > 0 }
        expense = records.select { |r| r.is_a?(Expense) && r.amount.cents > 0 }

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
