## [Unreleased]

### Added
- SQLite persistence via Sequel; the database is built and read at runtime with `rake db:seed` / `rake db:reset` for seeding from `orders.yaml`
- Payment recording: `--add-payment` CLI flag and a web payment form; payments link to orders via an order reference or credit the client's account
- Client credit: available credit and debits per customer, with credit automatically applied to order balances (`apply_client_credit`)
- Sinatra web interface: dashboard, customers, orders, sales and payment forms (`rackup config.ru` on port 9292 or `ruby web/app.rb` on port 4567)
- Monthly income/expense line chart on the dashboard (server-rendered SVG, no JavaScript dependencies)
- Sorbet static types across the library (`# typed:` sigils, method signatures, runtime sig enforcement)

### Changed
- Money amounts renamed from `*_cents` to `*_paise` (`transactions.amount_paise`, `orders.discount_paise`, `order_items.rate_paise`); a startup migration renames legacy columns automatically
- Order IDs regenerate deterministically on every load so payments stay linked to the same order reference
- Sanitized `auto_applied_credit?` to use `note.to_s`, so nil notes no longer crash the report

### Security
- Session cookies are signed with `SMEDGE_SECRET` (a random secret is generated when the environment variable is unset)

## [0.1.0] - 2025-04-02

- Initial release
