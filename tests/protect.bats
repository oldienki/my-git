#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_HOME/xdg"
    mkdir -p "$XDG_CONFIG_HOME/my-git/profiles" "$XDG_CONFIG_HOME/my-git/keys"
    export PATH="$REPO_ROOT/tests/helpers:$PATH"
    export STUB_STORE_LOG="$TEST_HOME/store.log"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "git-protect migrates plaintext token to secret-tool ref" {
    p="$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'name = J\nemail = w@x.com\ncargo_token = tok-abc\n' >"$p"
    run "$REPO_ROOT/git-protect" work
    [ "$status" -eq 0 ]
    grep -q 'cargo_token = secret-tool:service=my-git,profile=work,token=cargo_token' "$p"
    grep -q 'tok-abc' "$STUB_STORE_LOG"
}

@test "git-protect leaves secret-tool: and pass: refs untouched" {
    p="$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'cargo_token = secret-tool:service=my-git,profile=work,token=cargo_token\npypi_token = pass:x/y\n' >"$p"
    run "$REPO_ROOT/git-protect" work
    [ "$status" -eq 0 ]
    [[ "$output" == *"already secured"* ]]
    grep -q 'pass:x/y' "$p"
    [ ! -f "$STUB_STORE_LOG" ]
}

@test "git-protect migrates plaintext token inside docker section" {
    p="$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'docker_user = wu\ndocker_token = flat-tok\n\n[docker:ghcr.io]\nuser = octocat\ntoken = ghp_plain\n' >"$p"
    run "$REPO_ROOT/git-protect" work
    [ "$status" -eq 0 ]
    grep -q 'docker_token = secret-tool:service=my-git,profile=work,token=docker_token' "$p"
    grep -q 'token = secret-tool:service=my-git,profile=work,token=docker_ghcr_io' "$p"
    grep -q 'ghp_plain' "$STUB_STORE_LOG"
    grep -q 'flat-tok' "$STUB_STORE_LOG"
    ! grep -q 'ghp_plain\|flat-tok' "$p"
}

@test "git-protect leaves secured refs inside docker section untouched" {
    p="$XDG_CONFIG_HOME/my-git/profiles/work"
    printf '[docker:ghcr.io]\nuser = u\ntoken = secret-tool:service=my-git,profile=work,token=docker_ghcr_io\n[docker:quay.io]\ntoken = pass:x/y\n' >"$p"
    run "$REPO_ROOT/git-protect" work
    [ "$status" -eq 0 ]
    grep -q 'pass:x/y' "$p"
    [ ! -f "$STUB_STORE_LOG" ]
}

@test "git-protect preserves section headers and non-token keys" {
    p="$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'name = J\n\n[docker:ghcr.io]\nuser = octocat\ntoken = t1\n' >"$p"
    run "$REPO_ROOT/git-protect" work
    [ "$status" -eq 0 ]
    grep -q '\[docker:ghcr.io\]' "$p"
    grep -q 'user = octocat' "$p"
}

@test "git-protect audits referenced ssh key" {
    p="$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'ssh_key = work\n' >"$p"
    ssh-keygen -t ed25519 -N "" -f "$XDG_CONFIG_HOME/my-git/keys/work" -q
    run "$REPO_ROOT/git-protect" work
    [ "$status" -eq 0 ]
    [[ "$output" == *"NO passphrase"* ]]
}

@test "git-protect fails on missing profile" {
    run "$REPO_ROOT/git-protect" ghost
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "git-protect processes all profiles with --all" {
    printf 'cargo_token = t1\n' >"$XDG_CONFIG_HOME/my-git/profiles/a"
    printf 'cargo_token = t2\n' >"$XDG_CONFIG_HOME/my-git/profiles/b"
    run "$REPO_ROOT/git-protect" --all
    [ "$status" -eq 0 ]
    grep -q 'secret-tool:' "$XDG_CONFIG_HOME/my-git/profiles/a"
    grep -q 'secret-tool:' "$XDG_CONFIG_HOME/my-git/profiles/b"
}

@test "git-protect enforces 600 on profile file" {
    p="$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'name = J\n' >"$p"
    chmod 644 "$p"
    "$REPO_ROOT/git-protect" work >/dev/null
    [ "$(stat -c %a "$p")" = "600" ]
}
