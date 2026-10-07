# frozen_string_literal: true

# Migration: Create initial schema
# Enable foreign key enforcement
run "PRAGMA foreign_keys = ON"

create_table :clients do
  primary_key :id
  String :name, null: false, unique: true
  String :email
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
end

create_table :orders do
  primary_key :id
  foreign_key :client_id, :clients, null: false, on_delete: :cascade
  Date :date, null: false
  Integer :discount_paise, null: false, default: 0
  String :order_id, null: false, unique: true
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
end

create_table :order_items do
  primary_key :id
  foreign_key :order_id, :orders, null: false, on_delete: :cascade
  String :description, null: false
  Integer :quantity, null: false
  Integer :rate_paise, null: false
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
end

create_table :transactions do
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

# Indexes
add_index :transactions, :client_id
add_index :transactions, :order_id
add_index :orders, :client_id
add_index :order_items, :order_id
add_index :transactions, :date
