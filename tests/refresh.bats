#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_HOME/xdg"
    PROFILES_DIR="$XDG_CONFIG_HOME/my-git/profiles"
    KEYS_DIR="$XDG_CONFIG_HOME/my-git/keys"
    mkdir -p "$PROFILES_DIR" "$KEYS_DIR"

    printf 'name = Jane Doe\nemail = jane@example.com\nssh_key = work\nsigning_key = work.pub\n' \
        > "$PROFILES_DIR/work"
    printf 'name = Plain Jane\nemail = plain@example.com\nssh_key = plain\n' \
        > "$PROFILES_DIR/plain"
    touch "$KEYS_DIR/work" "$KEYS_DIR/work.pub" "$KEYS_DIR/plain"
    printf 'jane@example.com %s\n' "$KEYS_DIR/work.pub" > "$XDG_CONFIG_HOME/my-git/allowed_signers"

    REPO_DIR="$TEST_HOME/repo"
    git init -q "$REPO_DIR"
}

teardown() {
    rm -rf "$TEST_HOME"
}

bind_via_set_profile() {
    (cd "$REPO_DIR" && "$REPO_ROOT/git-set-profile" work >/dev/null)
}

@test "refresh syncs bound repo and reports OK" {
    bind_via_set_profile
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-refresh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"* ]]
    [ "$(git config my-git.profile)" = "work" ]
}

@test "refresh updates values changed in profile" {
    bind_via_set_profile
    printf 'name = Jane New\nemail = jane@example.com\nssh_key = work\nsigning_key = work.pub\n' \
        > "$PROFILES_DIR/work"
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-refresh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[UPDATED] user.name"* ]]
    [ "$(git config user.name)" = "Jane New" ]
}

@test "refresh --force rewrites identical values" {
    bind_via_set_profile
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-refresh" --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"[UPDATED] user.name"* ]]
}

@test "refresh binds via user.email fallback with notice" {
    (cd "$REPO_DIR" && git config user.email "plain@example.com" \
        && git config user.name "Plain Jane")
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-refresh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Notice: bound repository to profile 'plain' via user.email"* ]]
    [ "$(git config my-git.profile)" = "plain" ]
}

@test "refresh unsets sshCommand and signing keys dropped from profile" {
    bind_via_set_profile
    printf 'name = Jane Doe\nemail = jane@example.com\n' > "$PROFILES_DIR/work"
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-refresh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[REMOVED] core.sshCommand"* ]]
    [[ "$output" == *"[REMOVED] user.signingkey"* ]]
    [ -z "$(git config core.sshCommand 2>/dev/null || true)" ]
    [ -z "$(git config user.signingkey 2>/dev/null || true)" ]
    [ -z "$(git config commit.gpgsign 2>/dev/null || true)" ]
    [ -z "$(git config tag.gpgsign 2>/dev/null || true)" ]
    [ -z "$(git config gpg.format 2>/dev/null || true)" ]
}

@test "refresh warns on missing key file and continues" {
    rm "$KEYS_DIR/work"
    bind_via_set_profile
    rm "$KEYS_DIR/plain"
    (cd "$REPO_DIR" && git config --unset core.sshCommand)
    printf 'name = Jane Doe\nemail = jane@example.com\nssh_key = gone\n' > "$PROFILES_DIR/work"
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-refresh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARNING]"* || "$output" == *"Warning"* ]]
}

@test "refresh sets sshCommand in IdentitiesOnly format" {
    bind_via_set_profile
    cd "$REPO_DIR"
    git config --unset core.sshCommand
    run "$REPO_ROOT/git-refresh"
    [ "$status" -eq 0 ]
    [ "$(git config core.sshCommand)" = "ssh -i $KEYS_DIR/work -o IdentitiesOnly=yes" ]
}

@test "refresh fails outside a git repo" {
    cd "$TEST_HOME"
    run "$REPO_ROOT/git-refresh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a Git repository"* ]]
}

@test "refresh fails when no profile matches" {
    (cd "$REPO_DIR" && git config user.email "nobody@example.com")
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-refresh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"No matching profile"* ]]
    [[ "$output" == *"git-set-profile"* ]]
}

@test "refresh falls back to email when bound profile was deleted" {
    bind_via_set_profile
    (cd "$REPO_DIR" && git config user.email "plain@example.com" \
        && git config user.name "Plain Jane")
    rm "$PROFILES_DIR/work"
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-refresh"
    [ "$status" -eq 0 ]
    [ "$(git config my-git.profile)" = "plain" ]
}

@test "refresh rejects unknown option" {
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-refresh" --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}
