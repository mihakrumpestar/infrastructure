{
  github-desktop,
  makeWrapper,
  symlinkJoin,
}:

# Unofficial patches:
# - oauth-linux: official builds gate protocol-URL handling behind
#   __WIN32__, so OAuth callbacks are dropped on Linux
# - keyring-adoption: adopt accounts from the system keychain on
#   fresh machines (zero-click sign-in across PCs sharing a keyring)
# - disable-background-fetch: gate all automatic fetches behind
#   GITHUB_DESKTOP_DISABLE_BACKGROUND_FETCH (set by the wrapper below)
symlinkJoin {
  name = "github-desktop-local";

  paths = [
    (github-desktop.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./github-desktop-oauth-linux.patch
        ./github-desktop-keyring-adoption.patch
        ./github-desktop-disable-background-fetch.patch
      ];
    }))
  ];

  nativeBuildInputs = [ makeWrapper ];

  # Stop automatic background fetches without touching the session
  # environment; override per-launch with
  # GITHUB_DESKTOP_DISABLE_BACKGROUND_FETCH=0.
  postBuild = ''
    wrapProgram $out/bin/github-desktop \
      --set-default GITHUB_DESKTOP_DISABLE_BACKGROUND_FETCH 1
  '';

  meta.mainProgram = "github-desktop";
}
