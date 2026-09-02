# frozen_string_literal: true

# Rake tasks: `rake` (default) runs specs + rubocop; `rake db:seed` and
# `rake db:reset` manage the SQLite database.
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :db do
  desc "Create tables and seed the database from orders.yaml"
  task :seed do
    require_relative "lib/smedge"
    Smedge::Db.init_db
    Smedge::Db.seed_from_yaml(File.join(__dir__, "orders.yaml"))
    puts "Seeded #{Smedge::Db.db[:clients].count} clients, " \
         "#{Smedge::Db.db[:transactions].count} transactions, " \
         "#{Smedge::Db.db[:orders].count} orders, " \
         "#{Smedge::Db.db[:order_items].count} order items."
  end

  desc "Drop and recreate the database tables"
  task :reset do
    require_relative "lib/smedge"
    Smedge::Db.reset_schema
    puts "Database reset."
  end
end

task default: %i[spec rubocop]
