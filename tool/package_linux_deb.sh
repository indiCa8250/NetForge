#!/usr/bin/env bash
# Packages Flutter's Linux release bundle as an installable Debian package.
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bundle="$project_root/build/linux/x64/release/bundle"
output_dir="$project_root/dist"
version=${1:?"Usage: tool/package_linux_deb.sh <debian-version>"}
architecture=${2:-amd64}
package_name=netforge
stage=$(mktemp -d)

cleanup() {
  rm -rf "$stage"
}
trap cleanup EXIT

if [[ ! -x "$bundle/netforge" ]]; then
  echo "Linux release bundle not found. Run: flutter build linux --release" >&2
  exit 1
fi

install -d "$stage/DEBIAN" "$stage/opt/$package_name" "$stage/usr/bin"
cp -a "$bundle/." "$stage/opt/$package_name/"

cat > "$stage/DEBIAN/control" <<EOF
Package: $package_name
Version: $version
Section: net
Priority: optional
Architecture: $architecture
Maintainer: NetForge
Description: Local-first network mapping toolkit for authorized assessments
 NetForge discovers and documents devices on networks you own or are
 authorized to assess.
EOF

cat > "$stage/usr/bin/netforge" <<'EOF'
#!/bin/sh
exec /opt/netforge/netforge "$@"
EOF
chmod 755 "$stage/usr/bin/netforge"

install -d "$output_dir"
package="$output_dir/${package_name}_${version}_${architecture}.deb"
dpkg-deb --build --root-owner-group "$stage" "$package"
echo "Created $package"
