# frozen_string_literal: true

# Migration: Add credit ledger entries for immutable credit tracking
create_table :credit_ledger_entries do
  primary_key :id
  foreign_key :client_id, :clients, null: false, on_delete: :cascade
  foreign_key :source_income_id, :transactions, on_delete: :set_null
  foreign_key :order_id, :orders, on_delete: :set_null
  Integer :amount_paise, null: false
  String :entry_type, null: false # 'credit', 'consumption', 'refund'
  String :note
  Date :date, null: false
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
end

add_index :credit_ledger_entries, :client_id
add_index :credit_ledger_entries, :source_income_id
add_index :credit_ledger_entries, :order_id
add_index :credit_ledger_entries, :date
