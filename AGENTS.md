# Smedge - Agent Guide

This document helps AI agents understand the Smedge codebase for development tasks.

## Project Overview

**Smedge** is a Ruby-based accounting/invoicing application for managing clients, orders, payments, and expenses. It has both a CLI (`main.rb`) and a web interface (`web/app.rb` - Sinatra).

### Key Features
- Client management (customers, credit tracking)
- Order/sale management with line items
- Payment recording (linked to orders or as account credit)
- Expense tracking (debits against clients)
- Credit system (oldest-first consumption against order balances)
- CSV export for client statements
- Web dashboard with charts
- JSON API endpoints for mobile/partner integration
- HTTP Basic Authentication

## Architecture

```
main.rb                    # CLI entry point
lib/smedge.rb              # Main library entry, loads all domain objects
lib/smedge/
  ├── client.rb            # Customer with credits/debits
  ├── order.rb             # Sale with items, discount, payments
  ├── orderitem.rb         # Line item (description, qty, rate)
  ├── transaction.rb       # Base class for money movements
  ├── income.rb            # Money received (payment)
  ├── expense.rb           # Money paid out (debit)
  ├── services.rb          # Business logic helpers
  └── utils/
       ├── currency_formatter.rb  # Indian-style ₹ formatting
       ├── date_parse.rb          # dd-mm-yyyy parsing
       ├── display_helper.rb      # CLI pretty printing
       └── db.rb                  # SQLite persistence (Sequel ORM)
web/
  ├── app.rb               # Sinatra web app
  └── views/               # ERB templates
```

## Data Model (SQLite via Sequel)

| Table | Key Columns |
|-------|-------------|
| `clients` | id, name (unique), email |
| `orders` | id, client_id (FK), date, discount_paise |
| `order_items` | id, order_id (FK), description, quantity, rate_paise |
| `transactions` | id, client_id (FK), order_id (FK), type ('income'/'expense'), amount_paise, currency, date, mode, note |

## Conventions

- **All amounts stored as paise** (integer) in DB, converted to `Money` objects in domain
- **Indian Rupee (INR)** default currency with Indian-style formatting (1,00,000.00)
- **Date format**: "dd-mm-yyyy" in UI, "yyyy-mm-dd" for HTML inputs
- **Order IDs**: deterministic format `ORD-DDMMYYYY-SSS` (per-date serial)
- **Credit system**: `Client.available_credit` = unspent income; `Order.apply_client_credit` consumes oldest-first

## Key Files for Common Tasks

| Task | Files to Modify |
|------|----------------|
| Add domain logic | `lib/smedge/*.rb` |
| Database schema/migration | `lib/smedge/utils/db.rb` (`init_db`) |
| CLI commands | `main.rb` |
| Web routes | `web/app.rb` |
| Web UI | `web/views/*.erb` |
| Tests | `spec/*.rb` |

## Development Commands

```bash
# Run tests
bundle exec rspec

# Lint
bundle exec rubocop
bundle exec rubocop -A  # Auto-correct

# Run CLI
ruby main.rb                    # Full report
ruby main.rb --add-client "Name" --email "email@example.com"
ruby main.rb --add-sale "Client" --item "Item;Qty;RatePaise" --discount 5000
ruby main.rb --add-payment "Client" --amount 100000 --mode bank

# Run web app (with auth)
SMEDGE_AUTH_USERNAME=admin SMEDGE_AUTH_PASSWORD=changeme ruby web/app.rb
# Or via rackup:
rackup config.ru

# Seed database from YAML
rake db:seed
```

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `SMEDGE_DB` | SQLite database path | `smedge.sqlite` |
| `SMEDGE_SECRET` | Session cookie signing | random |
| `SMEDGE_AUTH_USERNAME` | HTTP Basic auth username | `admin` |
| `SMEDGE_AUTH_PASSWORD` | HTTP Basic auth password | `changeme` |

## Testing

```bash
bundle exec rspec                    # All tests
bundle exec rspec spec/db_spec.rb    # Database tests
bundle exec rspec spec/web_spec.rb   # Web tests
```

Tests use in-memory SQLite (`:memory:`) and seed from `orders.yaml`.

## JSON API Endpoints (Customer-facing)

| Endpoint | Description |
|----------|-------------|
| `GET /api/clients/:id` | Client summary with credit/debit totals |
| `GET /api/clients/:id/orders` | Order history with running balances |
| `GET /api/clients/:id/payments` | Payment statement (income + expense) |
| `GET /api/orders/:id` | Full order detail with items and payments |

> **Note**: JSON API endpoints are NOT authenticated yet - add customer auth before production use.

## Error Handling

Web app has specific handlers:
- `Smedge::Error` → 400 (validation/business logic)
- `Sequel::DatabaseError` → 500
- `ArgumentError` → 400
- Generic → 500

All errors are logged with context (path, method, params, backtrace).

## Extending the Domain

1. Add new model in `lib/smedge/`
2. Require in `lib/smedge.rb`
3. Add table in `Db.init_db`
4. Add CRUD methods in `Db` module
5. Add routes in `web/app.rb`
6. Add views in `web/views/`
7. Write tests in `spec/`

## Git Workflow

- Only `main` branch exists locally and remotely
- Commit directly to main after tests pass
- Remote branches are cleaned up periodically

## Protected Branches

| Branch | Protection | Purpose |
|--------|------------|---------|
| `2025-app` | **Protected** - no force pushes, no deletions | Read-only archive of 2025 application state. **DO NOT DELETE.** |

---

*Last updated: 2026-10-07*