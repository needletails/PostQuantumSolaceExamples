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

sanitize_legacy_core_files() {
  # Remove old per-app copies of core types that have been
  # centralized into the shared `sample-core` package.
  local legacy_paths=(
    # Apple demo (old core copies under PostQuantumSolaceDemo)
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Configuration/AppConfiguration.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Extensions/URLSession+Extension.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Helpers/IRCEventLoopExecutor.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Managers/PQSDelegation/MessageReceiverManager.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Managers/PQSDelegation/PQSSessionDelegateWrapper.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Managers/PQSDelegation/SessionTransportManager.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Managers/PQSDelegation/WebSocketTransportManager.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Managers/SessionManager+Connection.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Managers/SessionManager.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Managers/Transport/IRCConnection.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Models/MessagePacket.swift"
    "Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo/Store/PQSSessionCache.swift"

    # Gnome demo (old core copies under Sources)
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Configuration/AppConfiguration.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Extensions/URLSession+Extension.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Helpers/IRCEventLoopExecutor.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Managers/PQSDelegation/MessageReceiverManager.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Managers/PQSDelegation/PQSSessionDelegateWrapper.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Managers/PQSDelegation/SessionTransportManager.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Managers/PQSDelegation/WebSocketTransportManager.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Managers/SessionManager+Connection.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Managers/SessionManager.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Managers/Transport/IRCConnection.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Models/MessagePacket.swift"
    "Gnome/post-quantum-solace-gnome-demo-app/Sources/Store/PQSSessionCache.swift"

    # Skip demo (old core copies under Sources/PostQuantumSolaceSkipDemo)
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Configuration/AppConfiguration.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Extensions/URLSession+Extension.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Helpers/IRCEventLoopExecutor.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Managers/PQSDelegation/MessageReceiverManager.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Managers/PQSDelegation/PQSSessionDelegateWrapper.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Managers/PQSDelegation/SessionTransportManager.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Managers/PQSDelegation/WebSocketTransportManager.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Managers/SessionManager+Connection.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Managers/SessionManager.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Managers/Transport/IRCConnection.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Models/MessagePacket.swift"
    "Skip/post-quantum-solace-skip-demo/Sources/PostQuantumSolaceSkipDemo/Store/PQSSessionCache.swift"
  )

  for path in "${legacy_paths[@]}"; do
    if [[ -f "$path" ]]; then
      rm "$path"
      changed_any=true
      echo "removed legacy core file: $path"
    fi
  done
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

# Remove legacy per-app core copies now that everything is shared via `sample-core`
sanitize_legacy_core_files

# Exit with success; pre-commit will add -u to stage changes
if [[ "$changed_any" == true ]]; then
  exit 0
fi

exit 0
