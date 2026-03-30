# Test Kitchen provisioner for Chef ICE (Chef Infra Client 19+).
#
# Thin layer on top of the existing ChefInfra provisioner from
# kitchen-omnibus-chef. Only overrides the install path to use the
# Chef commercial downloads API or a direct download URL.
# Everything else (sandbox, config, run_command) is inherited.

require "kitchen/provisioner/chef_infra"
require_relative "chef_ice/version"

module Kitchen
  module Provisioner
    class ChefIce < ChefInfra
      kitchen_provisioner_api_version 2

      plugin_version Kitchen::Provisioner::CHEF_ICE_VERSION

      # Do NOT set product_name — it triggers mixlib-install validation
      # in the parent which doesn't know about chef-ice.
      # Instead we set require_chef_omnibus to false and handle install ourselves.
      default_config :require_chef_omnibus, false

      # Commercial downloads API base URL
      default_config :downloads_api_url, "https://chefdownload-commercial.chef.io"

      # Licence key for the commercial downloads API
      default_config :chef_license_key do |_p|
        ENV["CHEF_LICENSE_KEY"]
      end

      default_config :product_version, "latest"
      default_config :channel, "stable"
      default_config :install_strategy, "once"   # once, always, skip
      default_config :download_url, nil
      default_config :checksum, nil

      # Skip the enterprise gem delegation dance from ChefInfra —
      # we ARE the replacement provisioner.
      def self.new(config = {})
        allocate.tap { |i| i.send(:initialize, config) }
      end

      # Completely override install_command — never call super.
      # The parent's install path goes through mixlib-install which
      # doesn't know about the chef-ice product.
      def install_command
        return if config[:install_strategy] == "skip"

        if config[:download_url]
          prefix_command(wrap_shell_code(install_from_download_url))
        elsif config[:chef_license_key]
          prefix_command(wrap_shell_code(install_from_commercial_api))
        else
          raise UserError,
            "chef_license_key is required to download chef-ice from the " \
            "commercial downloads API. Set it in kitchen.yml or via the " \
            "CHEF_LICENSE_KEY env var. Alternatively, set download_url to " \
            "point at a local package."
        end
      end

      # Skip the parent's license check which goes through license-acceptance
      # gem with product names it may not recognise.
      def check_license
        # chef-ice license is handled by the install.sh script or the
        # chef_license / chef_license_key config passed to chef-client.
      end

      private

      # Install from a user-supplied direct URL (local mirror, S3, etc.)
      def install_from_download_url
        url      = config[:download_url]
        checksum = config[:checksum]
        strategy = config[:install_strategy]

        script = []
        script << install_guard if strategy == "once"

        script << <<~SH
          echo "-----> Installing Chef ICE from #{url}"
          tmpdir="$(mktemp -d)"
          filename="$(basename "#{url}" | sed 's/?.*//')"
          pkg="$tmpdir/$filename"

          if command -v curl >/dev/null 2>&1; then
            curl -sL -o "$pkg" "#{url}"
          elif command -v wget >/dev/null 2>&1; then
            wget -nv -O "$pkg" "#{url}"
          else
            echo "ERROR: neither curl nor wget found" >&2
            exit 1
          fi
        SH

        if checksum
          script << <<~SH
            echo "#{checksum}  $pkg" | sha256sum -c - || {
              echo "ERROR: checksum mismatch" >&2; exit 1
            }
          SH
        end

        script << <<~SH
          case "$pkg" in
            *.deb)  #{sudo("dpkg")} -i "$pkg" || #{sudo("apt-get")} install -fy ;;
            *.rpm)
              if command -v dnf >/dev/null 2>&1; then #{sudo("dnf")} install -y "$pkg"
              elif command -v yum >/dev/null 2>&1; then #{sudo("yum")} install -y "$pkg"
              else #{sudo("rpm")} -Uvh "$pkg"
              fi ;;
            *)      echo "ERROR: unknown package format" >&2; exit 1 ;;
          esac
          rm -rf "$tmpdir"
        SH

        script.join("\n")
      end

      # Install via the Chef commercial downloads API install.sh
      def install_from_commercial_api
        api_url     = config[:downloads_api_url]
        license_key = config[:chef_license_key]
        version     = config[:product_version]
        channel     = config[:channel]
        strategy    = config[:install_strategy]

        script = []
        script << install_guard if strategy == "once"

        script << <<~SH
          echo "-----> Installing Chef ICE #{version} (#{channel}) via commercial downloads API"
          if command -v curl >/dev/null 2>&1; then
            dl_cmd="curl -sL"
          elif command -v wget >/dev/null 2>&1; then
            dl_cmd="wget -qO-"
          else
            echo "ERROR: neither curl nor wget found" >&2
            exit 1
          fi
          $dl_cmd "#{api_url}/install.sh?license_id=#{license_key}" | #{sudo("bash")} -s -- \\
            -P chef-ice \\
            -c #{channel} \\
            -v #{version}
        SH

        script.join("\n")
      end

      # Guard clause: skip install if chef-client already present
      def install_guard
        <<~SH
          if [ -x "#{config[:chef_client_path]}" ]; then
            echo "-----> Chef ICE already installed, skipping"
            exit 0
          fi
        SH
      end
    end
  end
end
