# frozen_string_literal: true

# Migration: Add printing and delivery tracking to order_items
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

# Add indexes idempotently
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

# Add columns to order_items for quick summary queries
# Check if columns exist before adding
unless self.schema(:order_items).any? { |col| col[0] == :quantity_printed }
  alter_table :order_items do
    add_column :quantity_printed, Integer, default: 0
  end
end

unless self.schema(:order_items).any? { |col| col[0] == :quantity_delivered }
  alter_table :order_items do
    add_column :quantity_delivered, Integer, default: 0
  end
end

unless self.schema(:order_items).any? { |col| col[0] == :printing_completed }
  alter_table :order_items do
    add_column :printing_completed, TrueClass, default: false
  end
end

unless self.schema(:order_items).any? { |col| col[0] == :delivery_completed }
  alter_table :order_items do
    add_column :delivery_completed, TrueClass, default: false
  end
end

# Add indexes idempotently
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