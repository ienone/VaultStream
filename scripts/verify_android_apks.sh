#!/usr/bin/env bash
set -euo pipefail
: "${EXPECTED_CERT_SHA256:?}"
: "${EXPECTED_VERSION_CODE:?}"
sdk_tools=$(find "${ANDROID_HOME:?}/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
shopt -s nullglob
apks=(frontend/build/app/outputs/flutter-apk/*.apk)
(( ${#apks[@]} > 0 ))
for apk in "${apks[@]}"; do
  certificate=$("$sdk_tools/apksigner" verify --print-certs "$apk")
  actual=$(printf '%s\n' "$certificate" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
  [[ "$actual" == "$EXPECTED_CERT_SHA256" ]] || { echo "::error::Signing certificate mismatch: $apk"; exit 1; }
  package=$("$sdk_tools/aapt" dump badging "$apk" | sed -n '1p')
  [[ "$package" == *"name='com.vaultstream.frontend'"* ]] || { echo "::error::Package name mismatch: $apk"; exit 1; }
  [[ "$package" == *"versionCode='$EXPECTED_VERSION_CODE'"* ]] || { echo "::error::Version code mismatch: $apk"; exit 1; }
  printf '%s\n%s\nSHA-256: %s\n' "$apk" "$package" "$actual"
done
