# ARCHITECTURE.md

This document describes the current architecture of the my-git project.
Update it incrementally as the system changes.

## 1. Overview

my-git is a collection of Bash CLI tools that manage multiple Git
identity profiles. Each profile binds an email, a name, an SSH key, a
commit-signing key, and publish tokens (Cargo, PyPI, Docker).
Tools are installed into a user bin directory by `install-my-git`.
Configuration lives under `${XDG_CONFIG_HOME:-$HOME/.config}/my-git`.

## 2. Components

### 2.1 Shared Library

- `my-git-core.inc.sh` — shared include file. Currently defines
  `resolve_token`, which resolves `secret-tool:` references to values
  in the system keyring via `secret-tool lookup`.

### 2.2 Profile Management Tools

- `git-add-profile` — creates a profile file, generates an Ed25519 SSH
  key pair, registers the public key in `allowed_signers`.
- `git-set-profile` — applies a profile to the current repository
  (`user.name`, `user.email`, `core.sshCommand`, SSH signing config).
- `git-protect` — migrates plaintext `cargo_token`, `pypi_token`, and
  `docker_token` values into the system keyring and rewrites the
  profile field to `secret-tool:service=my-git,profile=<p>,token=<k>`.
  Enforces 700/600 permissions and audits SSH key passphrases.
- `git-export-profile` — packs profiles and SSH keys into an AES-256-CBC
  encrypted tar archive.
- `git-import-profile` — restores profiles and keys from such an archive.
- `git-clone`, `git-init` — repository setup helpers.

### 2.3 Publish Tools

- `git-cargo-publish` — resolves `cargo_token`, runs `cargo publish`.
- `git-pypi-publish` — resolves `pypi_token`, runs `twine upload`.
- `git-uv-publish` — resolves `pypi_token`, runs `uv publish`.
- `git-docker-publish` — resolves `docker_token`, performs an isolated
  `docker login` in an ephemeral `DOCKER_CONFIG`, pushes the image.

### 2.4 Installer and Completion

- `install-my-git` — copies tool executables into a bin directory,
  creates config directories, installs `my-git-completion.bash`.

## 3. Data Layout

```text
$XDG_CONFIG_HOME/my-git/
  profiles/<name>      INI-style key = value files (chmod 600)
  keys/<name>[.pub]    Ed25519 SSH keys (private 600, public 644)
  allowed_signers      SSH allowed-signers file for commit signing
```

## 4. Data Flows

```text
profile file ──> git-set-profile ──> repo git config (user.*, core.sshCommand)
profile file ──> publish tools  ──> token env var ──> cargo/twine/uv/docker
profile file ──> git-protect    ──> secret-tool store; field rewritten
                                   to secret-tool: reference
profile+keys ──> git-export-profile ──> tar | openssl enc (AES-256-CBC)
```

## 5. Known Issues and Debt

- Publish tools read token fields verbatim and do not resolve
  `secret-tool:` references written by `git-protect`.
- `parse_field` and `resolve_key_path` are duplicated across scripts.
- `my-git-core.inc.sh` is not installed by `install-my-git` and is not
  sourced by any tool.
- `secret-tool:` references are per-machine; exported archives carry
  references that do not resolve on other machines.
