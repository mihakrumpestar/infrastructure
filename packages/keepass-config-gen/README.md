# KeePassXC config generators

Generate OpenSSH client config, SSH signing trust, per-host git identities, Remmina RDP profiles, and GitHub CLI account metadata from a KeePassXC database. The package ships three binaries:

- `ssh-config-gen`: OpenSSH config, public keys, `allowed_signers`, git identities.
- `remmina-config-gen`: Remmina `.remmina` profiles, with the RDP password resolved from KeePassXC over Secret Service.
- `gh-config-gen`: `~/.config/gh/hosts.yml`, reconciled with the tokens KeePassXC publishes over Secret Service.

Neither tool writes private keys or RDP passwords to disk. SSH derives public keys only. Remmina writes `password=.` and lets Remmina fetch the password at connect time.

## How it works

- Both read entry metadata with `keepassxc-cli export -f xml`, write files atomically, and prune stale outputs from complete runs.
- SSH exports key attachments, derives public keys, and writes the config, `allowed_signers`, and git identities.
- Remmina sets `filename`, `key=password`, and `xdg:schema=org.remmina.Password` on the entry, then writes one profile per entry with `password=.`.

With a non-interactive credential, SSH unlocks at most twice: once for metadata and once for all attachments in one `keepassxc-cli open` session. An interactive run may prompt once per attachment. Remmina needs one XML export.

## Requirements

- `keepassxc-cli`, provided by the modules.
- SSH: private keys stored as KeePassXC attachments. External-file mode is not supported.
- Remmina: Remmina with libsecret, KeePassXC Secret Service enabled, the entry in the exposed group, and the database unlocked. `--check` can run offline with a warning; a locked service fails.
- Tray: a StatusNotifierItem host.

## KeePassXC entry setup

### SSH hosts

Add an `ssh_hosts` field with one host per line. Each line is a Host pattern or comma-separated patterns, followed by optional OpenSSH `Directive=Value` pairs:

```text
ssh_hosts:
  workstation HostName=192.0.2.10 Port=2200 User=admin
  git.example.com,git-alt HostName=git.example.com Port=443 User=git
  *.prod.example.com User=deploy ProxyJump=bastion
```

- The key is derived from the entry's attachment and shared by every host on the entry.
- `IdentityFile` and `IdentitiesOnly yes` are emitted automatically. An explicit `IdentityFile` on a line skips key derivation.
- Values may be quoted when they contain spaces.
- An entry with `ssh_hosts` but no derivable key is skipped with a warning.

### SSH signing

Add an `ssh_sign` field with one or more comma- or newline-separated principals:

```text
ssh_sign:
  me@example.com
```

Each principal is written to `allowed_signers` for that key.

### Git identities

Add `git.name` and `git.email` to an `ssh_hosts` line. The entry must also have `ssh_sign`.

```text
ssh_hosts:
  github-personal HostName=ssh.github.com Port=443 User=git git.name=Miha git.email=me@example.com
ssh_sign:
  me@example.com
```

This writes `~/.config/git/keepass-identities/github-personal` with `name`, `email`, and `signingkey`, plus an `include.conf` fragment that maps the SSH alias to that identity. With `git.enable`, `include.conf` is added to the global git config. Remotes must be scp-like `[user@]<alias>:path`; `ssh://` and remotes without a user are not matched.

### SSH private key

Attach the OpenSSH private key to the entry (Advanced -> Attachments) and select it in the SSH Agent tab. If the key is passphrase-protected, put the passphrase in the entry's Password field. Unencrypted keys are parsed directly.

### Remmina hosts

Add a `remmina_hosts` field with exactly one line of Remmina profile keys:

```text
remmina_hosts:
  server=rdp.example.com username=jdoe domain=EXAMPLE-DOMAIN group=Work quality=9
```

- `name` defaults to the Title; `protocol` to `RDP`; `username` to the entry's UserName.
- `server` is required.
- Other keys pass through, for example `gateway_server`, `cert_ignore`, `resolution_mode`, `sound`, `group`.
- Values may be quoted when they contain spaces.
- Inline `password`, `ssh_password`, `gateway_password`, `ssh_tunnel_password`, and `ssh_tunnel_passphrase` are rejected. KeePassXC is the only password source.
- The entry's Password field is the RDP password. The tool never reads, logs, or writes it.
- The entry must be in the group configured under Database settings -> Secret Service.

The tool sets three custom attributes on the entry:

```text
filename   = /home/you/.local/share/remmina/keepass_<slug>-<uuid>.remmina
key        = password
xdg:schema = org.remmina.Password
```

Do not mark them protected. `xdg:schema` is required: Remmina's libsecret lookup sends all three attributes, and KeePassXC matches every one. Without it, `filename` and `key` match but the lookup returns nothing.

Every profile contains `password=.`. Remmina sees the sentinel and asks `org.freedesktop.secrets` for the item. KeePassXC returns the Password field. The password exists only in memory during the connection.

If KeePassXC is locked, the tool stops and asks you to unlock it. If an entry is not in the exposed group, the tool skips it with a warning and keeps any existing profile.

## NixOS / Home Manager

The package exposes one home-manager module per tool.

```nix
inputs.keepass-config-gen.url = "./packages/keepass-config-gen";

# home-manager sharedModules
inputs.keepass-config-gen.homeManagerModules.ssh-config-gen
inputs.keepass-config-gen.homeManagerModules.remmina-config-gen
inputs.keepass-config-gen.homeManagerModules.gh-config-gen
```

```nix
programs.ssh-config-gen = {
  enable = true;
  database = "~/Passwords.kdbx";
  yubikey = "2";        # challenge-response slot[:serial]
  noPassword = true;
  # or:
  # passwordCommand = "secret-tool lookup service keepassxc";
  # passwordFile = "/run/secrets/keepass";
};

programs.remmina-config-gen = {
  enable = true;
  database = "~/Passwords.kdbx";
  yubikey = "2";
  noPassword = true;
};

programs.gh-config-gen = {
  enable = true;
};
```

### SSH options

| Option | Default | Purpose |
|---|---|---|
| `enable` | `false` | Install the CLI, the `~/.ssh/config` include, and the service/tray |
| `package` | built from this flake | Override the package |
| `database` | `~/Passwords.kdbx` | KeePassXC database to read |
| `keepassxcCli` | `pkgs.keepassxc`'s CLI | `keepassxc-cli` binary |
| `output` | `~/.ssh/config.d/keepass.conf` | Generated config fragment |
| `identitiesDir` | `~/.ssh/keepass-identities` | Derived public keys |
| `allowedSigners.enable` | `true` | Generate `allowed_signers` |
| `allowedSigners.path` | `~/.ssh/allowed_signers` | `allowed_signers` path |
| `git.enable` | `false` | Point git at `allowed_signers`, enable SSH signing, and generate git identities. Off by default to avoid conflicting definitions |
| `git.identitiesDir` | `~/.config/git/keepass-identities` | Git identity files and `include.conf` |
| `agentSocket` | `null` | Emit `IdentityAgent` in every `Host` block |
| `keyfile` | `null` | KeePassXC key file, if used |
| `yubikey` | `null` | Challenge-response slot, for example `"2"` or `"2:7370001"` |
| `noPassword` | `false` | Set when the database has no master password |
| `passwordCommand` / `passwordFile` | `null` | Non-interactive master password source |
| `includeInSshConfig` | `true` | Add the generated glob to `programs.ssh.includes` |
| `service.enable` | `true` | Install the on-demand regeneration service |
| `service.watch` | `false` | Regenerate on database change via a systemd path unit |
| `tray.enable` | `true` | System tray icon |

### Remmina options

| Option | Default | Purpose |
|---|---|---|
| `enable` | `false` | Install the CLI, the service, and the tray |
| `package` | built from this flake | Override the package |
| `database` | `~/Passwords.kdbx` | KeePassXC database to read |
| `keepassxcCli` | `pkgs.keepassxc`'s CLI | `keepassxc-cli` binary |
| `outputDir` | `null` | Remmina profile directory. `null` auto-detects from `remmina.pref` |
| `prefix` | `keepass_` | Filename prefix for generated profiles |
| `keyfile` | `null` | KeePassXC key file, if used |
| `yubikey` | `null` | Challenge-response slot, for example `"2"` or `"2:7370001"` |
| `noPassword` | `false` | Set when the database has no master password |
| `passwordCommand` / `passwordFile` | `null` | Non-interactive master password source |
| `service.enable` | `true` | Install the on-demand regeneration service |
| `service.watch` | `false` | Regenerate on database or `remmina.pref` change |
| `tray.enable` | `true` | System tray icon |

The service and tray require a non-interactive credential: `noPassword`, `passwordCommand`, or `passwordFile`. A key file or YubiKey alone is not enough. `gh-config-gen` is the exception: it never unlocks the database, it only reads what KeePassXC already publishes.

### gh options

| Option | Default | Purpose |
|---|---|---|
| `enable` | `false` | Install the CLI, the timer, and the tray |
| `package` | built from this flake | Override the package |
| `output` | `~/.config/gh/hosts.yml` | gh hosts file to reconcile. Must stay writable; `programs.gh.hosts` must stay empty |
| `service.enable` | `true` | Install the reconciliation service and its timer |
| `service.interval` | `15min` | How often to reconcile |
| `service.tray.enable` | `true` | System tray icon |

`gh-config-gen` reads only the `service` and `username` attributes of keyring items, so it cannot leak a token. Locked collections are skipped, never unlocked, so a run never prompts. A locked or absent keyring leaves the file untouched instead of emptying it.

KeePassXC exposes no unlock signal, so a timer polls instead of watching the database: one metadata-only D-Bus query every 15 minutes, which is also what notices a newly synced or newly unlocked account.

### When it regenerates

The services are on-demand and never start the database unlock at boot:

- Tray: left click or Refresh regenerates immediately.
- `service.watch = true`: a systemd path unit runs it when the database changes. Remmina also watches `remmina.pref`.
- Manually: `systemctl --user start ssh-config-gen` or `systemctl --user start remmina-config-gen`.
- `gh-config-gen`: oneshot on a timer, every 15 minutes, plus an explicit tray refresh. It never unlocks the database.

This keeps interactive or touch-requiring unlocks out of boot and activation.

## Command-line usage

SSH:

```sh
ssh-config-gen --database ~/Passwords.kdbx --print
ssh-config-gen --database ~/Passwords.kdbx --yubikey 2 --no-password --print
ssh-config-gen --database ~/Passwords.kdbx --yubikey 2 --no-password
ssh-config-gen --database ~/Passwords.kdbx --check
ssh-config-gen --database ~/Passwords.kdbx --if-changed
```

Without a configured credential, `--print` inherits the terminal. With key attachments, each export may prompt separately.

Remmina:

```sh
remmina-config-gen --database ~/Passwords.kdbx --yubikey 2 --no-password --print
remmina-config-gen --database ~/Passwords.kdbx --yubikey 2 --no-password
remmina-config-gen --database ~/Passwords.kdbx --check
remmina-config-gen --database ~/Passwords.kdbx --if-changed
```

`--check` is read-only but queries Secret Service for exposed entries. If the service is unavailable, it warns and assumes every entry is visible. If KeePassXC is locked, it fails. `--if-changed` checks the fingerprint and that listed files exist; use `--check` or a tray refresh for content drift.

GitHub CLI:

```sh
gh-config-gen --print
gh-config-gen --check
```

An unavailable or locked keyring is a warning, not a failure: the hosts file is left untouched rather than emptied.

Run `ssh-config-gen -h`, `remmina-config-gen -h`, or `gh-config-gen -h` for all flags.

## Generated files

| Path | Contents |
|---|---|
| `~/.ssh/config.d/keepass.conf` | SSH `Host` blocks |
| `~/.ssh/keepass-identities/*.pub` | Public keys derived from the database |
| `~/.ssh/allowed_signers` | `principal namespaces="git" <pubkey>` lines |
| `~/.config/git/keepass-identities/<alias>` | Per-identity git config |
| `~/.config/git/keepass-identities/include.conf` | `includeIf` fragment mapping SSH aliases to identities |
| `<remmina datadir>/keepass_<slug>-<uuid>.remmina` | Remmina profiles with `password=.` |
| `~/.config/gh/hosts.yml` | gh account metadata, rewritten from the keyring |
| `~/.local/state/ssh-config-gen/db-state` | SSH last database/options fingerprint |
| `~/.local/state/ssh-config-gen/log` | SSH tray last-run log |
| `~/.local/state/remmina-config-gen/state` | Remmina fingerprint plus generated profile paths |
| `~/.local/state/remmina-config-gen/log` | Remmina tray last-run log |
| `~/.local/state/gh-config-gen/log` | gh-config-gen tray last-run log |

Complete runs prune stale outputs: unused `.pub` files are removed, `allowed_signers` is rewritten, and old managed `.remmina` files are removed. Files without the configured prefix are never touched. A Remmina run that skips an entry does not prune: existing profiles are preserved and the state file is removed so the next run retries.

## Gotchas

- **`ssh-copy-id` needs `-f`.** The tool writes only public keys, so use `ssh-copy-id -f -i <pub> host`.
- **`~/.ssh/config` include ordering.** Home Manager renders `Include` first, and OpenSSH is first-match-wins. Do not define the same host in both places.
- **One owner for `allowed_signers`.** If another module writes `programs.git.settings.gpg.ssh.allowedSignersFile`, pick one owner.
- **Key passphrase.** An encrypted key uses the entry's Password field as its passphrase. Non-OpenSSH formats such as `.ppk` and PKCS#12 are not supported.
- **Challenge-response touch.** A touch-requiring slot cannot run unattended. Set the slot to "button press not required" for `service.watch`, or refresh from the tray.
- **Do not put secrets in `passwordCommand`.** The value is stored in the Nix store and unit file. Reference a secret path instead.
- **KeePassXC must own `org.freedesktop.secrets`.** If GNOME Keyring or KWallet owns the name, KeePassXC is not queried. If `ConfirmAccessItem` is enabled, the first attribute read or write prompts for approval.
- **The Remmina entry must be exposed.** An entry outside the Secret Service group is skipped. Unlock KeePassXC before connecting. Leave `disablepasswordstoring` at `0`; enabling it can delete the KeePassXC entry.
- **Remmina does not watch the profile directory.** New or removed profiles appear after a refresh or restart. A changed RDP password needs no regeneration. A changed `remmina_hosts` or title needs a refresh; a title change is pruned on the next complete run.
- **`--print` and `--check` are read-only.** Remmina `--check` may query Secret Service for visibility; see the command examples for its offline and locked behaviour.
- **`gh` needs the account in `hosts.yml`, not just the keyring.** That is the whole point of `gh-config-gen`. A token alone leaves `gh auth status` reporting "not logged in".
- **Do not also set `programs.gh.hosts`.** It generates a read-only store symlink at the same path; the module asserts the two are not combined.

## Troubleshooting

- Run with `--print` to see exactly what would be written.
- SSH failures: open **Show log** or `~/.local/state/ssh-config-gen/log`. Common causes are a wrong challenge-response slot, a touch-required slot, or `noPassword` set on a password-protected database.
- Remmina lookup: with KeePassXC unlocked, run `secret-tool lookup filename <absolute profile path> key password`. It should print the RDP password. `secret-tool` sends only `filename` and `key`, while Remmina also sends `xdg:schema=org.remmina.Password`. A successful lookup does not prove Remmina will match; the entry still needs the `xdg:schema` attribute.
- Check the provider with `busctl --user list | grep org.freedesktop.secrets`. Check a collection with `busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/<name> org.freedesktop.Secret.Collection Locked`.
- If Remmina logs that it cannot connect to a secrecy service, it started before KeePassXC's Secret Service was available. Its glibsecret plugin does not retry; restart Remmina after KeePassXC is running and unlocked.
- If a profile contains `password=` instead of `password=.`, Remmina saved it without a Secret Service connection. Refresh from the tray or rerun the generator, then reconnect after restarting Remmina.
- If the tray is missing, confirm the StatusNotifierItem widget is present in your panel and check `systemctl --user status ssh-config-gen-tray` or `systemctl --user status remmina-config-gen-tray`.
- `gh auth status` says "not logged in" while `secret-tool search service gh:github.com` finds the token: `hosts.yml` is stale or missing. Run `gh-config-gen --print` to see the document it would write, then `systemctl --user start gh-config-gen`. Check that KeePassXC owns `org.freedesktop.secrets` and that the entry is in the exposed group.

## Development

```sh
cd packages/keepass-config-gen
nix shell nixpkgs#go -c go vet ./...
nix shell nixpkgs#go -c go test ./...
nix build 'path:.#ssh-config-gen'
nix build 'path:.#remmina-config-gen'
nix build 'path:.#gh-config-gen'
```

Tests cover SSH parsing, key derivation, state and stale-file handling, an end-to-end SSH run against a fake CLI, Remmina datadir and `remmina_hosts` parsing, rendering and validation, pruning and state invalidation, check visibility and offline fallback, the Secret Service flow with a fake bus, and `hosts.yml` reconciliation: active-account precedence, orphan and inline-token users, preserved unknown keys, and idempotency. Tray tests cover private log permissions.

## Credits

Inspired by [rosec](https://github.com/jmylchreest/rosec).
