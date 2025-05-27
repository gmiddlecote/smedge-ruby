# frozen_string_literal: true

# payment.rb
require_relative "utils/date_parse"
require_relative "utils/currency_formatter"
include Smedge::Utils::CurrencyFormatter

module Smedge
  # Payment Class
  class Payment
    attr_accessor :client, :amount, :payment_date, :mode, :note, :order_id

    @@all = []

    def initialize(client:, payment_date:, mode:, amount: 0.0, note: "", order_id: nil)
      @client = client
      @amount = Money.new(amount)
      begin
        @payment_date = Smedge::Utils::DateParser.parse(payment_date)
      rescue Date::Error
        warn "Invalid date format: #{payment_date.inspect} for client: #{client.name}"
        @payment_date = nil
      end
      @mode = mode
      @note = note
      @order_id = order_id
      @@all << self
    end

    def extra?
      order_id.nil?
    end

    def display(pastel: nil, index: nil)
      heading = index ? "Payment #{index}: " : "Payment:"
      # if @amount > Money.new(0, "INR")
      puts pastel&.green(heading) || heading
      puts "Amount: #{@amount}"
      puts "Date: #{@payment_date}"
      puts "Mode: #{@mode}"
      puts "Note: #{@note}"
      # end
    end

    def to_h
      {
        client: @client.name,
        amount: @amount.cents,
        payment_date: @payment_date,
        mode: @mode,
        note: @note,
        order_id: @order_id
      }
    end

    # class method to access all payments
    def self.all
      @@all
    end

    def self.display_all(pastel: nil)
      puts "\nAll Payments:"
      @@all.each_with_index do |payment, index|
        payment.display(pastel: pastel, index: index + 1)
      end
    end

    def auto_applied_credit?
      mode == "credit" && note.include?("Auto-applied")
    end

    def self.display_all_grouped_by_client(pastel: nil)
      grouped = @@all.group_by { |p| p.client.name }
      grand_total = Money.new(0)

      grouped.each do |client_name, payments|
        valid_payments = payments.select { |p| p.amount.cents > 0 && !p.auto_applied_credit? }
        next if valid_payments.empty?

        puts "\n#{pastel&.bold(client_name) || client_name}'s Payments:"
        client_total = Money.new(0)

        # Split payments by whether they have a date or not
        dated_payments = valid_payments.select { |p| p.payment_date }
        undated_payments = valid_payments.reject { |p| p.payment_date }

        # Group by month and year
        payments_by_month = dated_payments.group_by { |p| p.payment_date.strftime("%B %Y") }

        payments_by_month.each do |month_year, month_payments|
          puts pastel&.cyan("\n#{month_year}") || "\n#{month_year}"

          headers = ["#", "Amount", "Date", "Mode", "Note"]
          rows = []
          month_total = Money.new(0)

          month_payments.each_with_index do |payment, index|
            rows << [
              index + 1,
              format_money_in_indian_style(payment.amount),
              payment.payment_date,
              payment.mode,
              payment.note
            ]
            month_total += payment.amount
          end

          table = TTY::Table.new(headers, rows)
          puts table.render(:unicode, padding: [0, 1])

          puts pastel&.yellow("Subtotal: #{format_money_in_indian_style(month_total)}") || "Subtotal: #{format_money_in_indian_style(month_total)}"
          client_total += month_total
        end

        # Handle undated payments
        unless undated_payments.empty?
          puts pastel&.cyan("\nPending Date") || "\nPending Date"

          headers = ["#", "Amount", "Date", "Mode", "Note"]
          rows = []
          pending_total = Money.new(0)

          undated_payments.each_with_index do |payment, index|
            rows << [
              index + 1,
              format_money_in_indian_style(payment.amount),
              "N/A",
              payment.mode,
              payment.note
            ]
            pending_total += payment.amount
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

    def self.display_all_grouped_by_month(pastel: nil)
      valid_payments = @@all.select { |p| p.amount.cents > 0 && p.payment_date && !p.auto_applied_credit? }

      payments_by_month = valid_payments.group_by { |p| p.payment_date.strftime("%B %Y") }

      grand_total = Money.new(0)

      payments_by_month.sort_by { |month_year, _| Date.strptime(month_year, "%B %Y") }.each do |month_year, payments|
        puts pastel&.on_bright_red("\n#{month_year}") || "\n#{month_year}"

        headers = ["#", "Client", "Amount", "Date", "Mode", "Note"]
        rows = []
        month_total = Money.new(0)

        payments.each_with_index do |payment, index|
          rows << [
            index + 1,
            payment.client.name,
            format_money_in_indian_style(payment.amount),
            payment.payment_date.strftime("%d-%m-%Y"),
            payment.mode,
            payment.note
          ]
          month_total += payment.amount
        end

        table = TTY::Table.new(headers, rows)
        puts table.render(:unicode, padding: [0, 1])

        puts pastel&.bright_blue("Payments: #{payments.size}") || "Payments: #{payments.size}"
        puts pastel&.yellow("Subtotal: #{format_money_in_indian_style(month_total)}") || "Subtotal: #{format_money_in_indian_style(month_total)}"
        grand_total += month_total
      end

      puts pastel&.magenta("\nGrand Total: #{format_money_in_indian_style(grand_total)}") || "\nGrand Total: #{format_money_in_indian_style(grand_total)}"
    end
  end
end
