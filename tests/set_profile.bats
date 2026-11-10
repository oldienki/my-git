#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_HOME/xdg"
    mkdir -p "$XDG_CONFIG_HOME/my-git/profiles" "$XDG_CONFIG_HOME/my-git/keys"

    REPO_DIR="$TEST_HOME/repo"
    git init -q "$REPO_DIR"

    printf 'name = Jane Doe\nemail = jane@example.com\nssh_key = work\nsigning_key = work.pub\n' \
        > "$XDG_CONFIG_HOME/my-git/profiles/work"
    touch "$XDG_CONFIG_HOME/my-git/keys/work" "$XDG_CONFIG_HOME/my-git/keys/work.pub"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "set-profile applies name, email, ssh command, signing" {
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-set-profile" work
    [ "$status" -eq 0 ]
    [ "$(git config user.name)" = "Jane Doe" ]
    [ "$(git config user.email)" = "jane@example.com" ]
    [[ "$(git config core.sshCommand)" == *"$XDG_CONFIG_HOME/my-git/keys/work"* ]]
    [ "$(git config gpg.format)" = "ssh" ]
    [ "$(git config commit.gpgsign)" = "true" ]
}

@test "set-profile without signing_key skips signing config" {
    printf 'name = J\nemail = j@x.com\n' > "$XDG_CONFIG_HOME/my-git/profiles/plain"
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-set-profile" plain
    [ "$status" -eq 0 ]
    [ -z "$(git config gpg.format 2>/dev/null || true)" ]
}

@test "set-profile errors on missing profile" {
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-set-profile" ghost
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "set-profile errors outside a git repo" {
    cd "$TEST_HOME"
    run "$REPO_ROOT/git-set-profile" work
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a Git repository"* ]]
}
