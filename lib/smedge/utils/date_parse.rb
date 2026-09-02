# frozen_string_literal: true

# typed: true

# date_parse

module Smedge
  # module Utils
  module Utils
    # Turns "dd-mm-yyyy" strings into Date objects. Returns nil (with a warning)
    # for anything else instead of raising, so callers can validate dates.
    module DateParser
      extend T::Sig

      DEFAULT_FORMAT = "%d-%m-%Y"

      # Parse a "dd-mm-yyyy" string; nil-tolerant and never raises.
      sig { params(date_str: T.nilable(String)).returns(T.nilable(Date)) }
      def self.parse(date_str)
        return nil if date_str.nil? || date_str.strip.empty?

        Date.strptime(date_str, DEFAULT_FORMAT)
      rescue ArgumentError
        warn "[DateParser] Invalid date Format: '#{date_str}'"
        nil
      end
    end
  end
end
