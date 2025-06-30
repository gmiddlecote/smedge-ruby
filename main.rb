#!/usr/bin/env ruby --yjit
# frozen_string_literal: true

require "pastel"
require "optparse"
require "yaml"

require_relative "lib/smedge"
require_relative "lib/smedge/utils/currency_formatter"
require_relative "lib/smedge/utils/display_helper"
require_relative "lib/smedge/utils/load_data"

def main
  include Smedge::Utils::CurrencyFormatter
  include Smedge::Utils::DisplayHelper

  pastel = Pastel.new

  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: main.rb [options]"
    opts.on("--client-name NAME", "Filtered by client name") do |name|
      options[:client_name] = name
    end
  end.parse!

  # Load File
  data = YAML.load_file("orders.yaml")

  # Create Clients
  clients = Smedge::Utils::LoadData.load_clients("orders.yaml")
  Smedge::Utils::LoadData.load_transactions("orders.yaml", clients)

  # heading
  Smedge::Utils::DisplayHelper.print_divider
  Smedge::Utils::DisplayHelper.print_fancy_banner
  Smedge::Utils::DisplayHelper.print_divider

  # Print Receipts from Clients
  puts options[:client_name]
  Smedge::Transaction.display_income_and_expense_by_month(pastel: pastel, client_name: options[:client_name])

  # Print Orders from Clients
  data["orders"].each do |order_data|
    client = clients[order_data["client"]]

    if client.nil?
      warn "No client found #{order_data["client"]}"
      next
    end

    if options[:client_name] && order_data["client"] != options[:client_name]
      next
    end

    order = Smedge::Order.new(order_data["date"], client, order_data["discount"])

    order_data["items"].each do |item_data|
      item = Smedge::OrderItem.new(item_data["description"], item_data["quantity"])
      item.setrate(item_data["rate"])
      order.add_item(item)
    end

    # order_data["flags"]&.each { |flag| order.update_flag(flag.to_sym) }

    # Apply filtering if CLI flags are set
    # next if options.any? && !order_data["flags"]&.any? { |f| options[f.to_sym] }

    Smedge::Utils::DisplayHelper.print_divider

    order.display_order
    # puts pastel.cyan("Status: #{order.display_flags}\n")

    Smedge::Order.print_available_credit(client, "Before Order")
    order.apply_client_credit
    Smedge::Order.print_balance_due(order)
    Smedge::Order.print_available_credit(client, "After Order")
  end

  Smedge::Utils::DisplayHelper.print_divider
end

main if __FILE__ == $PROGRAM_NAME
