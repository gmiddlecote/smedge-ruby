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
  ├── services/
  │   ├── credit_service.rb    # Credit ledger, consumption, queries
  │   ├── order_service.rb     # Order lifecycle, status transitions, credit application
  │   └── payment_service.rb   # Payment processing, linking, overpayments
  └── utils/
       ├── currency_formatter.rb  # Indian-style ₹ formatting
       ├── date_parse.rb          # dd-mm-yyyy parsing
       ├── display_helper.rb      # CLI pretty printing
       └── db.rb                  # SQLite persistence (Sequel ORM)
web/
  ├── app.rb               # Sinatra web app
  └── views/               # ERB templates
db/
  └── migrate/             # Sequel migration files
```

## Data Model (SQLite via Sequel)

| Table | Key Columns |
|-------|-------------|
| `clients` | id, name (unique), email, created_at, updated_at |
| `orders` | id, client_id (FK), date, discount_paise, order_id (unique), created_at, updated_at |
| `order_items` | id, order_id (FK), description, quantity, rate_paise, created_at |
| `transactions` | id, client_id (FK), order_id (FK), type ('income'/'expense'), amount_paise, currency, date, mode, note, created_at, updated_at |
| `credit_ledger_entries` | id, client_id (FK), source_income_id (FK), order_id (FK), amount_paise, entry_type ('credit'/'consumption'/'refund'), note, date, created_at |
| `schema_migrations` | version (PK), applied_at |

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
| Database schema/migration | `lib/smedge/utils/db.rb` (`init_db`), `db/migrate/*.rb` |
| Credit logic | `lib/smedge/services/credit_service.rb` |
| Order lifecycle | `lib/smedge/services/order_service.rb` |
| Payment processing | `lib/smedge/services/payment_service.rb` |
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

## Service Objects

- **CreditService**: Immutable credit ledger management. Handles credit recording, consumption (oldest-first), and queries. Returns new immutable `Income` entries for each consumption.
- **OrderService**: Order lifecycle management. Handles creation, status transitions (awaiting_design → awaiting_material → awaiting_print → printing → printed → delivered), credit application, and transition validation.
- **PaymentService**: Payment processing. Records payments linked to orders or as account credit, handles overpayments creating credit, retrieves payments for orders.
- **Services.build_items / rupees_to_paise / calculate_credit_flow**: Utility functions delegated to CreditService.

## Credit Ledger System

Credits are now tracked immutably via `CreditService`:
- **Recording**: `CreditService.record_credit` creates new `Income` entries (mode: cash/bank, order_id: nil)
- **Consumption**: `CreditService.consume_credit` creates immutable `Income` entries (mode: "credit", note: "Auto-applied to order") linked to orders
- **Audit Trail**: `credit_ledger_entries` table records every credit event (credit/consumption/refund) with source references
- **Queries**: `CreditService.available_entries`, `CreditService.total_available`, `CreditService.calculate_credit_flow`

## Database Migrations

Migrations are in `db/migrate/` and run automatically via `Smedge::Db.init_db`:
- `001_create_schema.rb`: Core tables (clients, orders, order_items, transactions) with FKs, indexes, timestamps
- `002_add_credit_ledger.rb`: Credit ledger table with FKs and indexes

Run migrations manually: `Sequel::Migrator.run(db, "db/migrate")`

## Migrations + FK Enforcement

- `PRAGMA foreign_keys = ON` enabled on every connection
- Migrations run automatically via `Smedge::Db.init_db` (called at boot by CLI/web)
- `schema_migrations` table tracks applied versions
- `reset_schema` drops all tables in FK-safe order and re-runs migrations

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