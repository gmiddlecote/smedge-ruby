# frozen_string_literal: true

# load_data.rb

require "yaml"

module Smedge
  # module Utils
  module Utils
    # module LoadData
    module LoadData
      # module LoadData
      def self.load_clients(yaml_file_path)
        data = YAML.load_file(yaml_file_path)
        return {} unless data["clients"]

        clients = {}
        data["clients"].each do |client_hash|
          client = Smedge::Client.new(client_hash["name"])
          clients[client.name] = client
        end

        clients
      end

      def self.load_transactions(yaml_file_path, clients)
        data = YAML.load_file(yaml_file_path)
        return unless data["transactions"]

        data["transactions"].each do |txn|
          client = clients[txn["client"]]
          next unless client

          if txn["type"] == "income"
            income = Income.new(
              date: txn["date"],
              amount: txn["amount"],
              mode: txn["mode"],
              note: txn["note"],
              client: client,
              order_id: nil
            )
            client.add_credit(income)

          elsif txn["type"] == "expense"
            expense = Smedge::Expense.new(
              date: txn["date"],
              amount: txn["amount"],
              mode: txn["mode"],
              note: txn["note"],
              client: client
            )
            client.add_debit(expense)

          end
        end
      end
    end
  end
end
