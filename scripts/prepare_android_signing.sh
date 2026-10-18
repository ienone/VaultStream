#!/usr/bin/env bash
set -euo pipefail
for name in ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
  if [[ -z "${!name:-}" ]]; then
    echo "::error::Required Android signing secret is missing: $name"
    exit 1
  fi
done
umask 077
printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > frontend/android/app/release.jks
cert_sha256=$(keytool -exportcert -keystore frontend/android/app/release.jks \
  -storepass:env ANDROID_KEYSTORE_PASSWORD -alias "$ANDROID_KEY_ALIAS" | sha256sum | cut -d ' ' -f 1)
# Seconds since 2020: shared by both workflows, within Android's 2100000000 limit.
# Avoid workflow-specific run_number counters and the oversized GitHub run_id.
version_code=$(( $(date -u +%s) - 1577836800 ))
(( version_code > 0 && version_code <= 2100000000 ))
printf 'cert_sha256=%s\nversion_code=%s\n' "$cert_sha256" "$version_code" >> "$GITHUB_OUTPUT"
