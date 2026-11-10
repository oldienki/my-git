#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_HOME/xdg"
    mkdir -p "$XDG_CONFIG_HOME/my-git/profiles" "$XDG_CONFIG_HOME/my-git/keys"

    printf 'name = Jane Doe\nemail = jane@example.com\nssh_key = work\nsigning_key = work.pub\n' \
        > "$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'name = J\nemail = j@x.com\nssh_key = plain\n' \
        > "$XDG_CONFIG_HOME/my-git/profiles/plain"
    touch "$XDG_CONFIG_HOME/my-git/keys/work" "$XDG_CONFIG_HOME/my-git/keys/work.pub" \
        "$XDG_CONFIG_HOME/my-git/keys/plain"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "git-init writes my-git.profile" {
    run "$REPO_ROOT/git-init" work "$TEST_HOME/repo"
    [ "$status" -eq 0 ]
    [ "$(git -C "$TEST_HOME/repo" config my-git.profile)" = "work" ]
    [ "$(git -C "$TEST_HOME/repo" config user.name)" = "Jane Doe" ]
}

@test "git-init writes my-git.profile without signing_key" {
    run "$REPO_ROOT/git-init" plain "$TEST_HOME/plain-repo"
    [ "$status" -eq 0 ]
    [ "$(git -C "$TEST_HOME/plain-repo" config my-git.profile)" = "plain" ]
    [ -z "$(git -C "$TEST_HOME/plain-repo" config gpg.format 2>/dev/null || true)" ]
}

@test "git-init errors on missing profile" {
    run "$REPO_ROOT/git-init" ghost "$TEST_HOME/ghost-repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "git-clone writes my-git.profile" {
    git init -q --bare "$TEST_HOME/remote.git"
    run "$REPO_ROOT/git-clone" work "file://$TEST_HOME/remote.git" "$TEST_HOME/clone"
    [ "$status" -eq 0 ]
    [ "$(git -C "$TEST_HOME/clone" config my-git.profile)" = "work" ]
    [ "$(git -C "$TEST_HOME/clone" config user.email)" = "jane@example.com" ]
    [ -n "$(git -C "$TEST_HOME/clone" config commit.gpgsign)" ]
}

@test "git-clone errors on missing profile" {
    run "$REPO_ROOT/git-clone" ghost "file://$TEST_HOME/remote.git" "$TEST_HOME/ghost-clone"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}
