# my-git: Multi-Profile Git Manager

A lightweight CLI toolset for seamless management of multiple Git identities (e.g., personal, work, freelance) on a single workstation without polluting global Git configurations.

Each profile maintains its own dedicated SSH key pair, commit metadata (`user.name`, `user.email`), and SSH cryptographic signing configuration (`gpg.format ssh`), applied strictly at the repository level.

---

## Key Features

* **Strict Repository Isolation**: Profile attributes are written exclusively to the local `.git/config`. Your global `~/.gitconfig` remains clean and unaffected.
* **Dedicated SSH Keys**: Bypasses SSH-agent key collisions via `core.sshCommand="ssh -i ... -o IdentitiesOnly=yes"`.
* **Zero-Friction SSH Signing**: Built-in support for native Git SSH commit and tag signing.
* **Automatic Permissions Management**: Automatically enforces strict POSIX permissions (`700` for directories, `600` for private keys, `644` for public keys).
* **Local Verification**: Centralized `allowed_signers` management eliminates `No principal matched` errors when running `git log --show-signature`.
* **System Keyring Integration**: `git-protect` migrates plaintext publish tokens into the system keyring; all tools resolve `secret-tool:` references at runtime via the shared `my-git-core.inc.sh` library.


---

## Installation

Clone the repository and run the `install-my-git` installer:

```bash
git clone [https://github.com/oldienki/my-git.git](https://github.com/oldienki/my-git.git)
cd my-git
./install-my-git

```

### What the installer does:

1. **Installs executables**: Copies all CLI tools and the shared library `my-git-core.inc.sh` (sourced by the tools at runtime) to `~/.local/bin` (or a specified directory).
2. **Initializes config directories**: Creates `~/.config/my-git/profiles` and `~/.config/my-git/keys` with strict `700` POSIX permissions.
3. **Installs shell completion**: Places `my-git-completion.bash` into `~/.config/my-git/`.
4. **Collision safety**: Checks for existing files or symlinks before writing. If collisions exist, it safely aborts unless forced.

### Installation Options:

* **Install to a custom path:**
```bash
./install-my-git /usr/local/bin

```


* **Force overwrite existing versions/symlinks:**
```bash
./install-my-git -f

```

---

## Shell Autocompletion Setup

Enable instant `<TAB>` completion for profile names, flags, and directories by adding the following snippet to your shell configuration:

### For Bash (`~/.bashrc`)

```bash
source ~/.config/my-git/my-git-completion.bash

```

### For Zsh (`~/.zshrc`)

```zsh
autoload -Uz compinit bashcompinit
compinit && bashcompinit
source ~/.config/my-git/my-git-completion.bash

```

---

## Directory Structure

All profiles, keys, and signer records reside under `${XDG_CONFIG_HOME:-~/.config}/my-git`:

```text
~/.config/my-git/
├── keys/
│   ├── work               # Private Ed25519 key (chmod 600)
│   ├── work.pub           # Public Ed25519 key (chmod 644)
│   ├── personal           # Private Ed25519 key (chmod 600)
│   └── personal.pub       # Public Ed25519 key (chmod 644)
├── profiles/
│   ├── work               # Profile config
│   └── personal           # Profile config
└── allowed_signers        # Public key registry for local signature verification

```

### Profile Configuration Format

Profiles are simple key-value files located in `~/.config/my-git/profiles/<profile_name>`:

```ini
name = Jane Doe
email = jane.doe@company.com
ssh_key = work
signing_key = work.pub

```

* Paths for `ssh_key` and `signing_key` can be relative to `~/.config/my-git/keys/`, `~/.ssh/`, or specified as absolute paths.

### Publish Token Fields

Profiles may carry registry credentials used by `git-cargo-publish`, `git-pypi-publish`, `git-uv-publish`, and `git-docker-publish`:

```ini
cargo_token = secret-tool:service=my-git,profile=work,token=cargo_token
pypi_token = pass:my-git/work/pypi
docker_user = jane
docker_token = secret-tool:service=my-git,profile=work,token=docker_token
docker_registry = ghcr.io
```

* **Plaintext** values are used verbatim.
* **`secret-tool:` references** are resolved at publish time from the system keyring via `resolve_token` (see `my-git-core.inc.sh`). `git-protect` writes these references automatically when migrating plaintext tokens.
* **`pass:` references** are treated as already secured and passed through unchanged.

---

## Utilities

### 1. `git-add-profile`

Initializes a new profile scaffold and handles cryptographic setup.

```bash
git-add-profile <profile>

```

#### What it does:

1. Generates an Ed25519 SSH key pair in `~/.config/my-git/keys/<profile>` (if one does not already exist).
2. Appends the public key to `~/.config/my-git/allowed_signers` with `namespaces="git"`.
3. Ensures `gpg.ssh.allowedSignersFile` is configured globally in Git.
4. Generates a template file at `~/.config/my-git/profiles/<profile>` with pre-filled key paths, leaving `name` and `email` for you to define.

---

### 2. `git-clone`

Clones a remote repository using the designated profile's SSH key and automatically configures repository-level identity and signing settings.

```bash
git-clone <profile> <git-url> [target_directory] [git_flags...]

```

#### Examples:

```bash
# Clone into default folder
git-clone work git@github.com:company/project.git

# Clone into a custom directory with additional Git arguments
git-clone personal git@github.com:octocat/hello-world.git my-app --depth 1

```

#### What it does:

1. Resolves and validates SSH key paths and permissions.
2. Clones the remote repository using `-c core.sshCommand="ssh -i <key> -o IdentitiesOnly=yes"`.
3. Navigates into the repository and writes local configurations:
* `core.sshCommand`
* `user.name` & `user.email`
* `gpg.format = ssh`
* `user.signingkey = <path_to_key>`
* `commit.gpgsign = true` & `tag.gpgsign = true`



---

### 3. `git-init`

Initializes a new local Git repository or configures an existing directory according to the selected profile.

```bash
git-init <profile> [path]

```

#### Examples:

```bash
# Initialize inside the current working directory
git-init work

# Initialize in a new directory
git-init personal ./new-service

```

#### What it does:

1. Runs `git init` on the target directory.
2. Applies the specified profile's identity, SSH transport configuration, and commit signing flags directly to `.git/config`.


---

### 4. `git-set-profile`

Applies or switches profile settings directly inside an existing Git repository or submodule.

```bash
git-set-profile <profile>

```

#### Examples:

```bash
# Apply a profile to an existing repository
cd ~/projects/legacy-repo
git-set-profile work

# Switch an active repository to a different identity
git-set-profile personal

# Configure a newly added submodule
cd libs/nested-module
git-set-profile freelance

```

#### What it does:

1. Verifies that the current directory is an active Git working tree (works transparently for regular repositories and submodules pointing to `.git/modules/...`).
2. Reads the profile settings from `~/.config/my-git/profiles/<profile>`.
3. Validates and enforces correct POSIX permissions on keys and directories.
4. Updates local repository configurations:
* Sets `core.sshCommand = ssh -i <key> -o IdentitiesOnly=yes` to ensure network actions (`pull`, `fetch`, `push`) use the correct key.
* Updates `user.name` and `user.email`.
* Configures SSH commit/tag signing (`gpg.format = ssh`, `user.signingkey`, `commit.gpgsign = true`).



#### Common Use Cases:

* **Nested Repositories & Submodules**: Safely apply an alternate identity to a sub-project or submodule residing inside a parent project without risking key or author leaks.
* **Migrating Existing Projects**: Adopt profiles across projects cloned prior to using `my-git` without needing to re-clone them.
* **Instant Profile Switching**: Reassign the commit identity and SSH key of an existing workspace in place.


---

### 5. `git-export-profile`

Bundles specified Git profiles and their associated private/public SSH keys into a password-protected, AES-256-CBC encrypted tar archive.

```bash
git-export-profile [--all | <profile1> [profile2 ...]] [-o <output_file>]

```

#### Options:

* `-a`, `--all`: Export all profiles present in `~/.config/my-git/profiles`.
* `-o`, `--output <file>`: Target archive path (defaults to `./my-git-export-<timestamp>.tar.enc`).
* `-h`, `--help`: Show usage instructions.

#### Examples:

```bash
# Export specific profiles
git-export-profile work personal

# Export all profiles to a custom backup path
git-export-profile --all -o ~/Desktop/my-git-backup.tar.enc

```

#### What it does:

1. Prompts for an encryption passphrase with non-echoed input and confirmation.
2. Isolates profile configurations and discovers all referenced SSH private and public keys.
3. Resolves `secret-tool:` token references back to plaintext in the staged copies, so the archive is portable across machines.
4. Stages the files into a clean temporary directory.
5. Creates a compressed `tar` archive and encrypts it using OpenSSL (`aes-256-cbc`, `-salt`, `-pbkdf2`, `100,000` iterations).
6. Clears sensitive passphrase variables from memory upon completion.

---

### 6. `git-import-profile`

Inspects or restores profiles and SSH keys from an encrypted archive created by `git-export-profile`.

```bash
git-import-profile <archive.tar.enc> [options | <profile1> [profile2 ...]]

```

#### Options:

* `-l`, `--list`: Display a table of all profiles in the archive (including names and emails) without importing anything.
* `-a`, `--all`: Import all profiles and keys stored in the archive.
* `--protect`: After import, migrate plaintext tokens into the system keyring and rewrite profile fields to `secret-tool:` references (same migration as `git-protect`).
* `<profile...>`: Import only the designated profile(s).
* `-h`, `--help`: Show usage instructions.

#### Examples:

```bash
# Preview archive contents (Profile name, Git User Name, Git Email)
git-import-profile backup.tar.enc --list

# Import every profile and key found in the archive
git-import-profile backup.tar.enc --all

# Selectively import specific profiles
git-import-profile backup.tar.enc work freelance

```

#### What it does:

1. Prompts for the archive decryption passphrase and unpacks contents into a secure temporary workspace.
2. In `--list` mode: parses and formats profile metadata into a terminal overview table.
3. In import mode:
* Restores profile configurations into `~/.config/my-git/profiles/`.
* Restores SSH private and public keys to `~/.config/my-git/keys/`, enforcing strict POSIX permissions (`600` for private keys, `644` for public keys, `700` for directories).
* Automatically extracts public signing keys and registers them in `~/.config/my-git/allowed_signers` (skipping duplicates).
* Configures Git's global `gpg.ssh.allowedSignersFile` setting if not already present.

---

### 7. `git-protect`

Audits profiles for plaintext credentials and insecure SSH keys, then hardens them.

```bash
git-protect <profile>
git-protect --all
```

#### What it does:

1. Migrates plaintext `cargo_token`, `pypi_token`, and `docker_token` values into the system keyring via `secret-tool` (requires `libsecret-tools`, e.g. `sudo apt install libsecret-tools`).
2. Rewrites the profile fields to `secret-tool:service=my-git,profile=<p>,token=<k>` references, leaving `pass:` references and already-protected fields untouched.
3. Preserves comments, blank lines, and field order in the profile file.
4. Enforces strict permissions (`600` profiles/private keys, `644` public keys, `700` directories).
5. Warns when a referenced SSH private key has an empty passphrase.

---

### 8. `git-cargo-publish`

Publishes a Rust crate with `cargo publish` using the `cargo_token` of the profile matching the repository's `user.email`.

```bash
git-cargo-publish [cargo_publish_options...]
```

Reads `git config user.email`, finds the matching profile, resolves `cargo_token` via `resolve_token`, and exports it as `CARGO_REGISTRY_TOKEN`. Forwards all arguments to `cargo publish`.

---

### 9. `git-pypi-publish`

Uploads a Python package to PyPI with `twine` using the profile's `pypi_token`.

```bash
git-pypi-publish [twine_options...] [dist_files...]
```

Resolves the token into `TWINE_PASSWORD` with `TWINE_USERNAME=__token__`, then runs `twine upload`. Defaults to `./dist/*` when no files are given.

---

### 10. `git-uv-publish`

Publishes a Python package with `uv publish` using the profile's `pypi_token`.

```bash
git-uv-publish [uv_publish_options...]
```

Resolves the token into `UV_PUBLISH_TOKEN` and forwards all arguments.

---

### 11. `git-docker-publish`

Pushes a Docker/OCI image using the profile's `docker_token`, with authentication isolated in an ephemeral `DOCKER_CONFIG` (leaves `~/.docker/config.json` untouched).

```bash
git-docker-publish [options] <image_name[:tag]> [docker_push_options...]
```

#### Options:

* `-r`, `--registry <url>`: Override the target registry (default from profile `docker_registry`, else `docker.io`).
* `-u`, `--user <username>`: Override the registry username.
* `-h`, `--help`: Show usage instructions.

Resolves `docker_token` and pipes it to `docker login --password-stdin`, pushes, then cleans up the temporary auth session.

---

## Quickstart

### 1. Installation

Place the scripts in a directory included in your `$PATH` (e.g., `~/.local/bin`):

```bash
install -m 755 git-add-profile git-clone git-init ~/.local/bin/

```

### 2. Create a Profile

```bash
git-add-profile work

```

Edit `~/.config/my-git/profiles/work` to set your credentials:

```ini
name = Jane Doe
email = jane.doe@company.com
ssh_key = work
signing_key = work.pub

```

### 3. Register the Key with GitHub / GitLab

Copy your public key:

```bash
cat ~/.config/my-git/keys/work.pub

```

* **GitHub**: Go to **Settings** $\to$ **SSH and GPG keys** $\to$ **New SSH key**.
* Add as **Authentication Key** (for git clone/push access).
* Add again as **Signing Key** (to display the **Verified** badge on commits).



### 4. Clone or Initialize

```bash
# Clone an existing repository
git-clone work git@github.com:company/repo.git

# Or start a fresh one
git-init work my-app

```

Verify your configuration inside the repository:

```bash
git config --local --list

```

