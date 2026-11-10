#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_HOME/xdg"
    mkdir -p "$XDG_CONFIG_HOME/my-git/profiles" "$XDG_CONFIG_HOME/my-git/keys"
    export PATH="$REPO_ROOT/tests/helpers:$PATH"
    export STUB_SECRET_VALUE="keyring-secret-1"
    export STUB_STORE_LOG="$TEST_HOME/store.log"
    ARCHIVE="$TEST_HOME/exp.tar.enc"

    printf 'name = J\nemail = w@x.com\ncargo_token = secret-tool:service=my-git,profile=work,token=cargo_token\n' \
        >"$XDG_CONFIG_HOME/my-git/profiles/work"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "export resolves secret-tool refs to plaintext inside archive" {
    printf 'pw\npw\n' | "$REPO_ROOT/git-export-profile" work -o "$ARCHIVE" >/dev/null
    [ -f "$ARCHIVE" ]
    # Source profile must stay protected
    grep -q 'secret-tool:' "$XDG_CONFIG_HOME/my-git/profiles/work"
    # Decrypt and inspect staged profile
    printf 'pw\n' | openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
        -pass stdin -in "$ARCHIVE" 2>/dev/null | tar -xzO profiles/work |
        grep -q 'cargo_token = keyring-secret-1'
}

@test "export resolves secret-tool ref inside docker section to plaintext" {
    printf 'name = J\nemail = w@x.com\ndocker_token = secret-tool:service=my-git,profile=work,token=docker_token\n\n[docker:ghcr.io]\nuser = octocat\ntoken = secret-tool:service=my-git,profile=work,token=docker_ghcr_io\n' \
        >"$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'pw\npw\n' | "$REPO_ROOT/git-export-profile" work -o "$ARCHIVE" >/dev/null
    [ -f "$ARCHIVE" ]
    # Source profile must stay protected
    grep -q 'secret-tool:' "$XDG_CONFIG_HOME/my-git/profiles/work"
    # Decrypt and inspect staged profile: section token resolved to plaintext
    printf 'pw\n' | openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
        -pass stdin -in "$ARCHIVE" 2>/dev/null | tar -xzO profiles/work |
        grep -q 'token = keyring-secret-1'
}

@test "import --protect re-secures section tokens" {
    printf 'name = J\nemail = w@x.com\n\n[docker:ghcr.io]\nuser = octocat\ntoken = ghp_plain\n' \
        >"$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'pw\npw\n' | "$REPO_ROOT/git-export-profile" work -o "$ARCHIVE" >/dev/null
    rm "$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'pw\n' | "$REPO_ROOT/git-import-profile" "$ARCHIVE" --all --protect >/dev/null
    grep -q 'token = secret-tool:service=my-git,profile=work,token=docker_ghcr_io' \
        "$XDG_CONFIG_HOME/my-git/profiles/work"
    grep -q 'ghp_plain' "$STUB_STORE_LOG"
}

@test "import default keeps plaintext tokens" {
    printf 'pw\npw\n' | "$REPO_ROOT/git-export-profile" work -o "$ARCHIVE" >/dev/null
    rm "$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'pw\n' | "$REPO_ROOT/git-import-profile" "$ARCHIVE" --all >/dev/null
    grep -q 'cargo_token = keyring-secret-1' "$XDG_CONFIG_HOME/my-git/profiles/work"
    [ ! -f "$STUB_STORE_LOG" ]
}

@test "import --protect re-secures tokens" {
    printf 'pw\npw\n' | "$REPO_ROOT/git-export-profile" work -o "$ARCHIVE" >/dev/null
    rm "$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'pw\n' | "$REPO_ROOT/git-import-profile" "$ARCHIVE" --all --protect >/dev/null
    grep -q 'secret-tool:service=my-git' "$XDG_CONFIG_HOME/my-git/profiles/work"
    grep -q 'keyring-secret-1' "$STUB_STORE_LOG"
}

@test "import --list shows profiles without importing" {
    printf 'pw\npw\n' | "$REPO_ROOT/git-export-profile" work -o "$ARCHIVE" >/dev/null
    rm "$XDG_CONFIG_HOME/my-git/profiles/work"
    run bash -c "printf 'pw\n' | '$REPO_ROOT/git-import-profile' '$ARCHIVE' --list"
    [ "$status" -eq 0 ]
    [[ "$output" == *"work"* ]]
    [ ! -f "$XDG_CONFIG_HOME/my-git/profiles/work" ]
}

@test "import fails on wrong passphrase" {
    printf 'pw\npw\n' | "$REPO_ROOT/git-export-profile" work -o "$ARCHIVE" >/dev/null
    run bash -c "printf 'wrong\n' | '$REPO_ROOT/git-import-profile' '$ARCHIVE' --all"
    [ "$status" -ne 0 ]
    [[ "$output" == *"decrypt"* ]]
}
