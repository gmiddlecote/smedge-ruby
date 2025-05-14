#!/usr/bin/env ruby
# frozen_string_literal: true

require "pastel"
require "optparse"
require "yaml"

require_relative "lib/smedge"
require_relative "lib/smedge/utils/currency_formatter"
require_relative "lib/smedge/utils/display_helper"

include Smedge::Utils::CurrencyFormatter
include Smedge::Utils::DisplayHelper

pastel = Pastel.new

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: main.rb [options]"

  opts.on("--awaiting-design", "Filter: awaiting design") { options[:awaiting_design] = true }
  opts.on("--awaiting-material", "Filter: awaiting material") { options[:awaiting_material] = true }
  opts.on("--awaiting-print", "Filter: awaiting print") { options[:awaiting_print] = true }
  opts.on("--printed", "Filter: printed") { options[:printed] = true }
  opts.on("--delivered", "Filter: delivered") { options[:delivered] = true }
end.parse!

# Load File
data = YAML.load_file("orders.yaml")

# Create Clients
clients = {}
data["clients"].each do |c|
  client = Smedge::Client.new(c["name"])
  c["payments"].each do |p|
  payment = Smedge::Payment.new(
    client: client,
    amount: p["amount"],
    payment_date: p["payment_date"],
    mode: p["mode"],
    note: p["note"]
  )
  client.add_credit(payment)
  end
  clients[c["name"]] = client
end

# Process orders
data["orders"].each do |order_data|
client = clients[order_data["client"]]
  order = Smedge::Order.new(order_data["date"], client)

  order_data["items"].each do |item_data|
  item = Smedge::OrderItem.new(item_data["description"], item_data["quantity"])
  item.setrate(item_data["rate"])
  order.additem(item)
  end

order_data["flags"]&.each { |flag| order.update_flag(flag.to_sym)}

# Apply filtering if CLI flags are set
next if options.any? && !order_data["flag"].any? { |f| options[f.to_sym]}

print_divider

order.display_order
puts pastel.cyan("Status: #{order.display_flags}\n")

print_available_credit(client, "Before Order")
order.apply_client_credit
print_balance_due(order)
print_available_credit(client, "After Order")
end

print_divider

# clients.each do |name, client|
#   client.credits.each_with_index do |payment, index|
#     payment.display(pastel: pastel, index: index + 1)
#   end
# end

# Smedge::Payment.all()
Smedge::Payment.display_all_grouped_by_client(pastel: pastel)
