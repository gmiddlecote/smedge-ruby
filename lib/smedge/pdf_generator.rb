# frozen_string_literal: true

# typed: true

require "prawn"
require "prawn/table"

module Smedge
  # PDF generation for receipts and invoices
  module PdfGenerator
    extend T::Sig
    extend self

    # Generate a receipt PDF for an order with payments
    sig { params(order: Order, payments: T::Array[Income]).returns(String) }
    def receipt(order, payments)
      Prawn::Document.new(page_size: "A4", margin: 40) do |pdf|
        setup_fonts(pdf)
        receipt_heading(pdf)
        order_details(pdf, order)
        items_table(pdf, order)
        totals_table(pdf, order)
        payments_section(pdf, payments)
        deliveries_section(pdf, order)
        document_footer(pdf, "receipt")
      end.render
    end

    # Generate an invoice PDF for an order (for unpaid/pending orders)
    sig { params(order: Order).returns(String) }
    def invoice(order)
      Prawn::Document.new(page_size: "A4", margin: 40) do |pdf|
        setup_fonts(pdf)
        invoice_heading(pdf)
        pdf.font_size(11) do
          seller_details(pdf)
          invoice_meta(pdf, order)
          buyer_details(pdf, order)
          pdf.move_down 15
          items_table(pdf, order, show_hsn: true)
          totals_table(pdf, order)
          payment_terms(pdf)
          signatory(pdf)
        end
        document_footer(pdf, "invoice")
      end.render
    end

    private

    # Register the bundled DejaVu fonts (they cover the ₹ glyph) and select
    # the default family for the document.
    sig { params(pdf: Prawn::Document).void }
    def setup_fonts(pdf)
      fonts_dir = File.expand_path("../../web/fonts", __dir__)
      pdf.font_families.update(
        "DejaVu" => {
          normal: File.join(fonts_dir, "DejaVuSans.ttf"),
          bold: File.join(fonts_dir, "DejaVuSans-Bold.ttf")
        }
      )
      pdf.font "DejaVu"
    end

    sig { params(pdf: Prawn::Document).void }
    def receipt_heading(pdf)
      pdf.font_size(20) { pdf.text "RECEIPT", align: :center, style: :bold }
      pdf.move_down 10
    end

    sig { params(pdf: Prawn::Document).void }
    def invoice_heading(pdf)
      pdf.font_size(22) { pdf.text "TAX INVOICE", align: :center, style: :bold }
      pdf.move_down 5
      pdf.font_size(10) { pdf.text "Original for Recipient", align: :center, color: "666666" }
      pdf.move_down 15
    end

    sig { params(pdf: Prawn::Document, order: Order).void }
    def order_details(pdf, order)
      pdf.font_size(12) do
        pdf.text "Order ID: #{order.order_id}", style: :bold
        pdf.text "Date: #{order.date&.strftime("%d-%m-%Y")}"
        pdf.text "Client: #{order.client.name}"
        pdf.text "Client GSTIN: #{order.client.gstin}" if order.client.gst_registered?
        pdf.text "Client State: #{order.client.state}" if order.client.state
        pdf.text "Place of Supply: #{order.place_of_supply}" if order.place_of_supply
      end
      pdf.move_down 15
    end

    sig { params(pdf: Prawn::Document, order: Order, show_hsn: T::Boolean).void }
    def items_table(pdf, order, show_hsn: false)
      return if order.items.empty?

      pdf.font_size(12) { pdf.text "Items", style: :bold }
      pdf.move_down 5

      headers = ["#", "Description"]
      headers << "HSN/SAC" if show_hsn
      headers += %w[Qty Rate Taxable CGST SGST IGST Total]

      rows = order.items.each_with_index.map { |item, idx| item_row(item, idx, show_hsn) }
      pdf.table([headers] + rows, header: true, width: pdf.bounds.width) do |t|
        t.row(0).font_style = :bold
        t.row(0).background_color = "CCCCCC"
        t.column(1).align = :left
        t.columns(2..(headers.length - 1)).align = :right
        t.row_colors = %w[FFFFFF F0F0F0]
        t.cell_style = { size: show_hsn ? 8 : 9, padding: show_hsn ? 3 : 4 }
      end
      pdf.move_down 15
    end

    sig { params(item: OrderItem, idx: Integer, show_hsn: T::Boolean).returns(T::Array[String]) }
    def item_row(item, idx, show_hsn)
      row = [(idx + 1).to_s, item.item]
      row << (item.hsn_code || item.sac_code || "N/A") if show_hsn
      row + [
        item.quantity.to_s,
        format_money(item.rate),
        format_money_paise(item.taxable_value_paise),
        format_money_paise(item.cgst_paise),
        format_money_paise(item.sgst_paise),
        format_money_paise(item.igst_paise),
        format_money_paise(item.total_with_gst_paise)
      ]
    end

    sig { params(pdf: Prawn::Document, order: Order).void }
    def totals_table(pdf, order)
      pdf.font_size(10) do
        totals = [
          ["Taxable Value", format_money_paise(order.total_taxable_value_paise)],
          ["CGST", format_money_paise(order.total_cgst_paise)],
          ["SGST", format_money_paise(order.total_sgst_paise)],
          ["IGST", format_money_paise(order.total_igst_paise)],
          ["Total GST", format_money_paise(order.total_gst_paise)],
          ["Grand Total (with GST)", format_money_paise(order.total_with_gst_paise)]
        ]

        pdf.table(totals, column_widths: [300, 200]) do |t|
          t.column(1).align = :right
          t.row(-1).font_style = :bold
          t.cell_style = { size: 10, padding: 4 }
        end
      end
      pdf.move_down 20
    end

    sig { params(pdf: Prawn::Document, payments: T::Array[Income]).void }
    def payments_section(pdf, payments)
      return if payments.empty?

      pdf.font_size(12) { pdf.text "Payments Received", style: :bold }
      pdf.move_down 5

      rows = payments.map do |p|
        [p.date&.strftime("%d-%m-%Y") || "N/A", format_money(p.amount), p.mode, p.note.to_s]
      end
      pdf.table([%w[Date Amount Mode Note]] + rows, header: true, width: pdf.bounds.width) do |t|
        t.row(0).font_style = :bold
        t.row(0).background_color = "CCCCCC"
        t.column(1).align = :right
        t.cell_style = { size: 9, padding: 4 }
      end

      pdf.move_down 10
      total_received = Money.new(payments.sum { |p| p.amount.cents })
      pdf.font_size(11) { pdf.text "Total Received: #{format_money(total_received)}", align: :right, style: :bold }
    end

    sig { params(pdf: Prawn::Document, order: Order).void }
    def deliveries_section(pdf, order)
      delivery_rows = order.items.flat_map do |item|
        item.delivery_logs.map do |log|
          [item.item, log[:quantity].to_s, log[:date].to_s, log[:note].to_s]
        end
      end
      return if delivery_rows.empty?

      pdf.move_down 15
      pdf.font_size(12) { pdf.text "Deliveries", style: :bold }
      pdf.move_down 5

      pdf.table([%w[Item Qty Date Note]] + delivery_rows, header: true, width: pdf.bounds.width) do |t|
        t.row(0).font_style = :bold
        t.row(0).background_color = "CCCCCC"
        t.columns(1).align = :right
        t.cell_style = { size: 9, padding: 4 }
      end

      pdf.move_down 5
      total_qty = order.items.sum(&:quantity)
      pdf.font_size(10) { pdf.text "Total Delivered: #{order.total_delivered}/#{total_qty}", align: :right, style: :bold }
    end

    sig { params(pdf: Prawn::Document).void }
    def seller_details(pdf)
      pdf.bounding_box([0, pdf.cursor], width: 250) do
        pdf.font_size(10) { pdf.text "Smedge", style: :bold }
        pdf.font_size(8) do
          pdf.text "123 Business Street"
          pdf.text "City, State - 400001"
          pdf.text "GSTIN: 27AAAAA0000A1Z5"
          pdf.text "Email: billing@smedge.example"
        end
      end
    end

    sig { params(pdf: Prawn::Document, order: Order).void }
    def invoice_meta(pdf, order)
      pdf.bounding_box([300, pdf.cursor], width: 250) do
        pdf.font_size(10) { pdf.text "TAX INVOICE", style: :bold, align: :right }
        pdf.move_down 5
        pdf.font_size(9) do
          pdf.text "Invoice No: #{order.order_id}", align: :right
          pdf.text "Date: #{order.date&.strftime("%d-%m-%Y")}", align: :right
          pdf.text "Place of Supply: #{order.place_of_supply || "N/A"}", align: :right
        end
      end
    end

    sig { params(pdf: Prawn::Document, order: Order).void }
    def buyer_details(pdf, order)
      pdf.move_down 20
      client = order.client
      pdf.bounding_box([0, pdf.cursor], width: 250) do
        pdf.font_size(10) { pdf.text "Bill To:", style: :bold }
        pdf.font_size(9) do
          pdf.text client.name
          pdf.text client.address if client.address
          pdf.text "#{client.city} - #{client.pincode}" if client.city || client.pincode
          pdf.text "GSTIN: #{client.gstin}" if client.gst_registered?
          pdf.text "State: #{client.state}" if client.state
        end
      end
    end

    sig { params(pdf: Prawn::Document).void }
    def payment_terms(pdf)
      pdf.font_size(10) do
        pdf.text "Payment Terms: Net 30 days", style: :bold
        pdf.move_down 5
        pdf.text "Bank Details:", style: :bold
        pdf.text "Account: Smedge Technologies Pvt Ltd"
        pdf.text "Bank: HDFC Bank"
        pdf.text "A/C No: 1234567890"
        pdf.text "IFSC: HDFC0001234"
      end
    end

    sig { params(pdf: Prawn::Document).void }
    def signatory(pdf)
      pdf.move_down 40
      pdf.font_size(10) do
        pdf.text "For Smedge Technologies Pvt Ltd", align: :right
        pdf.move_down 30
        pdf.text "Authorized Signatory", align: :right
      end
    end

    sig { params(pdf: Prawn::Document, kind: String).void }
    def document_footer(pdf, kind)
      pdf.move_down 30
      pdf.font_size(8) do
        pdf.text "This is a computer-generated #{kind}. No signature required.", align: :center, color: "999999"
        pdf.text "Generated on #{Date.today.strftime("%d-%m-%Y")}", align: :center, color: "999999"
      end
      pdf.number_pages "Page <page> of <total>", at: [pdf.bounds.right - 50, 0], size: 8
    end

    # Format money object for display
    sig { params(amount: Money).returns(String) }
    def format_money(amount)
      Utils::CurrencyFormatter.format_money_in_indian_style(amount)
    end

    # Format paise integer for display
    sig { params(paise: Integer).returns(String) }
    def format_money_paise(paise)
      Utils::CurrencyFormatter.format_money_in_indian_style(paise)
    end
  end
end
