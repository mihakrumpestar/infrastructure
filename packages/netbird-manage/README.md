# netbird-manage

Admin CLI for the NetBird REST API. `services.netbird` only gives you the client agent (`up`, `down`, `status`); peers, policies, routes and DNS are API-only.

## Install

`pkgs.netbird-manage` from this flake. Credentials resolve per invocation, nothing is stored.

## Credentials

```sh
secret-tool store --label "NetBird API" service netbird
```

The password field is the raw PAT, or JSON when the control plane is self-hosted:

```json
{ "token": "nb_pat_...", "url": "https://netbird.example/api" }
```

Keyring wins. `NETBIRD_API_TOKEN` and `NETBIRD_API_URL` are the fallback for hosts with no session bus.

KeePassXC names clients by `/proc/<pid>/exe`, so the package ships its own copy as `libexec/netbird-secret-tool`: a symlink or `exec -a` still resolves to libsecret's path. Its notification reads `1 entry was used by …/libexec/netbird-secret-tool`.

Nothing shorter is possible; the protocol exposes no client name. With `ConfirmAccessItem=false` you get the notification only.

## Use

```sh
netbird-manage peer --list --output json
netbird-manage --yes dns-zone create --name internal --domain internal.example --distribution-groups <id>
```

Every read takes `--output json`, every mutation takes `--yes`, `--debug` dumps HTTP with the token redacted. A declined or unreadable prompt exits non-zero.

Service users hold one role, `User` (read-only) or `Admin` (write), with no per-resource scoping. Use two tokens if an agent needs both.

## Patches

`env-precedence.patch` adds `NETBIRD_API_URL` and makes the environment beat `~/.netbird-manage.json`. `cancel-exit.patch` returns an error on a declined prompt; upstream returned nil, so unattended runs exited 0 having done nothing.

Both ship tests, so the build fails if either regresses.

## Alternatives

| Tool | Why not |
|---|---|
| `netbird` (nixpkgs) | client agent only |
| `netbird-tui` | interactive TUI |
| `netbirdio/netbird-mcp` | not on npm, no DNS or posture writes |
| `aantti/mcp-netbird` | dead since 2025-04 |
| Terraform provider | declarative only |
