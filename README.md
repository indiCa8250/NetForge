# NetForge

NetForge is a lean Android network field kit for authorized security assessments.

## Working modules

- TCP connect port scanner with hostname resolution, bounded concurrency, service labels, and response timing
- DNS A/AAAA lookup
- Local IPv4 interface discovery
- Session activity history
- Command-kit interface for keyboard-driven workflows
- Explicit authorization gate and local-only architecture

The scanner uses standard TCP sockets and does not need root. Port ranges are capped at 1,024
ports per range to keep accidental mobile resource use bounded.

## Run

```sh
flutter pub get
flutter run
```

Build an Android APK with `flutter build apk --release`.
