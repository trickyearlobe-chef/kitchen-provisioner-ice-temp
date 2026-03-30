# kitchen-provisioner-chef-ice

A [Test Kitchen](https://kitchen.ci/) provisioner for **Chef ICE** (Chef Infra Client 19+).

This is a thin layer on top of the existing `ChefInfra` provisioner from `kitchen-omnibus-chef`. It overrides only the install path to use the Chef commercial downloads API (or a direct URL). Everything else — cookbook upload, data bags, roles, config files, `chef-client --local-mode` execution — is inherited.

## Installation

```
gem install kitchen-provisioner-chef-ice
```

Or in your cookbook's `Gemfile`:

```ruby
gem "kitchen-provisioner-chef-ice"
```

## Usage

### Via Chef commercial downloads API

```yaml
provisioner:
  name: chef_ice
  product_version: 19.2.12      # or "latest"
  channel: stable
  chef_license_key: "your-key"  # or set CHEF_LICENSE_KEY env var
  chef_license: accept
```

### Via direct download URL

```yaml
provisioner:
  name: chef_ice
  download_url: https://my-mirror.example.com/chef-ice-19.2.12-1_amd64.deb
  checksum: abc123...            # optional SHA-256
  chef_license: accept
```

### Skip installation (pre-baked image)

```yaml
provisioner:
  name: chef_ice
  install_strategy: skip
  chef_license: accept
```

## Configuration

All settings from the standard `chef_infra` / `chef_zero` provisioner are supported. Additional settings:

| Setting | Default | Description |
|---------|---------|-------------|
| `product_version` | `latest` | Chef ICE version |
| `channel` | `stable` | Release channel |
| `chef_license_key` | `ENV["CHEF_LICENSE_KEY"]` | License key for commercial API |
| `downloads_api_url` | `https://chefdownload-commercial.chef.io` | API base URL |
| `download_url` | `nil` | Direct package URL (bypasses API) |

## License

Apache-2.0
