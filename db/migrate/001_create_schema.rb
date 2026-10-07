# frozen_string_literal: true

# Migration: Add GST fields to clients, orders, and order_items
create_table? :clients do
  primary_key :id
  String :name, null: false, unique: true
  String :email
  String :gstin
  String :state
  String :address
  String :city
  String :pincode
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
end

create_table? :orders do
  primary_key :id
  foreign_key :client_id, :clients, null: false, on_delete: :cascade
  Date :date, null: false
  Integer :discount_paise, null: false, default: 0
  String :order_id, null: false, unique: true
  String :place_of_supply
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
end

create_table? :order_items do
  primary_key :id
  foreign_key :order_id, :orders, null: false, on_delete: :cascade
  String :description, null: false
  Integer :quantity, null: false
  Integer :rate_paise, null: false
  String :hsn_code
  String :sac_code
  Integer :gst_rate_percent, default: 18
  Integer :taxable_value_paise, default: 0
  Integer :cgst_paise, default: 0
  Integer :sgst_paise, default: 0
  Integer :igst_paise, default: 0
  Integer :quantity_printed, default: 0
  Integer :quantity_delivered, default: 0
  TrueClass :printing_completed, default: false
  TrueClass :delivery_completed, default: false
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
end

create_table? :transactions do
  primary_key :id
  foreign_key :client_id, :clients, null: false, on_delete: :cascade
  foreign_key :order_id, :orders, on_delete: :set_null
  String :type, null: false # 'income' or 'expense'
  Integer :amount_paise, null: false
  String :currency, null: false, default: "INR"
  Date :date
  String :mode
  String :note
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
end

create_table? :credit_ledger_entries do
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

create_table? :printing_logs do
  primary_key :id
  foreign_key :order_item_id, :order_items, null: false, on_delete: :cascade
  Integer :quantity_printed, null: false, default: 0
  Date :printed_date, null: false
  String :note
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
end

create_table? :delivery_logs do
  primary_key :id
  foreign_key :order_item_id, :order_items, null: false, on_delete: :cascade
  Integer :quantity_delivered, null: false, default: 0
  Date :delivered_date, null: false
  String :note
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
end

# Indexes
begin
  add_index :transactions, :client_id
rescue Sequel::DatabaseError
end

begin
  add_index :transactions, :order_id
rescue Sequel::DatabaseError
end

begin
  add_index :orders, :client_id
rescue Sequel::DatabaseError
end

begin
  add_index :order_items, :order_id
rescue Sequel::DatabaseError
end

begin
  add_index :transactions, :date
rescue Sequel::DatabaseError
end

begin
  add_index :credit_ledger_entries, :client_id
rescue Sequel::DatabaseError
end

begin
  add_index :credit_ledger_entries, :source_income_id
rescue Sequel::DatabaseError
end

begin
  add_index :credit_ledger_entries, :order_id
rescue Sequel::DatabaseError
end

begin
  add_index :credit_ledger_entries, :date
rescue Sequel::DatabaseError
end

begin
  add_index :printing_logs, :order_item_id
rescue Sequel::DatabaseError
end

begin
  add_index :printing_logs, :printed_date
rescue Sequel::DatabaseError
end

begin
  add_index :delivery_logs, :order_item_id
rescue Sequel::DatabaseError
end

begin
  add_index :delivery_logs, :delivered_date
rescue Sequel::DatabaseError
end

begin
  add_index :clients, :gstin
rescue Sequel::DatabaseError
end

begin
  add_index :order_items, :hsn_code
rescue Sequel::DatabaseError
end

begin
  add_index :orders, :place_of_supply
rescue Sequel::DatabaseError
end