# frozen_string_literal: true

# typed: strict

require "digest"
require "securerandom"

module Smedge
  module Utils
    # Salted SHA-256 hashing for customer PINs. Stored form is
    # "sha256$<salt>$<digest>"; the digest is compared against a supplied PIN
    # so plain-text PINs never touch the database or the wires beyond the
    # login request itself.
    module Pin
      extend T::Sig

      # Salted SHA-256 hash of a PIN: "sha256$<salt>$<digest>".
      sig { params(pin: String).returns(String) }
      def self.hash_pin(pin)
        salt = SecureRandom.hex(8)
        "sha256$#{salt}$#{Digest::SHA256.hexdigest("#{salt}#{pin}")}"
      end

      # Compare a stored hash against a plain PIN.
      sig { params(stored: T.nilable(String), given: String).returns(T::Boolean) }
      def self.matches?(stored, given)
        return false unless stored&.start_with?("sha256$")

        salt, digest = stored.delete_prefix("sha256$").split("$", 2)
        return false unless salt && digest

        Digest::SHA256.hexdigest("#{salt}#{given}") == digest
      end
    end
  end
end
