#!/usr/bin/env ruby --yjit
# frozen_string_literal: true

# main.rb — the Smedge command line interface.
#
# Run with no arguments to print the full report. Use the "add" flags to
# record customers, sales and payments directly, e.g.:
#   ruby main.rb --add-sale "Ron" --item "Poster;100;5000" --discount 2000
#   ruby main.rb --add-payment "Ron" --amount 100000 --mode bank
require "pastel"
require "optparse"

require_relative "lib/smedge"

def main
  pastel = Pastel.new

  # Holds the parsed CLI arguments; "add" flags accumulate entries that are
  # applied in order after options parsing finishes.
  options = { client_name: nil, add_clients: [], add_sales: [], add_payments: [] }

  OptionParser.new do |opts|
    opts.banner = "Usage: main.rb [options]"

    opts.on("--client-name NAME", "Only show reports for this client") do |name|
      options[:client_name] = name
    end

    opts.on("--add-client NAME", "Add a new customer") do |name|
      options[:add_clients] << { name: name, email: nil }
    end

    opts.on("--email EMAIL", "Email address for the most recently added customer") do |email|
      entry = options[:add_clients].last
      raise OptionParser::ParseError, "--email requires a preceding --add-client" unless entry

      entry[:email] = email
    end

    opts.on("--add-sale CLIENT", "Add a sale for CLIENT (created automatically if unknown)") do |name|
      options[:add_sales] << { client: name, date: nil, discount: 0, items: [] }
    end

    opts.on("--add-payment CLIENT", "Record money received from CLIENT") do |name|
      options[:add_payments] << { client: name, amount: nil, mode: nil, note: nil, date: nil, order: nil }
    end

    opts.on("--date DD-MM-YYYY", "Date for the most recently added sale or payment") do |date|
      entry = options[:add_payments].last || options[:add_sales].last
      raise OptionParser::ParseError, "--date requires a preceding --add-sale or --add-payment" unless entry

      entry[:date] = date
    end

    opts.on("--amount PAISE", Integer, "Payment amount in paise for the most recently added payment") do |amount|
      entry = options[:add_payments].last
      raise OptionParser::ParseError, "--amount requires a preceding --add-payment" unless entry

      entry[:amount] = amount
    end

    opts.on("--mode MODE", "Payment mode (e.g. cash, bank) for the most recently added payment") do |mode|
      entry = options[:add_payments].last
      raise OptionParser::ParseError, "--mode requires a preceding --add-payment" unless entry

      entry[:mode] = mode
    end

    opts.on("--note NOTE", "Note for the most recently added payment") do |note|
      entry = options[:add_payments].last
      raise OptionParser::ParseError, "--note requires a preceding --add-payment" unless entry

      entry[:note] = note
    end

    opts.on("--order ORDER_ID", "Order ID the most recently added payment pays for (e.g. ORD-05092026-001)") do |order|
      entry = options[:add_payments].last
      raise OptionParser::ParseError, "--order requires a preceding --add-payment" unless entry

      entry[:order] = order
    end

    opts.on("--discount PAISE", Integer, "Discount in paise for the most recently added sale") do |discount|
      sale = options[:add_sales].last
      raise OptionParser::ParseError, "--discount requires a preceding --add-sale" unless sale

      sale[:discount] = discount
    end

    opts.on("--item DESCRIPTION;QTY;RATE", "Add an item to the most recently added sale (QTY and RATE are integers, RATE is in paise)") do |spec|
      sale = options[:add_sales].last
      raise OptionParser::ParseError, "--item requires a preceding --add-sale" unless sale

      sale[:items] << parse_item(spec)
    end
  end.parse!

  Smedge::Db.init_db

  if options[:add_clients].any? || options[:add_sales].any? || options[:add_payments].any?
    add_clients(options[:add_clients])
    add_sales(options[:add_sales])
    add_payments(options[:add_payments])
    return
  end

  report(pastel, options[:client_name])
end

# Split "DESCRIPTION;QTY;RATE" into a sale item hash (rate in paise).
def parse_item(spec)
  description, quantity, rate = spec.split(";", 3)
  raise Smedge::Error, "Invalid item format, expected DESCRIPTION;QTY;RATE, got: #{spec.inspect}" if description.nil? || quantity.nil? || rate.nil?

  { description: description.strip, quantity: Integer(quantity), rate: Integer(rate) }
rescue ArgumentError
  raise Smedge::Error, "Invalid quantity or rate (must be integers) in: #{spec.inspect}"
end

def add_clients(entries)
  entries.each do |entry|
    client, created = Smedge::Db.find_or_create_client(entry[:name], entry[:email])
    status = created ? "added" : "already exists"
    email = client.email ? " (#{client.email})" : ""
    puts "Customer #{status}: #{client.name}#{email} [id #{client.id}]"
  end
end

def add_sales(entries)
  entries.each do |entry|
    client, = Smedge::Db.find_or_create_client(entry[:client])
    order = Smedge::Db.create_order(
      date: entry[:date],
      client: client,
      discount: entry[:discount],
      items: entry[:items]
    )
    total = Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(order.total_amount_after_discount)
    puts "\nSale added: #{order.order_id} for #{client.name} (total #{total})"
    order.display_order
  end
end

def add_payments(entries)
  entries.each do |entry|
    raise Smedge::Error, "--amount is required for --add-payment #{entry[:client].inspect}" if entry[:amount].nil?

    client, = Smedge::Db.find_or_create_client(entry[:client])
    Smedge::Db.create_transaction(
      client: client,
      amount_paise: entry[:amount],
      date: entry[:date] || Date.today.strftime("%d-%m-%Y"),
      mode: entry[:mode] || "bank",
      note: entry[:note],
      order_ref: entry[:order]
    )
    amount = Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(entry[:amount])).strip
    message = "Payment recorded: #{amount} for #{client.name}"
    message += " against #{entry[:order]}" if entry[:order]
    puts message
  end
end

# Load everything and print the receipts/orders report; optionally restricted
# to a single client. Applies client credit per order while showing balances.
def report(pastel, client_name)
  clients = Smedge::Db.load_clients
  Smedge::Db.load_transactions(clients)
  orders = Smedge::Db.load_orders(clients)

  # heading
  Smedge::Utils::DisplayHelper.print_divider
  Smedge::Utils::DisplayHelper.print_fancy_banner
  Smedge::Utils::DisplayHelper.print_divider

  # Print Receipts from Clients
  Smedge::Transaction.display_income_and_expense_by_month(pastel: pastel, client_name: client_name)

  # Print Orders from Clients
  orders.each do |order|
    next if client_name && order.client.name != client_name

    Smedge::Utils::DisplayHelper.print_divider

    order.display_order

    Smedge::Utils::DisplayHelper.print_available_credit(order.client, "Before Order")
    order.apply_client_credit
    Smedge::Utils::DisplayHelper.print_balance_due(order)
    Smedge::Utils::DisplayHelper.print_available_credit(order.client, "After Order")
  end

  Smedge::Utils::DisplayHelper.print_divider
end

if __FILE__ == $PROGRAM_NAME
  begin
    main
  rescue OptionParser::ParseError, Smedge::Error => e
    warn "ERROR: #{e.message}"
    exit 1
  end
end
