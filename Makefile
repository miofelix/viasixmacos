.PHONY: build test icon app verify-app clean

build:
	swift build

test:
	swift test

icon:
	./Scripts/generate-icon.sh

app:
	./Scripts/package-app.sh release

verify-app:
	./Scripts/verify-app.sh "$(CURDIR)/dist/ViaSix.app"

clean:
	swift package clean
	rm -rf "$(CURDIR)/dist"
