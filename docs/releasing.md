# Releasing Berea from GitHub

Releases are built and signed in CI, so nothing needs a laptop or a cable. Berea on Android then
finds the release by itself and offers a bar to install it.

## One-time setup: the signing key

An update only installs over the Berea already on the phone if it is signed with the **same key**.
So CI must use the keystore your current release builds use (the file named in
`android/key.properties` on the machine that built your phone's app).

1. On that machine, make a base64 copy of the keystore:
   `base64 -i ~/berea-release.jks | pbcopy` (macOS) or `base64 -w0 ~/berea-release.jks` (Linux).
2. In GitHub: Settings, Secrets and variables, Actions, New repository secret. Add four:

   | Secret | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | the base64 text from step 1 |
   | `ANDROID_STORE_PASSWORD` | `storePassword` from `key.properties` |
   | `ANDROID_KEY_ALIAS` | `keyAlias` from `key.properties` |
   | `ANDROID_KEY_PASSWORD` | `keyPassword` from `key.properties` |

3. Keep the keystore file backed up somewhere safe. Lose it and no phone can ever update in place.

If your phone's Berea was built with no `key.properties`, it was signed with the debug key and
CI's release cannot replace it. Make a Berea backup (Settings, Back up), uninstall, install the
first CI release, and restore. That is the only time it costs anything.

## Cutting a release

1. Add a `## 0.9.1` section to `CHANGELOG.md` and merge it to `main`.
2. GitHub, Actions, Release, Run workflow (also possible from the GitHub mobile app), on `main`,
   with the version `0.9.1`. Or push a tag `v0.9.1`.
3. CI builds the database, runs the checks, signs, and publishes the release with
   `berea-android-arm64.apk`. It refuses a debug-signed build.

Use a plain version such as `0.9.1` for a release that phones should pick up. A version with a
dash (`0.9.1-rc1`) is published as a pre-release, which the in-app update does not look at.

## The first time

The Berea on your phone predates the update bar, so install the first CI release by hand: open the
release page on the phone, tap `berea-android-arm64.apk`, and allow the install. From then on the
bar does it.

macOS builds still come from `tool/release.sh` on a Mac.
