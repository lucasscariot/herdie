# App Store release checklist

The repository is ready to build and test locally. Distribution still requires
the project owner's Apple Developer account and App Store Connect record.

## Before the first archive

- Set `DEVELOPMENT_TEAM` through local Xcode signing settings. Do not commit a
  personal team identifier to the shared project specification.
- Create the App Store Connect app with bundle identifier
  `com.lucasscariot.herdie`, version `0.1.0`, and the intended public support,
  privacy-policy, and source-code URLs.
- Run the complete automated suite and a physical-device smoke test against a
  user-owned SSH host. Exercise password, private-key, Tailscale SSH, unknown
  host-key, changed host-key, background/foreground, resize, and reconnect
  paths.
- Capture final App Store screenshots on the supported iPhone and iPad sizes.
  Local product-reference images are design inputs, stay outside version
  control, and are not submission assets.

## Privacy

`PrivacyInfo.xcprivacy` declares no tracking or collected data and records the
required-reason use of UserDefaults as `CA92.1`. App Store privacy answers must
remain consistent with the shipped binary. Revisit both declarations before
adding analytics, crash reporting, accounts, a relay, or any hosted service.

Apple references:

- [Required-reason API entries](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)

## Encryption and export compliance

Herdie embeds SSH cryptography through its Rust dependencies; it does not rely
only on encryption supplied by Apple operating systems. Do not set
`ITSAppUsesNonExemptEncryption` to `false` merely to bypass App Store Connect's
questions.

Complete Apple's export-compliance questionnaire for every release and retain
the resulting documentation. Apple's current table identifies extra French
documentation for apps distributed in France that implement industry-standard
cryptography outside the operating system. Confirm the exact filing for the
shipping build with Apple or qualified counsel.

Apple references:

- [Export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- [Encryption documentation table](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/)

## Open-source release

- Create the public GitHub repository, add it as `origin`, and push `main` only
  after reviewing the initial commit for secrets and local artifacts.
- Keep the MIT license and publish source corresponding to every App Store
  release.
- Tag releases with the app version and document the Rust and Swift dependency
  revisions used by the archive.
- Enable branch protection and require the Rust, iOS unit, and iOS UI checks.

## Archive and submission

1. Update the marketing version and build number.
2. Generate the Xcode project from `project.yml`.
3. Run `make test` and `make check-android`.
4. Archive a generic iOS device build with the distribution signing team.
5. Validate and upload through Xcode, then complete privacy and export-compliance
   sections in App Store Connect.
6. Test the uploaded build in TestFlight on a physical device before submitting
   it for review.
