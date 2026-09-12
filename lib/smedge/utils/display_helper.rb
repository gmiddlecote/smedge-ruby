# frozen_string_literal: true

# typed: true

# display_helper.rb

require "pastel"
require "tty-font"
require_relative "currency_formatter"
require_relative "../version"

module Smedge
  module Utils
    # Pretty CLI decoration: banners, dividers, and credit/balance summaries.
    module DisplayHelper
      extend T::Sig

      module_function

      # Lazily create a single Pastel instance for colored console output.
      # Returned as T.untyped because Pastel's color methods are dynamic
      # (method_missing) and have no static signatures.
      sig { returns(T.untyped) }
      def pastel
        @pastel ||= Pastel.new
      end

      # available credit
      sig { params(client: Client, context: String).void }
      def print_available_credit(client, context)
        print pastel.inverse("Available Credit - #{context}".ljust(40))
        credit_display = Utils::CurrencyFormatter.format_money_in_indian_style(client.available_credit)
        if client.available_credit.positive? || client.available_credit.zero?
          puts pastel.green(credit_display.rjust(15))
        else
          puts pastel.white.on_red(credit_display.rjust(15))
        end
      end

      # balance due
      sig { params(order: Order).void }
      def print_balance_due(order)
        print pastel.inverse("Balance Due".ljust(40))
        balance_due = order.balance_due
        if balance_due.zero?
          puts pastel.inverse.green("Fully paid".rjust(17))
        else
          puts pastel.white.on_red(Utils::CurrencyFormatter.format_money_in_indian_style(balance_due).rjust(15))
        end
      end

      # divider
      sig { void }
      def print_divider
        print "\n"
        80.times { print pastel.bright_yellow("*") }
        print "\n"
      end

      # fancy banner
      sig { params(app_name: String, width: Integer).void }
      def print_fancy_banner(app_name = "Smedge", width = 80)
        pastel = Pastel.new
        font = TTY::Font.new(:standard)

        banner = font.write(app_name)
        split_lines = banner.split("\n")

        centered_lines = split_lines.map do |line|
          padding = (width - line.length) / 2
          (" " * padding) + line
        end.join("\n")

        version_line = "Version #{Smedge::VERSION}".rjust(width)

        puts pastel.cyan(centered_lines)
        puts pastel.green(version_line)
      end
    end
  end
end
