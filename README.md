# Herdie

Herdie is an open-source Herdr client for iPhone and iPad. It connects directly
to a macOS or Linux host over SSH, starts or reattaches to Herdr, and keeps the
mobile app disposable while work continues on the host.

The iOS app targets iOS 18. The portable session and terminal logic lives in
Rust so an Android app can use the same implementation later.

## Status

Herdie is under active development. See [the product specification](docs/PRODUCT.md)
and [architecture record](docs/ARCHITECTURE.md) for the current contract.

## Development

Requirements:

- Xcode 16 or newer
- XcodeGen
- Rust 1.85 or newer (edition 2024)
- Rust targets `aarch64-apple-ios`, `aarch64-apple-ios-sim`,
  `x86_64-apple-ios`, and `aarch64-linux-android`

Generate the Xcode project and run checks:

```sh
make project
make test
make check-android
```

`make build-core-android` additionally builds the SSH-enabled Android library
and Kotlin bindings when `ANDROID_NDK_HOME` points to an installed Android NDK.

Herdie never stores credentials in project files or user defaults. The iOS app
stores secrets in Keychain and sends them directly to the selected host.

Before an App Store release, follow the [release checklist](docs/APP_STORE.md).

## License

MIT. Herdie is independently implemented and does not bundle Herdr source.
