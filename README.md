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
3. Stages the files into a clean temporary directory.
4. Creates a compressed `tar` archive and encrypts it using OpenSSL (`aes-256-cbc`, `-salt`, `-pbkdf2`, `100,000` iterations).
5. Clears sensitive passphrase variables from memory upon completion.

---

### 6. `git-import-profile`

Inspects or restores profiles and SSH keys from an encrypted archive created by `git-export-profile`.

```bash
git-import-profile <archive.tar.enc> [options | <profile1> [profile2 ...]]

```

#### Options:

* `-l`, `--list`: Display a table of all profiles in the archive (including names and emails) without importing anything.
* `-a`, `--all`: Import all profiles and keys stored in the archive.
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

