# Stress test

Stress test:

```sh
nix-shell -p stress s-tui --command "s-tui"
```

GPU:

```sh
nix shell nixpkgs#hashcat -c hashcat \
  -m 0 -a 3 -w 4 -O \
  --runtime=3600 --potfile-disable --status --status-timer=10 \ 
  "00000000000000000000000000000000" \
  "?a?a?a?a?a?a?a?a"
```

Watch CPU and GPU:

```sh
cpu-x
```

System:

```sh
btop
```
