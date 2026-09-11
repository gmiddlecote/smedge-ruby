# frozen_string_literal: true

RSpec.describe Smedge::Db do
  around do |example|
    original = ENV["SMEDGE_DB"]
    ENV["SMEDGE_DB"] = ":memory:"
    Smedge::Db.reset_schema
    example.run
  ensure
    ENV["SMEDGE_DB"] = original
  end

  it "seeds clients, transactions, orders and order items from orders.yaml" do
    Smedge::Db.seed_from_yaml(File.join(__dir__, "..", "orders.yaml"))

    expect(Smedge::Db.db[:clients].count).to eq(9)
    expect(Smedge::Db.db[:transactions].count).to eq(26)
    expect(Smedge::Db.db[:orders].count).to eq(20)
    expect(Smedge::Db.db[:order_items].count).to be > 0
  end

  it "loads clients, transactions and orders from the database" do
    Smedge::Db.seed_from_yaml(File.join(__dir__, "..", "orders.yaml"))

    clients = Smedge::Db.load_clients
    expect(clients.map(&:name)).to include("Ron", "Ryan", "Happy Feet School")

    Smedge::Db.load_transactions(clients)
    ron = clients.find { |c| c.name == "Ron" }
    expect(ron.available_credit).to eq(Money.new(954_000, "INR"))

    orders = Smedge::Db.load_orders(clients)
    expect(orders.size).to eq(20)
    expect(orders).to all(be_an(Smedge::Order))
    expect(orders.all? { |order| order.items.any? }).to be(true)
    expect(orders.first.order_id).to match(/\AORD-\d{8}-\d{3}\z/)
  end

  it "creates a new client and returns the persisted one on a second call" do
    client, created = Smedge::Db.find_or_create_client("Jane Doe", "jane@example.com")

    expect(created).to be(true)
    expect(client.id).to be_an(Integer)
    expect(client.name).to eq("Jane Doe")
    expect(client.email).to eq("jane@example.com")

    again, recreated = Smedge::Db.find_or_create_client("Jane Doe", "jane@example.com")
    expect(recreated).to be(false)
    expect(again.id).to eq(client.id)
    expect(Smedge::Db.db[:clients].count).to eq(1)
  end

  it "creates an order with items and discount and persists it" do
    client, = Smedge::Db.find_or_create_client("Ron", "ron@example.com")
    order = Smedge::Db.create_order(
      date: "05-09-2026",
      client: client,
      discount: 5_000,
      items: [{ description: "Speaker", quantity: 2, rate: 150_000 },
              { description: "Cap", quantity: 4, rate: 10_000 }]
    )

    expect(order).to be_an(Smedge::Order)
    expect(order.items.size).to eq(2)
    expect(order.discount).to eq(Money.new(5_000, "INR"))
    expect(order.total_amount_after_discount).to eq(Money.new(335_000, "INR"))
    expect(Smedge::Db.db[:orders].count).to eq(1)
    expect(Smedge::Db.db[:order_items].count).to eq(2)

    reloaded = Smedge::Db.load_orders([client]).first
    expect(reloaded.items.size).to eq(2)
    expect(reloaded.items.first.item).to eq("Speaker")
    expect(reloaded.items.first.quantity).to eq(2)
  end

  it "rejects an invalid sale date" do
    client, = Smedge::Db.find_or_create_client("Ron")
    expect do
      Smedge::Db.create_order(date: "not-a-date", client: client, items: [])
    end.to raise_error(Smedge::Error, /Invalid sale date/)
  end

  it "records a payment that attaches to a linked order on reload" do
    Smedge::Order.daily_order_count = Hash.new(0)
    client, = Smedge::Db.find_or_create_client("Ron")
    order = Smedge::Db.create_order(date: "05-09-2026", client: client, discount: 5000,
                                    items: [{ description: "Speaker", quantity: 2, rate: 150_000 }])
    Smedge::Db.create_transaction(client: client, amount_paise: 100_000, date: "05-09-2026",
                                   mode: "bank", order_id: order.id)


    expect(Smedge::Db.db[:transactions].count).to eq(1)
    expect(Smedge::Db.db[:transactions].first[:order_id]).to eq(order.id)

    Smedge::Income.reset_all
    Smedge::Expense.reset_all
    Smedge::Db.load_transactions([client])
    reloaded = Smedge::Db.load_orders([client]).first
    expect(reloaded.total_received).to eq(Money.new(100_000, "INR"))
    expect(reloaded.balance_due).to eq(Money.new(195_000, "INR"))
  end

  it "records an account-credit payment without an order link" do
    client, = Smedge::Db.find_or_create_client("Ron")
    Smedge::Db.create_transaction(client: client, amount_paise: 50_000, date: "05-09-2026",
                                  mode: "cash", note: "Advance")

    expect(Smedge::Db.db[:transactions].first[:order_id]).to be_nil

    Smedge::Income.reset_all
    Smedge::Expense.reset_all
    Smedge::Db.load_transactions([client])
    expect(client.available_credit).to eq(Money.new(50_000, "INR"))
  end

  it "rejects an invalid payment date" do
    client, = Smedge::Db.find_or_create_client("Ron")
    expect do
      Smedge::Db.create_transaction(client: client, amount_paise: 100, date: "nope", mode: "bank")
    end.to raise_error(Smedge::Error, /Invalid payment date/)
  end
end
