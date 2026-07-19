.PHONY: build test app clean

build:
	swift build

test:
	swift test

app:
	./Scripts/package-app.sh release

clean:
	swift package clean
	rm -rf "$(CURDIR)/dist"

