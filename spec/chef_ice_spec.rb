require "kitchen"
require "kitchen/provisioner/chef_ice"

RSpec.describe Kitchen::Provisioner::ChefIce do
  let(:logged_output) { StringIO.new }
  let(:logger)        { Logger.new(logged_output) }

  let(:platform) do
    instance_double("Kitchen::Platform", os_type: nil, shell_type: nil, name: "ubuntu-22.04")
  end

  let(:suite) do
    instance_double("Kitchen::Suite", name: "default")
  end

  let(:transport) do
    instance_double("Kitchen::Transport::Base")
  end

  let(:driver) do
    instance_double("Kitchen::Driver::Base", cache_directory: nil)
  end

  let(:instance) do
    instance_double(
      "Kitchen::Instance",
      name:      "default-ubuntu-2204",
      logger:    logger,
      suite:     suite,
      platform:  platform,
      transport: transport,
      driver:    driver,
      to_str:    "default-ubuntu-2204",
    )
  end

  let(:config) do
    {
      kitchen_root: "/tmp/kitchen-root",
      test_base_path: "/tmp/kitchen-root/test/integration",
      instance: instance,
    }
  end

  subject { described_class.new(config) }

  before do
    allow(instance).to receive(:provisioner).and_return(subject)
    subject.finalize_config!(instance)
  end

  # ---------------------------------------------------------------
  # Fake API responses
  # ---------------------------------------------------------------

  let(:fake_packages_response) do
    {
      "linux" => {
        "x86_64" => {
          "rpm" => {
            "url"     => "https://example.com/download?pm=rpm",
            "sha256"  => "aabbccdd",
            "version" => "19.2.12",
          },
          "deb" => {
            "url"     => "https://example.com/download?pm=deb",
            "sha256"  => "eeff0011",
            "version" => "19.2.12",
          },
        },
        "aarch64" => {
          "rpm" => {
            "url"     => "https://example.com/download?pm=rpm&m=aarch64",
            "sha256"  => "11223344",
            "version" => "19.2.12",
          },
        },
      },
    }
  end

  let(:fake_versions_response) { ["19.1.164", "19.2.12"] }

  # ---------------------------------------------------------------
  # defaults
  # ---------------------------------------------------------------

  describe "defaults" do
    it "disables require_chef_omnibus" do
      expect(subject[:require_chef_omnibus]).to eq(false)
    end

    it "sets downloads_api_url" do
      expect(subject[:downloads_api_url]).to eq("https://commercial-acceptance.downloads.chef.co")
    end

    it "defaults product_version to latest" do
      expect(subject[:product_version]).to eq("latest")
    end

    it "defaults channel to stable" do
      expect(subject[:channel]).to eq("stable")
    end

    it "defaults install_strategy to once" do
      expect(subject[:install_strategy]).to eq("once")
    end

    it "defaults download_url to nil" do
      expect(subject[:download_url]).to be_nil
    end
  end

  # ---------------------------------------------------------------
  # install_command — only the guard check
  # ---------------------------------------------------------------

  describe "#install_command" do
    context "when install_strategy is skip" do
      let(:config) { super().merge(install_strategy: "skip") }

      it "returns nil" do
        expect(subject.install_command).to be_nil
      end
    end

    context "with default install_strategy (once)" do
      it "returns a guard that checks for chef-client" do
        cmd = subject.install_command
        expect(cmd).to include("already installed, skipping")
        expect(cmd).to include("chef-client")
      end

      it "does not contain any URLs" do
        cmd = subject.install_command
        expect(cmd).not_to include("http")
      end
    end
  end

  # ---------------------------------------------------------------
  # prepare_command — installs local package after sandbox upload
  # ---------------------------------------------------------------

  describe "#prepare_command" do
    context "when install_strategy is skip" do
      let(:config) { super().merge(install_strategy: "skip") }

      it "returns nil" do
        expect(subject.prepare_command).to be_nil
      end
    end

    context "when no packages have been downloaded" do
      it "returns nil" do
        expect(subject.prepare_command).to be_nil
      end
    end

    context "with a single download_url package" do
      let(:config) { super().merge(download_url: "https://mirror.example.com/chef-ice-19.deb") }

      before do
        # Simulate download_from_url having run
        subject.instance_variable_set(:@package_files, [{ filename: "chef-ice-19.deb" }])
      end

      it "generates a script that installs from a local file" do
        cmd = subject.prepare_command
        expect(cmd).to include("chef-ice-19.deb")
        expect(cmd).to include("dpkg")
      end

      it "does not contain any URLs or license keys" do
        cmd = subject.prepare_command
        expect(cmd).not_to include("http")
        expect(cmd).not_to include("license")
      end
    end

    context "with API-downloaded multi-arch packages" do
      let(:license_key) { "tmns-abcd1234-5678-9012-3456-xxxxxxxxxxxx-7890" }
      let(:config) { super().merge(chef_license_key: license_key) }

      before do
        subject.instance_variable_set(:@package_files, [
          { arch: "x86_64", pm: "rpm", filename: "chef-ice-19.2.12-x86_64.rpm" },
          { arch: "x86_64", pm: "deb", filename: "chef-ice-19.2.12-x86_64.deb" },
          { arch: "aarch64", pm: "rpm", filename: "chef-ice-19.2.12-aarch64.rpm" },
        ])
      end

      it "generates a script with architecture detection" do
        cmd = subject.prepare_command
        expect(cmd).to include("x86_64")
        expect(cmd).to include("aarch64")
        expect(cmd).to include("uname -m")
      end

      it "includes rpm install commands" do
        cmd = subject.prepare_command
        expect(cmd).to include("dnf")
        expect(cmd).to include("yum")
        expect(cmd).to include("rpm")
      end

      it "includes deb install commands" do
        cmd = subject.prepare_command
        expect(cmd).to include("dpkg")
      end

      it "references local package filenames" do
        cmd = subject.prepare_command
        expect(cmd).to include("chef-ice-19.2.12-x86_64.rpm")
        expect(cmd).to include("chef-ice-19.2.12-x86_64.deb")
        expect(cmd).to include("chef-ice-19.2.12-aarch64.rpm")
      end

      it "does not contain any URLs" do
        cmd = subject.prepare_command
        expect(cmd).not_to include("http")
      end

      it "does not contain the license key" do
        cmd = subject.prepare_command
        expect(cmd).not_to include(license_key)
      end

      it "does not reference install.sh" do
        cmd = subject.prepare_command
        expect(cmd).not_to include("install.sh")
      end
    end
  end

  # ---------------------------------------------------------------
  # create_sandbox — downloads packages into the sandbox
  # ---------------------------------------------------------------

  describe "#create_sandbox" do
    after { subject.cleanup_sandbox rescue nil }

    context "when install_strategy is skip" do
      let(:config) { super().merge(install_strategy: "skip") }

      it "does not attempt to download anything" do
        expect(subject).not_to receive(:prepare_package)
        subject.create_sandbox
      end
    end

    context "with download_url" do
      let(:config) do
        super().merge(download_url: "https://mirror.example.com/chef-ice-19.2.12.rpm")
      end

      it "downloads the file into the sandbox" do
        allow(subject).to receive(:http_download)
        allow(subject).to receive(:find_in_cache).and_return(nil)
        allow(subject).to receive(:store_in_cache)

        subject.create_sandbox

        expect(subject).to have_received(:http_download).with(
          an_instance_of(URI::HTTPS),
          a_string_ending_with("chef-ice-19.2.12.rpm")
        )
      end
    end

    context "with chef_license_key" do
      let(:license_key) { "tmns-abcd1234-5678-9012-3456-xxxxxxxxxxxx-7890" }
      let(:config) { super().merge(chef_license_key: license_key) }

      before do
        allow(subject).to receive(:api_get)
          .with("/stable/chef-ice/versions/all")
          .and_return(fake_versions_response)
        allow(subject).to receive(:api_get)
          .with("/stable/chef-ice/packages", "v" => "19.2.12")
          .and_return(fake_packages_response)
        allow(subject).to receive(:http_download)
        allow(subject).to receive(:verify_sha256)
        allow(subject).to receive(:find_in_cache).and_return(nil)
        allow(subject).to receive(:store_in_cache)
      end

      it "resolves the latest version" do
        subject.create_sandbox
        expect(subject).to have_received(:api_get)
          .with("/stable/chef-ice/versions/all")
      end

      it "fetches the packages metadata" do
        subject.create_sandbox
        expect(subject).to have_received(:api_get)
          .with("/stable/chef-ice/packages", "v" => "19.2.12")
      end

      it "downloads packages for all arch/pm combos" do
        subject.create_sandbox
        # x86_64 rpm, x86_64 deb, aarch64 rpm = 3 downloads
        expect(subject).to have_received(:http_download).exactly(3).times
      end

      it "verifies sha256 for each downloaded package" do
        subject.create_sandbox
        expect(subject).to have_received(:verify_sha256).exactly(3).times
      end

      it "populates @package_files with the correct entries" do
        subject.create_sandbox
        pf = subject.instance_variable_get(:@package_files)
        expect(pf.length).to eq(3)
        expect(pf.map { |p| p[:pm] }).to contain_exactly("rpm", "deb", "rpm")
        expect(pf.map { |p| p[:arch] }).to contain_exactly("x86_64", "x86_64", "aarch64")
      end

      context "with a specific version" do
        let(:config) { super().merge(product_version: "19.1.164") }

        before do
          allow(subject).to receive(:api_get)
            .with("/stable/chef-ice/packages", "v" => "19.1.164")
            .and_return(fake_packages_response)
        end

        it "does not call the versions endpoint" do
          subject.create_sandbox
          expect(subject).not_to have_received(:api_get)
            .with("/stable/chef-ice/versions/all")
        end
      end
    end

    context "without license key or download_url" do
      let(:config) { super().merge(chef_license_key: nil, download_url: nil) }

      before { ENV.delete("CHEF_LICENSE_KEY") }

      it "raises a UserError" do
        expect { subject.create_sandbox }.to raise_error(
          Kitchen::UserError, /chef_license_key/
        )
      end
    end
  end

  # ---------------------------------------------------------------
  # check_license — should be a no-op
  # ---------------------------------------------------------------

  describe "#check_license" do
    it "does not raise" do
      expect { subject.check_license }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------
  # run_command — inherited from ChefInfra
  # ---------------------------------------------------------------

  describe "#run_command" do
    it "runs chef-client in local mode" do
      cmd = subject.run_command
      expect(cmd).to include("chef-client")
      expect(cmd).to include("--local-mode")
    end
  end

  # ---------------------------------------------------------------
  # API error handling — key must be masked
  # ---------------------------------------------------------------

  describe "API error handling" do
    let(:license_key) { "tmns-secret-key-value-1234" }
    let(:config) { super().merge(chef_license_key: license_key, product_version: "latest") }

    it "masks the license key in error messages" do
      fake_response = instance_double("Net::HTTPForbidden",
        code: "403",
        body: '"License Id is not valid"')
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(fake_response).to receive(:is_a?).with(Net::HTTPRedirection).and_return(false)
      allow(subject).to receive(:http_get_follow).and_return(fake_response)

      expect { subject.send(:resolve_version) }.to raise_error(Kitchen::UserError) do |err|
        expect(err.message).to include("403")
        expect(err.message).to include("****")
        expect(err.message).not_to include(license_key)
      end
    end
  end

  # ---------------------------------------------------------------
  # version resolution
  # ---------------------------------------------------------------

  describe "resolve_version" do
    let(:config) { super().merge(chef_license_key: "test-key") }

    context "when product_version is a specific version" do
      let(:config) { super().merge(product_version: "19.1.164") }

      it "returns that version without calling the API" do
        expect(subject).not_to receive(:api_get)
        expect(subject.send(:resolve_version)).to eq("19.1.164")
      end
    end

    context "when product_version is latest" do
      before do
        allow(subject).to receive(:api_get).and_return(fake_versions_response)
      end

      it "returns the highest semver version" do
        expect(subject.send(:resolve_version)).to eq("19.2.12")
      end
    end
  end
end
