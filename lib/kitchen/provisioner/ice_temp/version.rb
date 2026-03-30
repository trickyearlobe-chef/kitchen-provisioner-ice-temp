# frozen_string_literal: true

module Kitchen
  module Provisioner
    ICE_TEMP_VERSION = begin
      dir = File.expand_path("../../..", __dir__)
      if File.directory?(File.join(dir, ".git"))
        tag = `git -C #{dir} describe --tags --match 'v*' 2>/dev/null`.strip
        tag.empty? ? "0.0.0" : tag.sub(/^v/, "").sub(/-(\d+)-g/, '.\1.dev.')
      else
        Gem.loaded_specs["kitchen-provisioner-ice-temp"]&.version&.to_s || "0.0.0"
      end
    end
  end
end
