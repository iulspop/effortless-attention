# Contributing to Effortless

## Development

### Prerequisites

- macOS 14+ with Xcode or Command Line Tools
- Swift 5.10+

### Build & Run

```bash
swift build
.build/debug/Effortless &
```

## Releasing a New Version

### 1. Build the release `.app` bundle

```bash
./scripts/build-app.sh 0.2.0
```

This outputs:
- `.build/release/Effortless.app` — the app bundle
- `.build/release/Effortless.zip` — zipped for distribution
- The SHA256 hash of the zip (you'll need this)

### 2. Create a GitHub Release

```bash
gh release create v0.2.0 .build/release/Effortless.zip \
  --title "Effortless v0.2.0" \
  --notes "Release notes here..."
```

### 3. Update the Homebrew tap

In the [homebrew-effortless](https://github.com/iulspop/homebrew-effortless) repo, edit `Casks/effortless.rb`:

- Update `version` to the new version
- Update `sha256` to the hash from step 1

```ruby
cask "effortless" do
  version "0.2.0"
  sha256 "new-sha256-hash-here"
  # ...
end
```

Commit and push to `main`.

## Installing

```bash
brew tap iulspop/effortless
brew install --cask effortless
```

### Gatekeeper Note

The app is not code-signed. On first launch, macOS will block it. To open:

1. Right-click `Effortless.app` → **Open**, or
2. Go to **System Settings → Privacy & Security** and click **Open Anyway**

This only needs to be done once.
