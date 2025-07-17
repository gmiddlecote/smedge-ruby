# frozen_string_literal: true

# income.rb
require_relative "utils/date_parse"
require_relative "utils/currency_formatter"

module Smedge
  # Income Class
  class Income < Transaction
    attr_accessor :order_id

    @@all = []

    def initialize(date:, amount:, mode:, note:, client:, order_id: nil)
      super(date, amount, mode, note, client)
      @order_id = order_id
      @@all << self
    end

    def extra?
      order_id.nil?
    end

    def display(pastel: nil, index: nil)
      heading = index ? "receipt #{index}: " : "receipt:"
      puts pastel&.green(heading) || heading
      puts "Amount: #{@amount}"
      puts "Date: #{@date}"
      puts "Mode: #{@mode}"
      puts "Note: #{@note}"
      # end
    end

    def to_h
      {
        client: @client.name,
        amount: @amount.cents,
        mode: @mode,
        date: @date,
        note: @note,
        order_id: @order_id
      }
    end

    # class method to access all receipts
    def self.all
      @@all
    end

    def self.display_all(pastel: nil)
      puts "\nAll receipts:"
      @@all.each_with_index do |receipt, index|
        receipt.display(pastel: pastel, index: index + 1)
      end
    end

    def auto_applied_credit?
      mode == "credit" && note.include?("Auto-applied")
    end

    def self.display_all_grouped_by_client(pastel: nil)
      grouped = @@all.group_by { |p| p.client.name }
      grand_total = Money.new(0)

      grouped.each do |client_name, receipts|
        valid_receipts = receipts.select { |p| p.amount.cents > 0 && !p.auto_applied_credit? }
        next if valid_receipts.empty?

        puts "\n#{pastel&.bold(client_name) || client_name}'s receipts:"
        client_total = Money.new(0)

        # Split receipts by whether they have a date or not
        dated_receipts = valid_receipts.select { |p| p.date }
        undated_receipts = valid_receipts.reject { |p| p.date }

        # Group by month and year
        receipts_by_month = dated_receipts.group_by { |p| p.date.strftime("%B %Y") }

        receipts_by_month.each do |month_year, month_receipts|
          puts pastel&.cyan("\n#{month_year}") || "\n#{month_year}"

          headers = ["#", "Amount", "Date", "Mode", "Note"]
          rows = []
          month_total = Money.new(0)

          month_receipts.each_with_index do |receipt, index|
            rows << [
              index + 1,
              format_money_in_indian_style(receipt.amount),
              receipt.date,
              receipt.mode,
              receipt.note
            ]
            month_total += receipt.amount
          end

          table = TTY::Table.new(headers, rows)
          puts table.render(:unicode, padding: [0, 1])

          puts pastel&.yellow("Subtotal: #{format_money_in_indian_style(month_total)}") || "Subtotal: #{format_money_in_indian_style(month_total)}"
          client_total += month_total
        end

        # Handle undated receipts
        unless undated_receipts.empty?
          puts pastel&.cyan("\nPending Date") || "\nPending Date"

          headers = ["#", "Amount", "Date", "Mode", "Note"]
          rows = []
          pending_total = Money.new(0)

          undated_receipts.each_with_index do |receipt, index|
            rows << [
              index + 1,
              format_money_in_indian_style(receipt.amount),
              "N/A",
              receipt.mode,
              receipt.note
            ]
            pending_total += receipt.amount
          end

          table = TTY::Table.new(headers, rows)
          puts table.render(:unicode, padding: [0, 1])

          puts pastel&.yellow("Subtotal (Pending): #{format_money_in_indian_style(pending_total)}") || "Subtotal (Pending): #{format_money_in_indian_style(pending_total)}"
          client_total += pending_total
        end

        puts pastel&.green("\n#{client_name} Total: #{format_money_in_indian_style(client_total)}") || "\n#{client_name} Total: #{format_money_in_indian_style(client_total)}"
        grand_total += client_total
      end

      puts pastel&.magenta("\nGrand Total: #{format_money_in_indian_style(grand_total)}") || "\nGrand Total: #{format_money_in_indian_style(grand_total)}"
    end
  end
end
