# frozen_string_literal: true

module Smedge
  class Transaction
    attr_accessor :date, :amount, :mode, :note, :client

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

    def self.display_income_and_expense_by_month(pastel: nil)
      income_data = Income.all.map { |r| r if r.date }.compact
      expense_data = Expense.all.map { |r| r if r.date }.compact

      grouped = (income_data + expense_data).group_by { |r| r.date.strftime("%B %Y") }

      grand_income = Smedge::Utils::CurrencyFormatter.new_money(0)
      grand_expense = Smedge::Utils::CurrencyFormatter.new_money(0)

      grouped.sort_by { |month_year, _| Date.strptime(month_year, "%B %Y") }.each do |month_year, records|
        puts pastel&.on_bright_red("\n#{month_year}") || "\n#{month_year}"

        income = records.select { |r| r.is_a?(Income) && r.amount.cents > 0 }
        expense = records.select { |r| r.is_a?(Expense) && r.amount.cents > 0 }

        income_total = Smedge::Utils::CurrencyFormatter.new_money(0)
        expense_total = Smedge::Utils::CurrencyFormatter.new_money(0)

        if income.any?
          puts pastel&.green("\nIncome:") || "\nIncome:"
          income_table = TTY::Table.new(
            ["#", "Client", "Amount", "Date", "Mode", "Note"],
            income.map.with_index do |r, i|
              income_total += r.amount
              [
                i + 1,
                r.client.name,
                format_money_in_indian_style(r.amount),
                r.date.strftime("%d-%m-%Y"),
                r.mode,
                r.note
              ]
            end
          )
          puts income_table.render(:unicode, padding: [0, 1])
          puts pastel&.yellow("Income Total: #{format_money_in_indian_style(income_total)}") || "Income Total: #{format_money_in_indian_style(income_total)}"
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
                format_money_in_indian_style(r.amount),
                r.date.strftime("%d-%m-%Y"),
                r.mode,
                r.note
              ]
            end
          )
          puts expense_table.render(:unicode, padding: [0, 1])
          puts pastel&.yellow("Expense Total: #{format_money_in_indian_style(expense_total)}") || "Expense Total: #{format_money_in_indian_style(expense_total)}"
        end

        profit = income_total - expense_total
        message = "\nProfit: #{format_money_in_indian_style(profit)}"
        puts pastel ? pastel.bright_blue("\nProfit: #{format_money_in_indian_style(profit)}") : message

        grand_income += income_total
        grand_expense += expense_total
      end

      grand_profit = grand_income - grand_expense
      puts pastel&.magenta("\nNet Income: #{format_money_in_indian_style(grand_income)}") || "\nNet Income: #{format_money_in_indian_style(grand_income)}"
      puts pastel&.magenta("Net Expense: #{format_money_in_indian_style(grand_expense)}") || "Net Expense: #{format_money_in_indian_style(grand_expense)}"
      puts pastel&.bold("\nNet Profit: #{format_money_in_indian_style(grand_profit)}") || "\nNet Profit: #{format_money_in_indian_style(grand_profit)}"

      end
    end
  end
