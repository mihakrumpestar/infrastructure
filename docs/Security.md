# Security

## Nix-SOPS

Generate your own age key:

```sh
age-keygen
```

Get machines age key (from their public ssh):

```sh
ssh-keyscan -t ed25519 <server IP or hostname> | grep -v '^#' | ssh-to-age
```

If you update keys, run:

```sh
sopstool updatekeys
```

## OnlyKey

OnlyKey:

```sh
onlykey-cli fwversion
onlykey-cli getlabels

# Config mode
onlykey-cli idletimeout 120 # 120 minutes
onlykey-cli wipemode 2 # Full wipe

onlykey-cli keytypespeed 9 # Default is 7
onlykey-cli hmackeymode 0 # Enable or disable button press for HMAC challenge-response 0 = Button Press Required (default); 1 = Button Press Not Required.

onlykey-cli ledbrightness 1 # Default is 8 (1-10)
```

Sources:

- [OnlyKey cli docs](https://docs.onlykey.io/command-line.html)

## SOPS

Generate keys:

```sh
age-keygen

 export SOPS_AGE_RECIPIENTS=
 export SOPS_AGE_KEY=
```

Encrypt file:

```sh
sops -e -a [SOPS_AGE_RECIPIENTS] .env > .env
# or
sops -e .env > .env
# or
sops -e -i .env

# Edit file in memory
sops [file]

# Pass virtual non-encrypted file to other prosesses ('{}' is the file location placeholder)
sops exec-file --no-fifo .env 'docker-compose -f docker-compose.yml --env-file {} up -d --force-recreate'
# or using exec-env
```

## SSH

```sh
 ssh-keygen -t ed25519 -C "<comment>" -f ~/Desktop/ssh_key.pem
# space (' ') at start prevents it from being saved in history

# remove all ssh keys
ssh-add -D

# list keys
ssh-add -L

# show signature (must be in a git repo)
git show --show-signature
```
