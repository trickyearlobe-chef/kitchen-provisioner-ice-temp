# Test Kitchen provisioner for ICE Temp (Chef Infra Client 19+).
#
# Thin layer on top of the existing ChefInfra provisioner from
# kitchen-omnibus-chef. Only overrides the install path to use the
# Chef commercial downloads API or a direct download URL.
# Everything else (sandbox, config files, run_command, policyfile/berkshelf)
# is inherited from ChefInfra.
#
# Architecture
# ------------
# The package is downloaded in Ruby on the workstation during
# create_sandbox, placed in the sandbox directory, and uploaded to
# the node with the rest of the sandbox files (cookbooks, config, etc.).
#
# prepare_command (which runs AFTER the sandbox upload but BEFORE
# run_command) installs the local package file using the native
# package manager. No curl/wget is needed on the node, no URLs
# appear in the shell script, and the license key never leaves
# the workstation.

require "kitchen/provisioner/chef_infra"
require_relative "ice_temp/version"
require "json"
require "net/http"
require "uri"
require "fileutils"
require "digest"



module Kitchen
  module Provisioner
    class IceTemp < ChefInfra
      kitchen_provisioner_api_version 2

      plugin_version Kitchen::Provisioner::ICE_TEMP_VERSION

      # Do NOT set product_name — it triggers mixlib-install validation
      # in the parent which doesn't know about ice-temp.
      # Instead we set require_chef_omnibus to false and handle install ourselves.
      default_config :require_chef_omnibus, false

      # Commercial downloads API base URL
      default_config :downloads_api_url, "https://commercial-acceptance.downloads.chef.co"

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

      # --- sandbox --------------------------------------------------

      # Download the ice-temp package into the sandbox so it gets
      # uploaded alongside cookbooks, data bags, etc.
      def create_sandbox
        super
        return if config[:install_strategy] == "skip"

        prepare_package
      end

      # --- commands sent to the node --------------------------------

      # install_command runs BEFORE the sandbox upload.
      # We only use it for the guard check — actual install happens
      # in prepare_command after the package file has been uploaded.
      def install_command
        return if config[:install_strategy] == "skip"

        prefix_command(wrap_shell_code(install_guard))
      end

      # prepare_command runs AFTER sandbox upload and BEFORE run_command.
      # The package file(s) are now on the node under root_path.
      def prepare_command
        return if config[:install_strategy] == "skip"
        return unless @package_files && !@package_files.empty?

        prefix_command(wrap_shell_code(install_package_script))
      end

      # Skip the parent's license check which goes through
      # license-acceptance gem with product names it may not recognise.
      def check_license
        # ice-temp license is handled by chef_license / chef_license_key
        # config passed to chef-client at run time.
      end

      private

      # ---------------------------------------------------------------
      # Package download (runs on workstation during create_sandbox)
      # ---------------------------------------------------------------

      # Decide which path to take and download the package into the
      # sandbox directory.
      def prepare_package
        if config[:download_url]
          download_from_url
        elsif config[:chef_license_key]
          download_from_api
        else
          raise UserError,
            "chef_license_key is required to download ice-temp from the " \
            "commercial downloads API. Set it in kitchen.yml or via the " \
            "CHEF_LICENSE_KEY env var. Alternatively, set download_url to " \
            "point at a local package."
        end
      end

      # Download from a user-supplied direct URL.
      def download_from_url
        url  = config[:download_url]
        name = File.basename(URI.parse(url).path)
        dest = File.join(sandbox_path, name)

        info("Downloading ice-temp from #{url}")
        http_download(URI.parse(url), dest)
        verify_sha256(dest, config[:checksum]) if config[:checksum]

        @package_files = [{ filename: name }]
      end

      # Walk the commercial downloads API and download the correct
      # package(s) for the target platform into the sandbox.
      def download_from_api
        version  = resolve_version
        packages = fetch_packages(version)

        info("ICE Temp #{version} (license: ****)")

        # Only download formats the target platform can use.
        formats = windows_os? ? %w[msi] : %w[rpm deb]
        platform = windows_os? ? "windows" : "linux"

        @package_files = []

        packages.each do |arch, pm_map|
          formats.each do |pm|
            detail = pm_map[pm]
            next unless detail

            url    = detail["url"]
            sha256 = detail["sha256"]

            # Check the shared Chef Workstation cache first.
            # Layout: ~/.chef/cached-packages/{platform}/{arch}/{pm}/ice-temp/{version}/
            cache_subdir = File.join(platform, arch, pm, "ice-temp", version)
            cached = find_in_cache(cache_subdir, sha256)

            if cached
              filename = File.basename(cached)
              dest = File.join(sandbox_path, filename)
              info("  Using cached #{filename}")
              FileUtils.cp(cached, dest)
            else
              # Download to a temp location, resolve real filename from
              # Content-Disposition header, then move into cache.
              info("  Downloading ice-temp #{version} #{pm} (#{arch})")
              tmpfile = File.join(sandbox_path, "ice-temp-download.tmp")
              real_name = http_download(URI.parse(url), tmpfile)

              # Use Content-Disposition filename if we got one,
              # otherwise fall back to a constructed name.
              filename = real_name || "ice-temp-#{version}-#{arch}.#{pm}"
              dest = File.join(sandbox_path, filename)
              FileUtils.mv(tmpfile, dest) if File.exist?(tmpfile)

              verify_sha256(dest, sha256) if sha256 && !sha256.empty?
              store_in_cache(dest, cache_subdir, sha256)
            end

            @package_files << { arch: arch, pm: pm, filename: filename }
          end
        end

        if @package_files.empty?
          raise UserError, "No downloadable packages found for ice-temp #{version}"
        end
      end

      # ---------------------------------------------------------------
      # API helpers (run on workstation — key never sent to the node)
      # ---------------------------------------------------------------

      # GET a JSON endpoint from the commercial downloads API.
      def api_get(path, params = {})
        params["license_id"] = config[:chef_license_key]
        uri = URI.parse("#{config[:downloads_api_url]}#{path}")
        uri.query = URI.encode_www_form(params)

        response = http_get_follow(uri, 5)

        unless response.is_a?(Net::HTTPSuccess)
          safe_uri = uri.to_s.gsub(config[:chef_license_key].to_s, "****")
          raise UserError,
            "Chef downloads API returned #{response.code}: " \
            "#{response.body.strip} (#{safe_uri})"
        end

        JSON.parse(response.body)
      end

      # Resolve "latest" to a concrete version string.
      def resolve_version
        version = config[:product_version]
        return version unless version.nil? || version == "latest"

        channel  = config[:channel]
        versions = api_get("/#{channel}/ice-temp/versions/all")

        raise UserError, "No versions found for ice-temp on #{channel} channel" if versions.empty?

        versions.sort_by { |v| Gem::Version.new(v) }.last
      end

      # Fetch the packages map and merge all platform keys.
      # Returns: { "x86_64" => { "rpm" => { ... }, "deb" => { ... } }, ... }
      def fetch_packages(version)
        channel  = config[:channel]
        response = api_get("/#{channel}/ice-temp/packages", "v" => version)

        merged = {}
        response.each_value do |arch_map|
          next unless arch_map.is_a?(Hash)

          arch_map.each do |arch, pm_map|
            merged[arch] ||= {}
            merged[arch].merge!(pm_map) if pm_map.is_a?(Hash)
          end
        end

        raise UserError, "No packages found for ice-temp #{version}" if merged.empty?

        merged
      end



      # ---------------------------------------------------------------
      # HTTP helpers
      # ---------------------------------------------------------------

      # GET with redirect following — returns the response object.
      def http_get_follow(uri, limit)
        raise UserError, "Too many HTTP redirects" if limit <= 0

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 10
        http.read_timeout = 30

        response = http.request(Net::HTTP::Get.new(uri))

        case response
        when Net::HTTPRedirection
          http_get_follow(URI.parse(response["location"]), limit - 1)
        else
          response
        end
      end

      # Stream a URI to a local file, following redirects.
      # Returns the filename from Content-Disposition header if present, else nil.
      def http_download(uri, dest, limit = 5)
        raise UserError, "Too many HTTP redirects downloading #{File.basename(dest)}" if limit <= 0

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          request = Net::HTTP::Get.new(uri)
          http.request(request) do |response|
            case response
            when Net::HTTPRedirection
              return http_download(URI.parse(response["location"]), dest, limit - 1)
            when Net::HTTPSuccess
              File.open(dest, "wb") do |f|
                response.read_body { |chunk| f.write(chunk) }
              end
              # Extract filename from Content-Disposition if present
              cd = response["content-disposition"]
              if cd && cd =~ /filename=["']?([^"';\s]+)/
                return $1
              end
              return nil
            else
              raise UserError,
                "Failed to download #{File.basename(dest)}: HTTP #{response.code}"
            end
          end
        end
      end

      # Verify a file matches an expected SHA-256 hex digest.
      def verify_sha256(path, expected)
        actual = Digest::SHA256.file(path).hexdigest
        return if actual == expected

        raise UserError,
          "Checksum mismatch for #{File.basename(path)}: " \
          "expected #{expected}, got #{actual}"
      end

      # ---------------------------------------------------------------
      # Package cache — shared with chef-pkg at ~/.chef/cached-packages/
      #
      # Layout:
      #   ~/.chef/cached-packages/{platform}/{arch}/{pm}/ice-temp/{version}/
      #     ice-temp-19.2.12-1.amzn2.x86_64.rpm
      #     ice-temp-19.2.12-1.amzn2.x86_64.rpm.sha256
      # ---------------------------------------------------------------

      CACHE_ROOT = File.join(Dir.home, ".chef", "cached-packages")

      # Find a cached package file by scanning the cache subdirectory
      # for a file whose .sha256 sidecar matches the expected digest.
      # Returns the full path to the cached file, or nil.
      def find_in_cache(subdir, expected_sha256)
        dir = File.join(CACHE_ROOT, subdir)
        return nil unless File.directory?(dir)
        return nil if expected_sha256.nil? || expected_sha256.empty?

        Dir.glob(File.join(dir, "*")).each do |path|
          next if path.end_with?(".sha256")

          sidecar = "#{path}.sha256"
          next unless File.exist?(sidecar)
          next unless File.read(sidecar).strip == expected_sha256

          return path
        end

        nil
      end

      # Store a downloaded file in the cache with a .sha256 sidecar.
      def store_in_cache(source, subdir, sha256)
        return if sha256.nil? || sha256.empty?

        dir = File.join(CACHE_ROOT, subdir)
        FileUtils.mkdir_p(dir)
        dest = File.join(dir, File.basename(source))
        FileUtils.cp(source, dest)
        File.write("#{dest}.sha256", sha256)
      end

      # ---------------------------------------------------------------
      # Shell script generators (run on the node)
      # ---------------------------------------------------------------

      # Guard clause: skip install if chef-client already present.
      def install_guard
        <<~SH
          if [ -x "#{config[:chef_client_path]}" ]; then
            echo "-----> ICE Temp already installed, skipping"
            exit 0
          fi
        SH
      end

      # Generate a shell script that installs the package file(s)
      # already uploaded to root_path on the node.
      def install_package_script
        if @package_files.length == 1 && !@package_files[0][:arch]
          # Single file from download_url — install directly
          remote = remote_path_join(config[:root_path], @package_files[0][:filename])
          return install_single_package(remote)
        end

        # Multiple arch/pm files from the API — pick the right one at runtime
        install_multi_package
      end

      # Install a single known package file.
      def install_single_package(remote_pkg)
        <<~SH
          echo "-----> Installing ICE Temp from uploaded package"
          case "#{remote_pkg}" in
            *.deb) #{sudo("dpkg")} -i "#{remote_pkg}" || #{sudo("apt-get")} install -fy ;;
            *.rpm)
              if command -v dnf >/dev/null 2>&1; then #{sudo("dnf")} install -y "#{remote_pkg}"
              elif command -v yum >/dev/null 2>&1; then #{sudo("yum")} install -y "#{remote_pkg}"
              else #{sudo("rpm")} -Uvh "#{remote_pkg}"
              fi ;;
            *.msi) msiexec /qn /i "#{remote_pkg}" ;;
            *) echo "ERROR: unknown package format" >&2; exit 1 ;;
          esac
        SH
      end

      # Build a shell script with arch detection and pm detection that
      # picks the correct package file from the set uploaded to root_path.
      def install_multi_package
        root = config[:root_path]

        arch_branches = {}
        @package_files.each do |pf|
          arch_branches[pf[:arch]] ||= []
          arch_branches[pf[:arch]] << pf
        end

        script = []
        script << <<~SH
          echo "-----> Installing ICE Temp from uploaded package"
          machine="$(uname -m)"
          case "$machine" in
            x86_64|amd64)  arch="x86_64" ;;
            aarch64|arm64) arch="aarch64" ;;
            *)             echo "ERROR: unsupported architecture $machine" >&2; exit 1 ;;
          esac
        SH

        case_lines = []
        arch_branches.each do |arch, files|
          pm_lines = []
          files.each do |pf|
            remote = remote_path_join(root, pf[:filename])
            keyword = pm_lines.empty? ? "if" : "elif"
            case pf[:pm]
            when "rpm"
              pm_lines << "    #{keyword} command -v rpm >/dev/null 2>&1; then"
              pm_lines << "      if command -v dnf >/dev/null 2>&1; then #{sudo("dnf")} install -y \"#{remote}\""
              pm_lines << "      elif command -v yum >/dev/null 2>&1; then #{sudo("yum")} install -y \"#{remote}\""
              pm_lines << "      else #{sudo("rpm")} -Uvh \"#{remote}\""
              pm_lines << "      fi"
            when "deb"
              pm_lines << "    #{keyword} command -v dpkg >/dev/null 2>&1; then"
              pm_lines << "      #{sudo("dpkg")} -i \"#{remote}\" || #{sudo("apt-get")} install -fy"
            when "msi"
              pm_lines << "    #{keyword} command -v msiexec >/dev/null 2>&1; then"
              pm_lines << "      msiexec /qn /i \"#{remote}\""
            end
          end
          unless pm_lines.empty?
            pm_lines << "    else"
            pm_lines << "      echo \"ERROR: no supported package manager found\" >&2"
            pm_lines << "      exit 1"
            pm_lines << "    fi"
          end
          case_lines << "  #{arch})\n#{pm_lines.join("\n")}\n    ;;"
        end

        script << <<~SH
          case "$arch" in
          #{case_lines.join("\n")}
            *)
              echo "ERROR: no ice-temp package for architecture $arch" >&2
              exit 1
              ;;
          esac
        SH

        script.join("\n")
      end
    end
  end
end
