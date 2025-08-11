# frozen_string_literal: true
# typed: strict

# load_data.rb

require "yaml"
require "sorbet-runtime"

module Smedge
  # module Utils
  module Utils
    # module LoadData
    module LoadData
      extend T::Sig

      # module LoadData
      sig { params(yaml_file_path: String).returns(T::Hash[String, Smedge::Client]) }
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

      sig do
        params(
          yaml_file_path: String,
          clients: T::Hash[String, Smedge::Client]
        ).returns(T::Hash[String, Smedge::Transaction])
      end
      def self.load_transactions(yaml_file_path, clients)
        data = T.let(
          YAML.safe_load_file(yaml_file_path, aliases: true) || {},
          T::Hash[T.untyped, T.untyped]
        )

        transactions = T.let({}, T::Hash[String, Smedge::Transaction])
        return transactions unless data["transactions"].is_a?(Array)

        data["transactions"].each_with_index do |txn, idx|
          next unless txn.is_a?(Hash)
          client = clients[txn["client"]]
          next unless client

          case txn["type"]
          when "income"
            income = Smedge::Income.new(
              date: txn["date"],
              amount: txn["amount"],
              mode: txn["mode"],
              note: txn["note"],
              client: client,
              order_id: nil
            )
            client.add_credit(income)
            transactions["income_#{idx}"] = income

          when "expense"
            expense = Smedge::Expense.new(
              date: txn["date"],
              amount: txn["amount"],
              mode: txn["mode"],
              note: txn["note"],
              client: client
            )
            client.add_debit(expense)
            transactions["expense_#{idx}"] = expense
          end
        end

        transactions
      end

    end
  end
end
