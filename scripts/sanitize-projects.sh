#!/usr/bin/env bash
set -euo pipefail

# Sanitize Xcode project files and Skip env by removing team IDs
# and clearing bundle identifiers. Intended to run locally or via pre-commit.

repo_root_dir="$(cd "$(dirname "$0")"/.. && pwd)"
cd "$repo_root_dir"

changed_any=false

sanitize_pbxproj() {
  local file="$1"
  # Remove DEVELOPMENT_TEAM lines and clear PRODUCT_BUNDLE_IDENTIFIER values.
  # Works with BSD/macOS perl.
  perl -0777 -i -pe '
    s/^([ \t]*)DEVELOPMENT_TEAM\s*=\s*[^;]*;\n//mg;
    s/^([ \t]*PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)([^;]*);/$1"";/mg;
  ' "$file"
}

sanitize_skip_env() {
  local file="$1"
  perl -0777 -i -pe '
    s/^(PRODUCT_BUNDLE_IDENTIFIER\s*=).*/$1/mi;
  ' "$file"
}

# Track before/after hashes to see if modifications happened
file_changed() {
  local file="$1"
  local before_hash="$2"
  local after_hash
  after_hash="$(shasum "$file" | awk '{print $1}')"
  [[ "$before_hash" != "$after_hash" ]]
}

# Sanitize all Xcode project files
while IFS= read -r -d '' pbx; do
  before="$(shasum "$pbx" | awk '{print $1}')"
  sanitize_pbxproj "$pbx"
  if file_changed "$pbx" "$before"; then
    changed_any=true
    echo "sanitized: $pbx"
  fi
done < <(find . -type f -name project.pbxproj -print0)

# Sanitize Skip.env files (if present)
while IFS= read -r -d '' senv; do
  before="$(shasum "$senv" | awk '{print $1}')"
  sanitize_skip_env "$senv"
  if file_changed "$senv" "$before"; then
    changed_any=true
    echo "sanitized: $senv"
  fi
done < <(find . -type f -name Skip.env -print0)

# Exit with success; pre-commit will add -u to stage changes
if [[ "$changed_any" == true ]]; then
  exit 0
fi

exit 0
