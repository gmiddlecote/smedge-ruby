# frozen_string_literal: true

# payment.rb
require "date"
require "money"
require_relative "utils/date_parse"

module Smedge
  # Payment Class
  class Payment
    attr_accessor :client, :amount, :payment_date, :mode, :note, :order_id

    @@all = []

    def initialize(client:, amount: 0.0, payment_date:, mode:, note: "", order_id: nil)
      @client = client
      @amount = Money.new(amount)
      # @payment_date = Date.strptime(payment_date, "%d-%m-%Y")
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

    def display(pastel:nil, index: nil)
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

    def self.display_all_grouped_by_client(pastel: nil)
      grouped = @@all.group_by { |p| p.client.name }
      grand_total = Money.new(0, "INR")

      grouped.each do |client_name, payments|
        valid_payments = payments.select { |p| p.amount.cents > 0 }
        next if valid_payments.empty?

        puts "\n#{pastel&.bold(client_name) || client_name}'s Payments:"
        client_total = Money.new(0, "INR")

        # Group by month and year
        payments_by_month = valid_payments.group_by { |p| p.payment_date.strftime("%B %Y") }

        # month and year
        payments_by_month.each do |month_year, month_payments|
          puts pastel&.cyan("\n#{month_year}") || "\n#{month_year}"
          month_total = Money.new(0, "INR")

          # table
          rows = []
          headers = ["#", "Amount", "Date", "Mode", "Note"]
          month_total = Money.new(0)

          month_payments.each_with_index do |payment, index|
            rows << [
              index + 1,
              format_money_in_indian_style(payment.amount),
              payment.payment_date,
              payment.mode,
              payment.note
            ]
            # payment.display(pastel: pastel, index: index + 1)
            month_total += payment.amount
          end

          table = TTY::Table.new(headers, rows)
          puts table.render(:unicode, padding: [0, 1])

          puts pastel&.yellow("Subtotal: #{format_money_in_indian_style(month_total)}") || "Subtotal: #{format_money_in_indian_style(month_total)}"
          client_total += month_total
        end

        puts pastel&.green("\n#{client_name} Total: #{format_money_in_indian_style(client_total)}") || "\n#{client_name} Total: #{format_money_in_indian_style(client_total)}"
        grand_total += client_total
      end

      puts pastel&.magenta("\nGrand Total: #{format_money_in_indian_style(grand_total)}") || "\nGrand Total: #{format_money_in_indian_style(grand_total)}"
    end

  end
end
