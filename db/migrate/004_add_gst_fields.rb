# frozen_string_literal: true

# Migration: Add GST compliance fields
alter_table :clients do
  add_column :gstin, String
  add_column :state, String
end

alter_table :orders do
  add_column :invoice_number, String
  add_column :tax_amount_paise, Integer, default: 0
end

alter_table :order_items do
  add_column :hsn_code, String
end
