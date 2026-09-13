# Building and verifying releases

## Current status

This is a source-first preview with one physical LBP2900 page confirmed for each of C and Rust; see [exact results and open checks](HARDWARE-TESTING.md). The `v2.0.0-alpha.1` draft artifacts predate the transfer-status fix and must not be published as the validated build. Use current `main` source for C. There is no signed, notarized end-user release yet; follow [release work in issue #8](https://github.com/slpixe/canon-lbp2900-driver/issues/8). No Apple Developer ID certificates or notarization credentials are stored in the repository. An ad hoc signature is **not** Developer ID signing. An attestation is **not** notarization or a malware verdict.

CI builds source, runs offline tests, produces packages and can attest their origin. A version-tag release workflow creates only a **draft prerelease**, which a maintainer must review before publishing. Development packages carry `UNSIGNED` in their filenames. Do not recommend those packages as trusted click-to-install software. If macOS blocks a package/app, keep the protection in place; use a reviewed local source build or wait for a correctly signed release.

## Development packages

```sh
./scripts/package.sh --development
```

This builds locally as a normal user and writes:

- `dist/canon-lbp2900-driver-VERSION-UNSIGNED.pkg`: driver-only Installer package, with OS/CPU gating and a readme. No install scripts, launch services or automatic queue creation.
- `dist/LBP2900Progress-VERSION-UNSIGNED.zip`: the optional locally signed app; no automatic login startup.
- `dist/SHA256SUMS` and `dist/build-info.json`: hashes, exact source commit, dirty-tree indicator and toolchain information.

The driver package installs only the filter and PPD. Its readme describes selecting the USB printer and PPD in System Settings. The optional app is deliberately separate so nobody has to install it to print. Remove stale files from `dist/` when switching release versions or signing modes, and distribute only the exact artifacts listed in the current checksum manifest.

## Developer ID and notarization

For public click-to-install distribution, obtain your own Apple Developer Program identity and keep signing keys in a controlled Keychain. Build from a clean, reviewed commit and provide the identities through environment variables:

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: YOUR VERIFIED IDENTITY'
export DEVELOPER_ID_INSTALLER='Developer ID Installer: YOUR VERIFIED IDENTITY'
./scripts/package.sh
```

The script signs the filter and app with hardened runtime and a secure timestamp, and signs both Installer layers. The result has `SIGNED` in its filename, but is **not notarized yet**. Use an existing `notarytool` Keychain profile; do not put credentials in scripts or Git:

```sh
xcrun notarytool submit dist/canon-lbp2900-driver-VERSION-SIGNED.pkg --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/canon-lbp2900-driver-VERSION-SIGNED.pkg
xcrun notarytool submit dist/LBP2900Progress-VERSION-SIGNED.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple build/LBP2900Progress.app
```

Stop if either submission is not Accepted. Re-create the app ZIP from the stapled app using `ditto` as shown in `scripts/package.sh`; do not rebuild/re-sign the app at that point. Regenerate `SHA256SUMS` after stapling/repacking and generate attestations for the **final** bytes. The automatically generated development-build attestations do not apply to subsequently signed/notarized artifacts. Test installation, Gatekeeper behavior and printing on a clean target Mac before publishing.

Apple reference: [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

## Consumer verification

Get releases only from `https://github.com/slpixe/canon-lbp2900-driver/releases`. Check the release's preview/stable status, supported OS/CPU, source commit, test results and expected Developer ID team. A maintainer should publish that identity through a separately trusted channel.

```sh
shasum -a 256 -c SHA256SUMS
gh attestation verify PATH_TO_ARTIFACT --repo slpixe/canon-lbp2900-driver
pkgutil --check-signature PATH_TO_DRIVER.pkg
spctl --assess --type install --verbose=2 PATH_TO_DRIVER.pkg
codesign -dvvv PATH_TO/LBP2900Progress.app
codesign --verify --strict --verbose=2 PATH_TO/LBP2900Progress.app
syspolicy_check distribution PATH_TO/LBP2900Progress.app
```

These checks do not launch or install the artifacts. For attestation verification, confirm the expected repository, commit and workflow, not merely that *some* attestation exists. Keep the final build metadata alongside the artifact. Use GitHub's release source archive at that exact tag/commit to obtain the corresponding GPL source.

Checksums detect differences; they do not establish author identity by themselves. Valid code signatures do not prove absence of vulnerabilities. Gatekeeper/notarization adds Apple's distribution checks but is not a code audit. Failed checks are not an invitation to disable those checks.

For a signed Git tag, `git verify-tag TAG` requires a trusted signing key. Inherited upstream tags are unsigned. Creating an unsigned tag under a new name does not change that. This project does not claim that all Git commits/tags are signed.

## Maintainer release gate

- Clean source commit; CI, sanitizer, static-analysis and package-policy checks pass.
- Complete `HARDWARE-TESTING.md` with the actual source/artifact identity and target OS results.
- Inspect package contents, source archive and build metadata; no signing keys, local paths, prebuilt fallback or added service.
- Verify Developer ID signatures and accepted notarization for an ordinary end-user release.
- Publish hashes and attestations for final artifacts; preserve complete GPL source at the release commit.
- Review the draft and publish deliberately. CI never promotes a preview to stable automatically.
