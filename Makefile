.PHONY: project test test-core test-ios check-android build-core-ios build-core-android check clean

project: build-core-ios
	xcodegen generate

test: test-core test-ios

test-core:
	cargo test --manifest-path core/Cargo.toml --all-features

test-ios: project
	xcodebuild test -project Herdie.xcodeproj -scheme Herdie -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' -derivedDataPath DerivedData ONLY_ACTIVE_ARCH=YES

check-android:
	cargo check --manifest-path core/Cargo.toml -p herdie-core --target aarch64-linux-android

build-core-ios:
	./scripts/build-core-ios.sh

build-core-android:
	./scripts/build-core-android.sh

check:
	cargo fmt --manifest-path core/Cargo.toml --all -- --check
	cargo clippy --manifest-path core/Cargo.toml --all-targets --all-features -- -D warnings
	$(MAKE) check-android
	$(MAKE) test

clean:
	./scripts/clean.sh
