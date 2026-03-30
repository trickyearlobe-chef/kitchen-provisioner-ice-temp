# CLAUDE.md

## Project

- **Name**: kitchen-provisioner-ice-temp
- **Type**: Ruby gem — Test Kitchen provisioner plugin
- **Purpose**: Temporary stopgap provisioner that inherits from `ChefInfra` (kitchen-omnibus-chef) and overrides only the install path for chef-ice (chef-client 19+). Uninstall once Chef Workstation ships native support.

## Architecture

- Provisioner class: `Kitchen::Provisioner::ChefIce` inherits from `Kitchen::Provisioner::ChefInfra`
- Provisioner name in kitchen.yml: `chef_ice`
- Package downloaded on workstation during `create_sandbox`, uploaded via sandbox, installed from local file via `prepare_command`
- `install_command` is only the guard check (runs before upload)
- Everything else (sandbox, config files, run_command, policyfile/berkshelf) is inherited from ChefInfra
- Version: `lib/kitchen/provisioner/chef_ice/version.rb`
- Package cache shared with chef-pkg at `~/.chef/cached-packages/`

## Key Design Decisions

- **Thin layer.** Do NOT duplicate logic that already exists in test-kitchen or kitchen-omnibus-chef.
- Two install paths: (1) Chef commercial downloads API walked in Ruby on workstation, (2) `download_url` for direct package URL.
- License key NEVER leaves the workstation — API calls happen in Ruby, not in shell scripts on the node.
- No curl/wget needed on the node — package manager installs from a local file.
- **Zero extra gem dependencies.** `kitchen-omnibus-chef` is already in chef-workstation. Chef Workstation version pinning is VERY fragile — do NOT add gems.

## Conventions

- CLAUDE.md is operating rules for the AI, not project documentation.
- Keep it concise.
- NEVER use the console/terminal for file editing. Always use the edit tools in the IDE.

## File Layout

```
kitchen-provisioner-ice-temp.gemspec
Makefile
LICENSE
CHANGELOG.md
README.md
CLAUDE.md
lib/
  kitchen/
    provisioner/
      chef_ice.rb              # main provisioner (inherits ChefInfra)
      chef_ice/
        version.rb
spec/
  chef_ice_spec.rb
```

## Testing

- `make spec` — runs rspec
- `make build` — builds gem
- `make install` — builds and installs locally