# Changelog

## 0.1.0

- Initial release
- Provisioner `chef_ice` for Test Kitchen
- Install via Chef commercial downloads API (`chef_license_key` required)
- Install via direct `download_url` (local mirror / S3 / etc.)
- Install strategy: `once`, `always`, `skip`
- Cookbook resolution via Policyfile, Berkshelf, or local copy
- SHA-256 checksum verification for direct downloads
- Platform-aware package installation (deb, rpm, sh, msi)
- Zero extra gem dependencies — runs inside chef-workstation as-is
