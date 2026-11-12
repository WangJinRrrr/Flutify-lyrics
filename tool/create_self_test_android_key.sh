#!/usr/bin/env bash
set -euo pipefail

# Only for disposable CI artifacts, never a replacement for the fixed release key.
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"
umask 077
key_file="$RUNNER_TEMP/flutify-self-test.p12"
if [[ -e "$key_file" ]]; then
  echo 'Self-test key already exists; refusing to overwrite it.' >&2
  exit 1
fi

export FLUTIFY_SELF_TEST_PASSWORD
FLUTIFY_SELF_TEST_PASSWORD="$(openssl rand -hex 24)"
printf '::add-mask::%s\n' "$FLUTIFY_SELF_TEST_PASSWORD"
keytool -genkeypair -noprompt -storetype PKCS12 -keystore "$key_file" \
  -alias flutify-self-test -keyalg RSA -keysize 2048 -validity 2 \
  -storepass:env FLUTIFY_SELF_TEST_PASSWORD -keypass:env FLUTIFY_SELF_TEST_PASSWORD \
  -dname 'CN=Flutify Self-test,OU=Disposable CI signing' >/dev/null
certificate_sha256="$(keytool -exportcert -keystore "$key_file" -alias flutify-self-test \
  -storepass:env FLUTIFY_SELF_TEST_PASSWORD | openssl dgst -sha256 -r | cut -d ' ' -f1)"

{
  printf 'ANDROID_KEYSTORE_PATH=%s\n' "$key_file"
  printf 'ANDROID_KEYSTORE_PASSWORD=%s\n' "$FLUTIFY_SELF_TEST_PASSWORD"
  printf 'ANDROID_KEY_ALIAS=flutify-self-test\n'
  printf 'ANDROID_KEY_PASSWORD=%s\n' "$FLUTIFY_SELF_TEST_PASSWORD"
  printf 'ANDROID_SIGNING_CERT_SHA256=%s\n' "$certificate_sha256"
} >> "$GITHUB_ENV"
printf 'Disposable self-test certificate SHA-256: %s\n' "$certificate_sha256"
