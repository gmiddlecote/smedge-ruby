# frozen_string_literal: true

require "rack/test"
require_relative "../web/app"

RSpec.describe Smedge::Web do
  include Rack::Test::Methods

  around do |example|
    original = ENV.fetch("SMEDGE_DB", nil)
    ENV["SMEDGE_DB"] = ":memory:"
    Smedge::Db.reset_schema
    Smedge::Db.seed_from_yaml(File.join(__dir__, "..", "orders.yaml"))
    example.run
  ensure
    ENV["SMEDGE_DB"] = original
  end

  def app
    Smedge::Web
  end

  it "serves the dashboard with summary cards" do
    get "/"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Dashboard", "Total Sales")
  end

  it "renders the monthly income/expense line chart on the dashboard" do
    get "/"
    expect(last_response).to be_ok
    expect(last_response.body).to include('id="monthly-chart"', 'class="line income"', 'class="line expense"')
    expect(last_response.body).to include("Income", "Expense")
  end

  it "lists customers" do
    get "/clients"
    expect(last_response).to be_ok
    expect(last_response.body).to include("Ron", "Happy Feet School")
  end

  it "shows a customer detail page with orders" do
    client = Smedge::Db.load_clients.find { |c| c.name == "Ron" }
    get "/clients/#{T.must(client.id)}"
    expect(last_response).to be_ok
    expect(last_response.body).to include("ORD-04042025-001")
  end

  it "returns 404 for an unknown customer" do
    get "/clients/99999"
    expect(last_response.status).to eq(404)
  end

  it "lists all orders" do
    get "/orders"
    expect(last_response).to be_ok
    expect(last_response.body).to include("ORD-04042025-001")
  end

  it "adds a customer via POST" do
    post "/customers", name: "Jane Doe", email: "jane@example.com"
    expect(last_response.status).to eq(302)
    expect(Smedge::Db.db[:clients].count).to eq(10)
    client = Smedge::Db.db[:clients].where(name: "Jane Doe").first
    expect(client[:email]).to eq("jane@example.com")
  end

  it "rejects a customer POST without a name" do
    post "/customers", name: "   "
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Customer name is required")
  end

  it "adds a sale via POST and persists it" do
    post "/sales",
         client: "Ron",
         date: "2026-09-05",
         discount: "50.00",
         item: { description: %w[Speaker Cap], quantity: %w[2 4], rate: %w[1500.00 100.00] }
    expect(last_response.status).to eq(302)
    expect(Smedge::Db.db[:orders].count).to eq(21)
    order = Smedge::Db.db[:orders].order(:id).last
    expect(order[:discount_paise]).to eq(5000)
    expect(Smedge::Db.db[:order_items].where(order_id: order[:id]).count).to eq(2)
  end

  it "renders validation errors on the sale form" do
    post "/sales", client: "Ron", date: "", item: { description: ["x"], quantity: ["1"], rate: ["10"] }
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Sale date is required")
  end

  it "records an account-credit payment via POST" do
    post "/payments", client: "Ron", amount: "1000.00", date: "2026-09-06", mode: "bank", note: "Advance"
    expect(last_response.status).to eq(302)
    expect(Smedge::Db.db[:transactions].count).to eq(27)
    transaction = Smedge::Db.db[:transactions].order(:id).last
    expect(transaction[:amount_paise]).to eq(100_000)
    expect(transaction[:order_id]).to be_nil
  end

  it "records a payment against a sale via POST" do
    post "/sales",
         client: "Ron",
         date: "2026-09-05",
         item: { description: ["Speaker"], quantity: ["2"], rate: ["1500.00"] }
    order = Smedge::Db.db[:orders].order(:id).last

    post "/payments", client: "Ron", amount: "1000.00", date: "2026-09-06", mode: "bank", order_id: order[:id]
    expect(last_response.status).to eq(302)
    expect(Smedge::Db.db[:transactions].where(order_id: order[:id]).count).to eq(1)
    expect(order).not_to be_nil
  end

  it "rejects a payment POST with a negative amount" do
    post "/payments", client: "Ron", amount: "-50", date: "2026-09-06", mode: "bank"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Payment amount must be more than 0")
  end

  it "exports a client statement as CSV" do
    client = Smedge::Db.load_clients.find { |c| c.name == "Ron" }
    get "/clients/#{T.must(client.id)}/export"
    expect(last_response).to be_ok
    expect(last_response.content_type).to include("text/csv")
    expect(last_response.body.lines.first).to eq("Date,Type,Amount,Mode,Note\n")
  end

  it "quotes CSV cells that contain commas" do
    client, = Smedge::Db.find_or_create_client("CSV Client", "csv@example.com")
    Smedge::Db.create_transaction(client: client, amount_paise: 50_000, date: "05-09-2026",
                                  mode: "bank", note: "advance, paid")
    get "/clients/#{client.id}/export"
    expect(last_response.body).to include("\"advance, paid\"")
  end

  it "serves a client summary via the API" do
    client = Smedge::Db.load_clients.find { |c| c.name == "Ron" }
    get "/api/clients/#{T.must(client.id)}"
    expect(last_response).to be_ok
    expect(last_response.content_type).to include("application/json")

    body = JSON.parse(last_response.body)
    expect(body["name"]).to eq("Ron")
    expect(body["available_credit"]).to be_a(Hash)
    expect(body["available_credit"]).to include("paise", "formatted")
  end

  it "serves a client's orders via the API" do
    client = Smedge::Db.load_clients.find { |c| c.name == "Ron" }
    get "/api/clients/#{T.must(client.id)}/orders"
    expect(last_response).to be_ok

    orders = JSON.parse(last_response.body)["orders"]
    expect(orders).to be_an(Array)
    expect(orders.first["order_id"]).to match(/\AORD-\d{8}-\d{3}\z/)
    expect(orders.first["balance_due"]).to include("paise", "formatted")
  end

  it "serves an order detail via the API" do
    client = Smedge::Db.load_clients.find { |c| c.name == "Ron" }
    order = Smedge::Db.load_orders([client]).first
    get "/api/orders/#{T.must(order.id)}"
    expect(last_response).to be_ok

    body = JSON.parse(last_response.body)
    expect(body["items"]).to be_an(Array)
    expect(body["items"].first).to include("description", "quantity", "rate", "total")
    expect(body).to include("status_flags", "balance_due")
  end

  it "returns JSON 404 for an unknown client or order" do
    get "/api/clients/99999"
    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)).to include("error")

    get "/api/orders/99999"
    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)).to include("error")
  end
end
