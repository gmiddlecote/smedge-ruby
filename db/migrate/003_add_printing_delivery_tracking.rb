# frozen_string_literal: true

# Migration: Add printing and delivery tracking to order_items
create_table :printing_logs do
  primary_key :id
  foreign_key :order_item_id, :order_items, null: false, on_delete: :cascade
  Integer :quantity_printed, null: false, default: 0
  Date :printed_date, null: false
  String :note
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
end

create_table :delivery_logs do
  primary_key :id
  foreign_key :order_item_id, :order_items, null: false, on_delete: :cascade
  Integer :quantity_delivered, null: false, default: 0
  Date :delivered_date, null: false
  String :note
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
end

add_index :printing_logs, :order_item_id
add_index :printing_logs, :printed_date
add_index :delivery_logs, :order_item_id
add_index :delivery_logs, :delivered_date

# Add columns to order_items for quick summary queries
alter_table :order_items do
  add_column :quantity_printed, Integer, default: 0
  add_column :quantity_delivered, Integer, default: 0
  add_column :printing_completed, TrueClass, default: false
  add_column :delivery_completed, TrueClass, default: false
end
