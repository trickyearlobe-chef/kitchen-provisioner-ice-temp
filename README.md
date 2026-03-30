# kitchen-provisioner-ice-temp

> **⚠️ This is a temporary stopgap gem.**
> It provides Chef ICE (Chef Infra Client 19+) support for Test Kitchen
> until a future Chef Workstation release ships with native chef-ice
> provisioning built in. Once you upgrade to that version of Chef
> Workstation, **uninstall this gem** and switch your `kitchen.yml` back
> to the built-in provisioner.

A [Test Kitchen](https://kitchen.ci/) provisioner for **Chef ICE** (Chef Infra Client 19+).

This is a thin layer on top of the existing `ChefInfra` provisioner from `kitchen-omnibus-chef`. It overrides only the install path to use the Chef commercial downloads API (or a direct URL). Everything else — cookbook upload, data bags, roles, config files, `chef-client --local-mode` execution — is inherited.

## Installation

```
gem install kitchen-provisioner-ice-temp
```

Or in your cookbook's `Gemfile`:

```ruby
gem "kitchen-provisioner-ice-temp"
```

## Usage

### Via Chef commercial downloads API

```yaml
provisioner:
  name: ice_temp
  product_version: 19.2.12      # or "latest"
  channel: stable
  chef_license_key: "your-key"  # or set CHEF_LICENSE_KEY env var
  chef_license: accept
```

### Via direct download URL

```yaml
provisioner:
  name: ice_temp
  download_url: https://my-mirror.example.com/chef-ice-19.2.12-1_amd64.deb
  checksum: abc123...            # optional SHA-256
  chef_license: accept
```

### Skip installation (pre-baked image)

```yaml
provisioner:
  name: ice_temp
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
| `downloads_api_url` | `https://commercial-acceptance.downloads.chef.co` | API base URL |
| `download_url` | `nil` | Direct package URL (bypasses API) |

## Removal

When a future Chef Workstation ships with native chef-ice support:

1. **Uninstall the gem:**

   ```
   chef exec gem uninstall kitchen-provisioner-ice-temp
   ```

2. **Update `kitchen.yml`** — change the provisioner name from `ice_temp` to whatever the new built-in provisioner is called (likely `chef_ice` or `chef_infra` with a `product_name: chef-ice` option):

   ```yaml
   provisioner:
     name: chef_ice          # or chef_infra — check the Chef Workstation release notes
     product_version: 19.2.12
     chef_license_key: "your-key"
     chef_license: accept
   ```

3. **Remove from Gemfile** (if listed):

   ```ruby
   # DELETE this line:
   gem "kitchen-provisioner-ice-temp"
   ```

That's it — all other configuration (`product_version`, `channel`, `chef_license_key`, etc.) should carry over to the built-in provisioner unchanged.

## License

Apache-2.0