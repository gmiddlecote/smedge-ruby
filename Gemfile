# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in smedge.gemspec
gemspec

group :development do
  # NOTE: The `sorbet` gem (static type checker) is NOT installable on
  # Windows/no-WSL because sorbet-static ships no Windows binary. Keep only
  # sorbet-runtime (which enforces sigs at runtime) and run `srb tc` on
  # macOS/Linux or in CI instead.
  gem "sorbet-runtime"
  gem "yaml"
end

group :web do
  gem "puma", ">= 6.4"
  gem "rackup", "~> 2.2"
  gem "sinatra", "~> 4.0"
end

group :test do
  gem "rack-test", "~> 2.0"
end
