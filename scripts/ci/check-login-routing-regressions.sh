#!/usr/bin/env bash
set -euo pipefail

main_rs="src-tauri/src/main.rs"
nav_rs="src-tauri/src/proton_navigation.rs"

required_patterns=(
  "tauri://localhost/account/?hv_token="
  "captcha_completion_token(url)"
  "Do not infer completion from \"leaving\" verify.proton.me"
  "caused post-2FA freezes"
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$main_rs" "$nav_rs"; then
    echo "Missing login/2FA regression guard pattern: $pattern" >&2
    exit 1
  fi
done

forbidden_patterns=(
  "[CAPTCHA] Left captcha page, returning to account app"
  "Detect navigation AWAY from captcha to non-captcha page"
)

for pattern in "${forbidden_patterns[@]}"; do
  if grep -Fq "$pattern" "$main_rs"; then
    echo "Forbidden inferred CAPTCHA completion path found: $pattern" >&2
    exit 1
  fi
done

echo "Login/2FA routing regression checks passed"
