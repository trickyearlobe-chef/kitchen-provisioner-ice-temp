# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "kitchen/provisioner/chef_ice/version"

Gem::Specification.new do |spec|
  spec.name          = "kitchen-provisioner-chef-ice"
  spec.version       = Kitchen::Provisioner::CHEF_ICE_VERSION
  spec.authors       = ["Richard Nixon"]
  spec.email         = ["richard.nixon@btinternet.com"]
  spec.summary       = "Test Kitchen provisioner for Chef ICE (Chef Infra Client 19+)"
  spec.description   = "A thin Test Kitchen provisioner that inherits from the " \
                        "existing ChefInfra provisioner and overrides installation " \
                        "to use the Chef commercial downloads API or a direct URL " \
                        "for chef-ice (chef-client 19+) packages."
  spec.homepage      = "https://github.com/trickyearlobe-chef/kitchen-provisioner-chef-ice"
  spec.license       = "Apache-2.0"

  spec.files         = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.1"

  # This gem requires test-kitchen and kitchen-omnibus-chef at runtime, but we
  # intentionally declare NO gem dependencies here. Chef Workstation already
  # provides these and a curated set of gems. Declaring dependencies causes
  # bundler/gem to resolve and install versions that conflict with Chef
  # Workstation's signed Ruby and native extensions.
  # Install with: chef exec gem install kitchen-provisioner-chef-ice
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"]       = spec.homepage
  spec.metadata["bug_tracker_uri"]       = "#{spec.homepage}/issues"
end
