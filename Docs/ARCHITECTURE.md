# Architecture

> Developer documentation. End users should start with the [README](../README.md) or [ViaSix User Guide](USER_GUIDE.md).

ViaSix is split into a UI executable and an importable core library.

```text
ViaSixApp (SwiftUI, @MainActor)
    │
    ├── AppModel: user-visible state and workflow coordination
    │
ViaSixCore
    ├── Models: speed-test parameters, results and preferences
    ├── Parsing: CSV and streaming CFST output
    ├── Configuration: safe Xray template updates
    ├── Runtime: component installation and owned child processes
    └── Infrastructure: Application Support paths and persistence
```

## Writable data

The signed app bundle is treated as read-only. Mutable data is stored in:

```text
~/Library/Application Support/ViaSix/
  Data/
    preferences.json
    ip.txt
    ipv6.txt
    template.json
    config.json
    result.csv
  Runtime/
    cfst
    xray
    geoip.dat
    geosite.dat
  Logs/
```

Default resources are copied on first launch. An application update may migrate an exact byte-for-byte match of a previously shipped default, while any user-edited resource is preserved.

## Process ownership

ViaSix only stops child processes that it started and still owns. It never uses a global process-name kill. A speed-test run removes the prior CSV before launch, so an empty or failed run cannot be mistaken for cached success.

## Runtime installation

Official release archives are selected by CPU architecture, downloaded over HTTPS, verified against a pinned SHA-256 digest, expanded in a temporary directory and moved into place only after all required files are present. A user-selected local executable takes precedence over the managed copy.

The current distribution model is intended for Developer ID signing and notarization. It is not compatible with the Mac App Store sandbox because the application launches external networking helpers.
