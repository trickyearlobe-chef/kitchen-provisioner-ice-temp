# CLAUDE.md

## Project

- **Name**: kitchen-provisioner-ice-temp
- **Type**: Ruby gem — Test Kitchen provisioner plugin
- **Purpose**: Thin provisioner that inherits from `ChefInfra` (kitchen-omnibus-chef) and overrides only the install path for ice-temp (chef-client 19+).

## Architecture

- Provisioner class: `Kitchen::Provisioner::IceTemp` inherits from `Kitchen::Provisioner::ChefInfra`
- Only overrides: `install_command` and `self.new` (skip enterprise gem delegation)
- Everything else (sandbox, config files, run_command, policyfile/berkshelf) is inherited from ChefInfra
- Version: `lib/kitchen/provisioner/ice_temp/version.rb`

## Key Design Decisions

- **Thin layer.** Do NOT duplicate logic that already exists in test-kitchen or kitchen-omnibus-chef.
- Two install paths: (1) Chef commercial downloads API `install.sh` with `license_id`, (2) `download_url` (delegates to parent mixlib-install handling).
- Default `product_name` is `ice-temp`.
- **Zero extra gem dependencies.** Only `test-kitchen` declared. `kitchen-omnibus-chef` is already in chef-workstation. Chef Workstation version pinning is VERY fragile — do NOT add gems.

## Conventions

- CLAUDE.md is operating rules for the AI, not project documentation.
- Keep it concise.
- NEVER use the console/terminal for file editing. Always use `file-edit-mcp` tools (`fem_`).

## File Layout

```
kitchen-provisioner-ice-temp.gemspec
Gemfile
Makefile
LICENSE
CHANGELOG.md
README.md
CLAUDE.md
lib/
  kitchen/
    provisioner/
      ice_temp.rb              # main provisioner (inherits ChefInfra)
      ice_temp/
        version.rb
spec/
  ice_temp_spec.rb
```

## Testing

- `make test` — runs rspec
- `make build` — builds gem
- `make install` — builds and installs locally