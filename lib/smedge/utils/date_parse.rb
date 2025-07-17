# frozen_string_literal: true

# date_parse

module Smedge
  # module Utils
  module Utils
    # module DateParser
    module DateParser
      DEFAULT_FORMAT = "%d-%m-%Y"

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
