# NetForge

NetForge is a local-first Flutter toolkit for mapping and documenting networks
during authorized assessments.

## Features

- Discover devices on the current LAN
- Save named network inventories with device labels, notes, MAC addresses, and ports
- Compare later LAN scans with saved devices
- Scan single, common, or all TCP ports
- View nearby Wi-Fi access points on Android
- Perform DNS lookups and subnet calculations
- Import and export readable network notes
- Store data locally on the device

## Run

```sh
flutter pub get
flutter run
```

Build an Android APK with:

```sh
flutter build apk --release
```

## Publishing updates

The in-app **Updates** screen checks the latest GitHub Release. Push a version
tag such as `v1.0.1` to publish a real update. GitHub Actions builds the Android
APK and Linux `.deb`, attaches them to that release, and the app will then offer
the matching download to anyone running an older version.

Before publishing the first release, create one Android release keystore and
configure these GitHub Actions repository secrets. Keep the keystore backed up:
every update must be signed with the same key.

- `ANDROID_KEYSTORE_BASE64`: the keystore file encoded with `base64 -w 0`
- `ANDROID_KEY_ALIAS`: the key alias
- `ANDROID_KEY_PASSWORD`: the key password
- `ANDROID_STORE_PASSWORD`: the keystore password

```sh
git tag v1.0.1
git push origin v1.0.1
```

Use NetForge only on networks you own or are authorized to assess.

## License

NetForge is licensed under the GNU General Public License v3.0.
