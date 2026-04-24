# frozen_string_literal: true

# Shim so that `name: chef-ice` (hyphenated) works in .kitchen.yml.
#
# Test Kitchen's plugin loader resolves names via:
#   require "kitchen/provisioner/#{plugin}"   -- this file satisfies that
#   const_get(camel_case(plugin))             -- camel_case("chef-ice") => "Chef-ice"
#
# "Chef-ice" is not a valid Ruby constant name, so const_get raises
# NameError and the plugin fails to load.  We cannot use const_set
# either — Ruby rejects hyphens in constant names entirely.
#
# Instead we patch Kitchen::Provisioner.for_plugin to normalise the
# hyphenated name to its underscored equivalent before the loader
# runs.  This follows the same pattern Kitchen already uses to remap
# "chef_zero" → "chef_infra" in the stock provisioner module.

require_relative "chef_ice"

module Kitchen
  module Provisioner
    class << self
      unless method_defined?(:_original_for_plugin_before_chef_ice)
        alias_method :_original_for_plugin_before_chef_ice, :for_plugin

        def for_plugin(plugin, config)
          if plugin == "chef-ice"
            plugin = "chef_ice"
            config[:name] = "chef_ice"
          end
          _original_for_plugin_before_chef_ice(plugin, config)
        end
      end
    end
  end
end
