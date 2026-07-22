# ViaSix monorepo orchestrator.
# Platform-specific builds live under apps/*; this file only delegates.

MACOS_DIR := apps/macos
WINDOWS_DIR := apps/windows
ANDROID_DIR := apps/android
CONTRACTS_DIR := contracts

.PHONY: \
	help \
	macos-build \
	macos-test \
	macos-check \
	macos-app \
	macos-clean \
	windows-skeleton \
	windows-test \
	android-skeleton \
	contracts-check \
	check \
	check-all

help:
	@echo "ViaSix monorepo targets:"
	@echo "  make macos-check       - lint, build, test macOS app"
	@echo "  make macos-app         - package ad-hoc ViaSix.app"
	@echo "  make macos-build       - swift build (macOS)"
	@echo "  make macos-test        - swift test (macOS)"
	@echo "  make macos-clean       - clean macOS build artifacts"
	@echo "  make contracts-check   - verify contracts layout and fixtures"
	@echo "  make windows-skeleton  - verify Windows app tree"
	@echo "  make windows-test      - Rust contract projection tests (Windows host crate)"
	@echo "  make android-skeleton  - verify Android placeholder tree"
	@echo "  make check             - contracts + macOS check + windows-test (default CI)"
	@echo "  make check-all         - check + platform skeletons"

macos-build:
	$(MAKE) -C $(MACOS_DIR) build

macos-test:
	$(MAKE) -C $(MACOS_DIR) test

macos-check:
	$(MAKE) -C $(MACOS_DIR) check

macos-app:
	$(MAKE) -C $(MACOS_DIR) app

macos-clean:
	$(MAKE) -C $(MACOS_DIR) clean

contracts-check:
	@test -f "$(CONTRACTS_DIR)/VERSION"
	@test -f "$(CONTRACTS_DIR)/schemas/local-proxy.schema.json"
	@test -f "$(CONTRACTS_DIR)/schemas/x-viasix.schema.json"
	@test -d "$(CONTRACTS_DIR)/fixtures/mihomo-config/cases"
	@cases=0; \
	for dir in "$(CONTRACTS_DIR)/fixtures/mihomo-config/cases"/*; do \
	  [ -d "$$dir" ] || continue; \
	  test -f "$$dir/case.json" || { echo "missing case.json in $$dir"; exit 1; }; \
	  test -f "$$dir/input.yaml" || { echo "missing input.yaml in $$dir"; exit 1; }; \
	  cases=$$((cases + 1)); \
	done; \
	test "$$cases" -ge 1 || { echo "no contract fixture cases found"; exit 1; }; \
	echo "contracts layout OK (version $$(cat "$(CONTRACTS_DIR)/VERSION"), $$cases cases)"

windows-skeleton:
	@test -f "$(WINDOWS_DIR)/README.md"
	@test -f "$(WINDOWS_DIR)/package.json"
	@test -f "$(WINDOWS_DIR)/src-tauri/Cargo.toml"
	@test -f "$(WINDOWS_DIR)/src-tauri/src/projection/mod.rs"
	@test -f "$(WINDOWS_DIR)/scripts/fetch-mihomo.mjs"
	@test -f "$(WINDOWS_DIR)/src/main.ts"
	@echo "windows skeleton OK"

windows-test:
	cargo test --manifest-path "$(WINDOWS_DIR)/src-tauri/Cargo.toml"

android-skeleton:
	@test -f "$(ANDROID_DIR)/README.md"
	@test -f "$(ANDROID_DIR)/settings.gradle.kts"
	@test -f "$(ANDROID_DIR)/app/src/main/AndroidManifest.xml"
	@test -f "$(ANDROID_DIR)/app/src/main/java/dev/viasix/app/Placeholder.kt"
	@echo "android skeleton OK"

check: contracts-check macos-check windows-test

check-all: check windows-skeleton android-skeleton
