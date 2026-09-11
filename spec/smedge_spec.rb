# frozen_string_literal: true

RSpec.describe Smedge do
  it "has a version number" do
    expect(Smedge::VERSION).not_to be nil
  end
end

RSpec.describe Smedge::Utils::DateParser do
  it "parses dd-mm-yyyy dates" do
    expect(Smedge::Utils::DateParser.parse("20-03-2025")).to eq(Date.new(2025, 3, 20))
  end

  it "returns nil for invalid or empty dates" do
    expect(Smedge::Utils::DateParser.parse("not-a-date")).to be_nil
    expect(Smedge::Utils::DateParser.parse(nil)).to be_nil
    expect(Smedge::Utils::DateParser.parse("")).to be_nil
  end

  it "returns nil for dates with invalid day or month" do
    expect(Smedge::Utils::DateParser.parse("32-01-2025")).to be_nil
    expect(Smedge::Utils::DateParser.parse("01-13-2025")).to be_nil
  end
end

RSpec.describe Smedge::Utils::CurrencyFormatter do
  it "formats money in Indian style" do
    formatted = Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(123_456, "INR"), width: 8)
    expect(formatted).to eq("₹1,234.56")
  end

  it "handles zero and small amounts" do
    expect(Smedge::Utils::CurrencyFormatter.format_money_in_indian_style(Money.new(0, "INR")).strip).to eq("₹0.00")
  end

end

RSpec.describe Smedge::Client do
  let(:client) { Smedge::Client.new("Ron") }

  it "tracks available credit" do
    income = Smedge::Income.new(
      date: "20-03-2025",
      amount: 200_000,
      mode: "online",
      note: "Advance payment",
      client: client
    )
    client.add_credit(income)
    expect(client.available_credit).to eq(Money.new(200_000, "INR"))
  end

  it "deducts from credit with use_credit" do
    client.add_credit(
      Smedge::Income.new(
        date: "20-03-2025",
        amount: 100_000,
        mode: "online",
        note: "Advance payment",
        client: client
      )
    )

    used = client.use_credit(Money.new(400_00, "INR"))

    expect(used).to eq(Money.new(400_00, "INR"))
    expect(client.available_credit).to eq(Money.new(600_00, "INR"))
  end

  it "consumes multiple credit payments oldest-first" do
    c1 = Smedge::Income.new(date: "01-01-2025", amount: 50_000, mode: "cash", note: "p1", client: client)
    c2 = Smedge::Income.new(date: "02-01-2025", amount: 50_000, mode: "cash", note: "p2", client: client)
    client.add_credit(c1)
    client.add_credit(c2)

    used = client.use_credit(Money.new(70_000, "INR"))
    
    expect(used).to eq(Money.new(70_000, "INR"))
    expect(c1.amount).to eq(Money.new(0, "INR"))
    expect(c2.amount).to eq(Money.new(30_000, "INR"))
    expect(client.available_credit).to eq(Money.new(30_000, "INR"))
  end

  it "returns available amount when requested amount exceeds credit" do
    client.add_credit(Smedge::Income.new(date: "01-01-2025", amount: 10_000, mode: "cash", note: "p1", client: client))
    
    used = client.use_credit(Money.new(15_000, "INR"))
    
    expect(used).to eq(Money.new(10_000, "INR"))
    expect(client.available_credit).to eq(Money.new(0, "INR"))
  end
end

RSpec.describe Smedge::Order do
  let(:client) { Smedge::Client.new("Ron") }

  it "generates sequential order ids per day" do
    Smedge::Order.daily_order_count.clear

    order1 = Smedge::Order.new("04-04-2025", client)
    order2 = Smedge::Order.new("04-04-2025", client)

    expect(order1.order_id).to eq("ORD-04042025-001")
    expect(order2.order_id).to eq("ORD-04042025-002")
  end

  it "computes balance due after discount and payments" do
    order = Smedge::Order.new("04-04-2025", client, 100_00)
    item = Smedge::OrderItem.new("Horn", 6)
    item.setrate(15_000)
    order.add_item(item)

    expect(order.total_amount_before_discount).to eq(Money.new(90_000, "INR"))
    expect(order.balance_due).to eq(Money.new(80_000, "INR"))
  end

  it "handles orders with no items" do
    order = Smedge::Order.new("04-04-2025", client)
    expect(order.total_amount_before_discount).to eq(Money.new(0, "INR"))
    expect(order.balance_due).to eq(Money.new(0, "INR"))
  end
end
