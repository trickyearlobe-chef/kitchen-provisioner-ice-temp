# frozen_string_literal: true

# Shim so that `name: chef-ice` (hyphenated) works in .kitchen.yml.
#
# Test Kitchen plugin loader (Kitchen::Plugin.load) resolves names via:
#
#   1. require "kitchen/provisioner/#{plugin}"    -- this file satisfies that
#   2. str_const = Kitchen::Util.camel_case(plugin)
#   3. klass = type.const_get(str_const)
#
# With "chef-ice", step 1 succeeds (loads this file, which loads chef_ice.rb).
# But step 2 produces "Chef-ice" (Thor::Util.camel_case only splits on
# underscores), and step 3 raises NameError because "Chef-ice" is not a
# valid Ruby constant name.
#
# We apply two patches:
#
# 1. Kitchen::Util.camel_case -- normalises "chef-ice" to "chef_ice" before
#    Thor converts it to "ChefIce".  This fixes the CURRENT Plugin.load
#    call because camel_case is invoked AFTER the require that loads this
#    file.
#
# 2. Kitchen::Provisioner.for_plugin -- rewrites "chef-ice" to "chef_ice"
#    before Plugin.load is called.  This catches any FUTURE calls (e.g.
#    Kitchen re-resolving the provisioner) and mirrors the pattern Kitchen
#    already uses for "chef_zero" to "chef_infra".

require_relative "chef_ice"

# -- Patch 1: fix camel_case for the in-flight Plugin.load call ----------
module Kitchen
  module Util
    class << self
      unless method_defined?(:_camel_case_before_chef_ice)
        alias_method :_camel_case_before_chef_ice, :camel_case

        def camel_case(str)
          str = "chef_ice" if str == "chef-ice"
          _camel_case_before_chef_ice(str)
        end
      end
    end
  end
end

# -- Patch 2: fix for_plugin for any subsequent resolution calls ----------
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
