## [Unreleased]

### Added
- **GST-Compliant Order Numbers**: Order IDs now follow GST format `ORD/YY-YY/NNNNN` (e.g., `ORD/25-26/00001`) with financial year (Apr-Mar) based serial numbers
- **Per-Line-Item Printing & Delivery Tracking**:
  - `OrderItem#record_printing(quantity, date, note)` and `OrderItem#record_delivery(quantity, date, note)`
  - Per-item progress percentages (`print_progress_percentage`, `delivery_progress_percentage`)
  - Per-item audit logs (`printing_logs`, `delivery_logs`) with date, quantity, and notes
  - Order-level progress: `overall_print_progress`, `overall_delivery_progress`
  - Status flags auto-update: `awaiting_print` → `printing` → `printed` → `delivered`
- **GST Fields for Line Items** (`OrderItem`):
  - `hsn_code`, `sac_code`, `gst_rate_percent` (default 18%)
  - Automatic GST calculation: `calculate_gst(place_of_supply, client_state)`
  - Intra-state (CGST+SGST) vs inter-state (IGST) detection based on place of supply
  - Order-level GST summary: `total_cgst_paise`, `total_sgst_paise`, `total_igst_paise`, `total_gst_paise`, `total_with_gst_paise`
- **Client GST Fields**: `gstin`, `state`, `address`, `city`, `pincode` with helpers `gst_registered?` and `state_code`
- **Order ID Format**: Changed from `ORD-DDMMYYYY-SSS` to GST-compliant `ORD/YY-YY/NNNNN` (e.g., `ORD/25-26/00001`)
- **Printing/Delivery Database Schema**:
  - New tables: `printing_logs`, `delivery_logs` with `order_item_id` FKs
  - `order_items` now track `quantity_printed`, `quantity_delivered`, `printing_completed`, `delivery_completed`
  - New tables `printing_logs` and `delivery_logs` with indexes
- **Service Layer Extraction**:
  - `CreditService`: Immutable credit ledger, oldest-first consumption, audit trail
  - `OrderService`: Order lifecycle, status transitions, credit application
  - `PaymentService`: Payment recording, overpayment handling, credit creation
- **Idempotent Migrations**: All migrations use `create_table?` and `begin/rescue` for indexes
- **Idempotent Seed**: `seed_from_yaml` no longer calls `reset_schema`; assumes schema exists
- **FK Enforcement**: `PRAGMA foreign_keys = ON` on every connection; safe `reset_schema` with `PRAGMA foreign_keys = OFF` during drops
- **HTTP Basic Auth**: `SMEDGE_AUTH_USERNAME` / `SMEDGE_AUTH_PASSWORD` env vars (defaults: admin/changeme)
- **Error Handling**: Specific handlers for `Smedge::Error` (400), `Sequel::DatabaseError` (500), `ArgumentError` (400); JSON/HTML responses based on Accept header
- **CSV Export**: Uses Ruby's `CSV` library for proper escaping
- **Error Logging**: All errors logged with path, method, params, and backtrace
- **New Migration**: `003_add_printing_delivery_tracking.rb` with `printing_logs`, `delivery_logs`, `order_items` columns, and indexes
- **CSV Gem Dependency**: Added `csv` gem for Ruby 3.4+ compatibility

### Changed
- **Order ID Format**: `ORD-DDMMYYYY-SSS` → `ORD/YY-YY/NNNNN` (e.g., `ORD/25-26/00001`)
- **Migration System**: Proper idempotent migrations with `create_table?` and `begin/rescue` for indexes
- **Credit System**: Immutable credit ledger (`CreditService`); consumption creates new immutable entries instead of mutating existing payments
- **Idempotent Migrations**: All migrations use `create_table?` and `begin/rescue` for indexes
- **Idempotent Seed**: `seed_from_yaml` no longer calls `reset_schema`; assumes schema exists
- **Reset Schema Safety**: `PRAGMA foreign_keys = OFF` before dropping tables in reverse FK order
- **In-Memory DB Sharing**: `:memory:` with `cache=shared` for test isolation
- **Error Handling**: Specific handlers for `Smedge::Error` (400), `Sequel::DatabaseError` (500), `ArgumentError` (400); JSON/HTML responses
- **CSV Export**: Uses Ruby's `CSV` library for proper escaping
- **Error Logging**: All errors logged with path, method, params, backtrace

### Fixed
- **Double Migration Issue**: `seed_from_yaml` no longer calls `reset_schema`, preventing duplicate migration runs
- **FK Drop Order**: `reset_schema` disables FKs before dropping tables in reverse dependency order
- **In-Memory DB Sharing**: `:memory:` with `cache=shared` for test isolation
- **Test Fixtures**: Updated order ID regex from `ORD-\d{8}-\d{3}` to `ORD/\d{2}-\d{2}/\d{5}`
- **Order ID Generation**: Now uses financial year (Apr-Mar) with 5-digit serial
- **Credit Service**: Immutable ledger; consumption creates new immutable entries
- **Seed Data**: Uses deterministic GST-compliant order IDs (`ORD/YY-YY/NNNNN`)
- **Web Auth**: Basic Auth with configurable credentials via env vars

### Security
- HTTP Basic Auth on all web routes (`SMEDGE_AUTH_USERNAME` / `SMEDGE_AUTH_PASSWORD`)
- Error responses don't leak stack traces in production (only in development)

## [0.1.0] - 2025-04-02

- Initial release