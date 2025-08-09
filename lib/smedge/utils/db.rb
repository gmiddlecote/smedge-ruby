# frozen_string_literal: true
# typed: strict

require "sequel"
require "sorbet-runtime"

module Smedge
  # Database functions
  module Db
    extend T::Sig  # This must come before extend self
    extend self    # makes methods available as module functions

    @db = T.let(Sequel.sqlite, Sequel::Database) # in-memory database

    sig { returns(Sequel::Database) }
    def db
      @db
    end

    sig { void }
    def init_db
      db.create_table? :clients do
        primary_key :id
        String :name, null: false
        String :email
      end

      db.create_table? :transactions do
        primary_key :id
        foreign_key :client_id, :clients
        Integer :amount_cents, null: false
        String :currency, default: "INR"
        String :type, null: false # 'income' or 'expense'
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end
    end
  end
end
