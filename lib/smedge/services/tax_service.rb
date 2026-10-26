# frozen_string_literal: true

module Smedge
  module TaxService
    # For registered clients with GSTIN: split intra-state (CGST+SGST) vs inter-state (IGST)
    # Based on a business/state setting; assumes business state is passed or compared.
    # Rate is stored as a percentage (e.g., 18 for 18%).
    extend T::Sig

    # Returns [cgst, sgst, igst] as fractions of total rate (e.g., 9/9/18)
    sig { params(client_state: T.nilable(String), business_state: T.nilable(String), rate_percent: Numeric).returns([Float, Float, Float]) }
    def self.calculate_split(client_state:, business_state:, rate_percent:)
      # If either party is unregistered (no gstin) or rate is 0, no tax split
      return [0.0, 0.0, 0.0] if rate_percent.to_f <= 0 || client_state.nil? || business_state.nil?

      rate_f = rate_percent.to_f
      if client_state.to_s.strip.upcase == business_state.to_s.strip.upcase
        [rate_f / 2.0, rate_f / 2.0, 0.0]
      else
        [0.0, 0.0, rate_f]
      end
    end

    sig { params(amount_paise: Integer, rate_percent: Numeric, split: [Float, Float, Float]).returns([Integer, Integer, Integer]) }
    def self.tax_amounts(amount_paise:, rate_percent:, split:)
      rate_f = rate_percent.to_f
      total_tax = (amount_paise.to_f * rate_f / 100.0).round
      cgst_rate, sgst_rate, igst_rate = split
      cgst = ((amount_paise.to_f * cgst_rate / 100.0) / rate_f * total_tax).round if rate_f > 0
      sgst = ((amount_paise.to_f * sgst_rate / 100.0) / rate_f * total_tax).round if rate_f > 0
      igst = ((amount_paise.to_f * igst_rate / 100.0) / rate_f * total_tax).round if rate_f > 0
      [cgst || 0, sgst || 0, igst || 0]
    end
  end
end
