# frozen_string_literal: true

require "pastel"
require "tty-font"
require_relative "currency_formatter"
require_relative "../version"

module Smedge
  module Utils
    # Display Helper
    module DisplayHelper
      include CurrencyFormatter

      def pastel
        @pastel ||= Pastel.new
      end

      def print_available_credit(client, context)
        print pastel.inverse("Available Credit - #{context}".ljust(40))
        credit_display = format_money_in_indian_style(client.available_credit)
        if client.available_credit.positive? || client.available_credit.zero?
          puts pastel.green(credit_display.rjust(15))
        else
          puts pastel.red(credit_display.rjust(15))
        end
      end

      def print_balance_due(order)
        print pastel.inverse("Balance Due".ljust(40))
        balance_due = order.balance_due
        if balance_due.zero?
          puts pastel.inverse.green("Fully paid".ljust(15))
        else
          puts pastel.inverse.red(format_money_in_indian_style(balance_due).rjust(15))
        end
      end

      def print_divider
        print "\n"
        80.times { print pastel.bright_yellow("*") }
        print "\n"
      end

      def print_fancy_banner(app_name = "Smedge", width = 80)
        pastel = Pastel.new
        font = TTY::Font.new(:standard)

        banner = font.write(app_name)
        split_lines = banner.split("\n")

        centered_lines = split_lines.map do |line|
          padding = (width - line.length) / 2
          " " * padding + line
        end.join("\n")

        # banner_lines = banner.lines.map { |line| line.rstrip.center(width) }.join("\n")
        version_line = "Version #{Smedge::VERSION}".center(width)

        puts pastel.cyan(centered_lines)
        puts pastel.green(version_line)
      end
    end
  end
end
