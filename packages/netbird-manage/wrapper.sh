#!/usr/bin/env bash
# Reads NetBird credentials from the Secret Service, then execs the CLI.
# Keyring wins; NETBIRD_API_TOKEN / NETBIRD_API_URL are the headless fallback.
set -o errexit
set -o nounset
set -o pipefail

export PATH="@path@:${PATH:-}"

# KeePassXC names a client by /proc/<pid>/exe, and a symlink or `exec -a`
# resolves back to libsecret's store path, so the copy is the only way to make
# its notification say NetBird.
secret_tool="@secretTool@"

[ -x "$secret_tool" ] || { echo "netbird-manage: $secret_tool missing." >&2; exit 1; }
command -v jq >/dev/null || { echo "netbird-manage: jq missing." >&2; exit 1; }

item=$("$secret_tool" lookup service netbird 2>/dev/null) || item=""

token=""
url=""

case "$item" in
  "") ;;
  \{*)
    # JSON item carries the URL for self-hosted control planes.
    token=$(printf '%s' "$item" | jq -r '.token // ""') || {
      echo "netbird-manage: keyring item is not valid JSON." >&2
      exit 1
    }
    url=$(printf '%s' "$item" | jq -r '.url // ""')
    ;;
  *) token=$item ;;
esac

[ -n "$token" ] && export NETBIRD_API_TOKEN=$token
[ -n "$url" ] && export NETBIRD_API_URL=$url

if [ -z "${NETBIRD_API_TOKEN:-}" ]; then
  echo "netbird-manage: no credentials. Store one with:" >&2
  echo "  secret-tool store --label 'NetBird API' service netbird" >&2
  echo "Then unlock the KeePassXC database; a locked service fails the lookup." >&2
  exit 1
fi

exec @netbird@ "$@"
