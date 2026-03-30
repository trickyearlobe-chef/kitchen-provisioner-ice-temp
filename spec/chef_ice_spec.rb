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

  describe "defaults" do
    it "sets product_name to chef-ice" do
      expect(subject[:product_name]).to eq("chef-ice")
    end

    it "sets downloads_api_url" do
      expect(subject[:downloads_api_url]).to eq("https://chefdownload-commercial.chef.io")
    end
  end

  describe "#install_command" do
    context "when install_strategy is skip" do
      let(:config) { super().merge(install_strategy: "skip") }

      it "returns nil" do
        expect(subject.install_command).to be_nil
      end
    end

    context "when download_url is set" do
      let(:config) do
        super().merge(download_url: "https://mirror.example.com/chef-ice-19.deb")
      end

      it "delegates to parent (mixlib-install)" do
        # Should not raise — parent handles download_url
        expect { subject.install_command }.not_to raise_error
      end
    end

    context "when using API without license key" do
      let(:config) { super().merge(chef_license_key: nil) }

      before { ENV.delete("CHEF_LICENSE_KEY") }

      it "raises an error" do
        expect { subject.install_command }.to raise_error(Kitchen::UserError, /chef_license_key/)
      end
    end

    context "when using API with license key" do
      let(:config) { super().merge(chef_license_key: "test-key-123") }

      it "generates a script using the commercial install.sh" do
        cmd = subject.install_command
        expect(cmd).to include("chefdownload-commercial.chef.io")
        expect(cmd).to include("test-key-123")
        expect(cmd).to include("-P chef-ice")
      end
    end
  end

  describe "#run_command" do
    it "runs chef-client in local mode (inherited)" do
      cmd = subject.run_command
      expect(cmd).to include("chef-client")
      expect(cmd).to include("--local-mode")
    end
  end
end
