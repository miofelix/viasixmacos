SWIFT := swift
SWIFT_SOURCES := Sources Tests Package.swift
APP_BUNDLE := $(CURDIR)/dist/ViaSix.app
SHELL_SCRIPTS := $(wildcard Scripts/*.sh)

.PHONY: \
	build \
	build-release \
	run \
	test \
	format \
	format-check \
	lint \
	lint-scripts \
	lint-metadata \
	lint-docs \
	lint-licenses \
	check \
	icon \
	app \
	app-debug \
	verify-app \
	clean

build:
	$(SWIFT) build

build-release:
	$(SWIFT) build -c release

run:
	$(SWIFT) run ViaSix

test:
	$(SWIFT) test -Xswiftc -warnings-as-errors

format:
	$(SWIFT) format format --in-place --parallel --recursive $(SWIFT_SOURCES)

format-check:
	$(SWIFT) format lint --strict --parallel --recursive $(SWIFT_SOURCES)

lint-scripts:
	@for script in $(SHELL_SCRIPTS); do /bin/zsh -n "$$script"; done

lint-metadata:
	@plutil -lint \
		Packaging/Info.plist \
		Packaging/LaunchDaemons/com.felix.viasix.tun-helper.plist \
		Packaging/Entitlements/ViaSix.entitlements \
		Packaging/Entitlements/ViaSixTunHelper.entitlements >/dev/null
	@plutil -convert xml1 -o /dev/null Sources/ViaSixCore/Resources/local-proxy.json
	@test ! -e Sources/ViaSixCore/Resources/server.json
	@test ! -e Sources/ViaSixCore/Resources/template.json

lint-docs:
	@./Scripts/check-doc-links.sh

lint-licenses:
	@test -f LICENSE
	@grep -Fqx "MIT License" LICENSE
	@grep -Fqx "Copyright (c) 2026 ViaSix contributors" LICENSE
	@test "$$(shasum -a 256 ThirdPartyLicenses/CloudflareSpeedTest-GPL-3.0.txt | awk '{print $$1}')" = "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986"
	@test "$$(shasum -a 256 ThirdPartyLicenses/mihomo-GPL-3.0.txt | awk '{print $$1}')" = "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986"
	@test "$$(shasum -a 256 ThirdPartyLicenses/Yams-MIT.txt | awk '{print $$1}')" = "0354b0ea403d2e78059c5ae0510a2cfae9f8eb306fcef094ac9fff5b47e20bed"
	@test ! -e ThirdPartyLicenses/Xray-core-MPL-2.0.txt

lint: format-check lint-scripts lint-metadata lint-docs lint-licenses

check: lint
	$(SWIFT) build -c release -Xswiftc -warnings-as-errors
	$(MAKE) test

icon:
	./Scripts/generate-icon.sh

app:
	./Scripts/package-app.sh release

app-debug:
	./Scripts/package-app.sh debug

verify-app:
	./Scripts/verify-app.sh "$(APP_BUNDLE)"

clean:
	$(SWIFT) package clean
	rm -rf "$(CURDIR)/dist"
