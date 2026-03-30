GEM_NAME := kitchen-provisioner-ice-temp

CURRENT_VERSION := $(shell git describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//')
ifeq ($(CURRENT_VERSION),)
  CURRENT_VERSION := 0.0.0
endif
MAJOR := $(word 1,$(subst ., ,$(CURRENT_VERSION)))
MINOR := $(word 2,$(subst ., ,$(CURRENT_VERSION)))
PATCH := $(word 3,$(subst ., ,$(CURRENT_VERSION)))

.PHONY: help test build install clean version bump-patch bump-minor bump-major release

.DEFAULT_GOAL := help

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  test         Run rspec tests"
	@echo "  build        Build the gem into pkg/"
	@echo "  install      Build and install the gem locally"
	@echo "  clean        Remove build artifacts"
	@echo "  version      Show current version (from git tags)"
	@echo "  bump-patch   Tag a patch release  (x.y.Z+1)"
	@echo "  bump-minor   Tag a minor release  (x.Y+1.0)"
	@echo "  bump-major   Tag a major release  (X+1.0.0)"
	@echo "  release      Push main and tags to origin"

test:
	rspec

build: clean
	gem build $(GEM_NAME).gemspec
	mkdir -p pkg
	mv $(GEM_NAME)-*.gem pkg/

install: build
	gem install pkg/$(GEM_NAME)-*.gem

clean:
	rm -rf pkg/ tmp/ coverage/ $(GEM_NAME)-*.gem

version:
	@echo $(CURRENT_VERSION)

bump-patch:
	$(eval NEW_VERSION := $(MAJOR).$(MINOR).$(shell echo $$(($(PATCH)+1))))
	git tag -a "v$(NEW_VERSION)" -m "Release v$(NEW_VERSION)"
	@echo "Tagged v$(NEW_VERSION)"

bump-minor:
	$(eval NEW_VERSION := $(MAJOR).$(shell echo $$(($(MINOR)+1))).0)
	git tag -a "v$(NEW_VERSION)" -m "Release v$(NEW_VERSION)"
	@echo "Tagged v$(NEW_VERSION)"

bump-major:
	$(eval NEW_VERSION := $(shell echo $$(($(MAJOR)+1))).0.0)
	git tag -a "v$(NEW_VERSION)" -m "Release v$(NEW_VERSION)"
	@echo "Tagged v$(NEW_VERSION)"

release:
	@if [ -z "$(CURRENT_VERSION)" ] || [ "$(CURRENT_VERSION)" = "0.0.0" ]; then \
		echo "Error: no version tag found. Run make bump-patch/minor/major first."; \
		exit 1; \
	fi
	git push origin main --tags
	@echo "Pushed v$(CURRENT_VERSION)"
