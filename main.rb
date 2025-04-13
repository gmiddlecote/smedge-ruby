#!/usr/bin/env ruby
# frozen_string_literal: true

require "pastel"
require "optparse"

require_relative "lib/smedge"
require_relative "lib/smedge/utils/display_helper"

include Smedge::Utils::CurrencyFormatter
include Smedge::Utils::DisplayHelper

Pastel.new

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: main.rb [options]"

  opts.on("--awaiting-design", "Filter: awaiting design") { options[:awaiting_design] = true }
  opts.on("--awaiting-material", "Filter: awaiting material") { options[:awaiting_material] = true }
  opts.on("--awaiting-print", "Filter: awaiting print") { options[:awaiting_print] = true }
  opts.on("--printed", "Filter: printed") { options[:printed] = true }
  opts.on("--delivered", "Filter: delivered") { options[:delivered] = true }
end.parse!

# Setup client
client_ron = Smedge::Client.new("Ron")

# Advance payment
advance_payment1 = Smedge::Payment.new(
  client: client_ron,
  amount: 200_000,
  payment_date: "20-03-20204",
  mode: "online",
  note: "Advance payment"
)
client_ron.add_credit(advance_payment1)

advance_payment2 = Smedge::Payment.new(
  client: client_ron,
  amount: 245_000,
  payment_date: "07-04-20204",
  mode: "online",
  note: "Advance payment"
)
client_ron.add_credit(advance_payment2)

# Setup order 1
order1 = Smedge::Order.new("04-04-2024", client_ron)

orderitem1 = Smedge::OrderItem.new("Horn", 6)
orderitem1.setrate(15_000)
order1.additem(orderitem1)

orderitem2 = Smedge::OrderItem.new("Terminal Cap", 6)
orderitem2.setrate(10_000)
order1.additem(orderitem2)

orderitem3 = Smedge::OrderItem.new("Sign - Speaker Stencil", 1)
orderitem3.setrate(12_000)
order1.additem(orderitem3)

orderitem4 = Smedge::OrderItem.new("Small Angled Speaker", 2)
orderitem4.setrate(15_000)
order1.additem(orderitem4)

order1.update_flag(:printed)
order1.update_flag(:delivered)

order1.display_order
puts pastel.cyan("Status: #{order1.display_flags}\n")

print_available_credit(client_ron, "Before Order")
order1.apply_client_credit
print_balance_due(order1)
print_available_credit(client_ron, "After order")
print_divider

# Setup Order 2
order2 = Smedge::Order.new("26-03-2024", client_ron)

order21 = Smedge::OrderItem.new("Mask", 1)
order21.setrate(50_000)
order2.additem(order21)

order2.update_flag(:printed)
order2.update_flag(:delivered)

order2.display_order
puts pastel.cyan("Status: #{order2.display_flags}\n")

print_available_credit(client_ron, "Before Order")
order2.apply_client_credit
print_balance_due(order2)
print_available_credit(client_ron, "After Order")
print_divider

# Order 3
order3 = Smedge::Order.new("08-04-2024", client_ron)
orderitem31 = Smedge::OrderItem.new("Large Cone Speaker", 2)
orderitem31.setrate(100_000)
order3.additem(orderitem31)

order3.update_flag(:awaiting_material)

order3.display_order
puts pastel.cyan("Status: #{order3.display_flags}\n")

print_available_credit(client_ron, "Before Order")
order3.apply_client_credit
print_balance_due(order3)
print_available_credit(client_ron, "After Order")
print_divider

# Order 4
order4 = Smedge::Order.new("08-04-2024", client_ron)
orderitem41 = Smedge::OrderItem.new("Small slanted speaker", 2)
orderitem41.setrate(15_000)
order4.additem(orderitem41)

orderitem42 = Smedge::OrderItem.new("Large text sign", 1)
orderitem42.setrate(15_000)
order4.additem(orderitem42)

order4.update_flag(:printed)

order4.display_order
puts pastel.cyan("Status: #{order4.display_flags}\n")

print_available_credit(client_ron, "Before Order")
order4.apply_client_credit
print_balance_due(order4)
print_available_credit(client_ron, "After Order")
print_divider
