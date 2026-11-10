#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_HOME/xdg"
    mkdir -p "$XDG_CONFIG_HOME/my-git/profiles" "$XDG_CONFIG_HOME/my-git/keys"

    # Shadow bin: tool stubs + secret-tool stub
    SHADOW_BIN="$TEST_HOME/bin"
    mkdir -p "$SHADOW_BIN"
    for t in cargo twine uv docker; do
        ln -s "$REPO_ROOT/tests/helpers/capture-tool" "$SHADOW_BIN/$t"
    done
    ln -sf "$REPO_ROOT/tests/helpers/secret-tool" "$SHADOW_BIN/secret-tool"
    export PATH="$SHADOW_BIN:$PATH"
    export CAPTURE_LOG="$TEST_HOME/capture.log"
    export STUB_SECRET_VALUE="keyring-secret-1"

    # Temp git repo with user.email matching a profile
    REPO_DIR="$TEST_HOME/repo"
    git init -q "$REPO_DIR"
    git -C "$REPO_DIR" config user.email "work@example.com"
    git -C "$REPO_DIR" config user.name "T"
    git -C "$REPO_DIR" commit -q --allow-empty -m init

    printf 'email = work@example.com\ncargo_token = secret-tool:service=my-git,profile=work,token=cargo_token\npypi_token = secret-tool:service=my-git,profile=work,token=pypi_token\ndocker_user = wu\ndocker_token = secret-tool:service=my-git,profile=work,token=docker_token\n' \
        > "$XDG_CONFIG_HOME/my-git/profiles/work"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "cargo-publish resolves secret-tool ref into CARGO_REGISTRY_TOKEN" {
    run "$REPO_ROOT/git-cargo-publish" --dry-run
    [ "$status" -eq 0 ]
    grep -q 'cargo | CARGO_REGISTRY_TOKEN=keyring-secret-1' "$CAPTURE_LOG"
}

@test "cargo-publish works with plaintext token too" {
    printf 'email = work@example.com\ncargo_token = plain-tok\n' \
        > "$XDG_CONFIG_HOME/my-git/profiles/work"
    run "$REPO_ROOT/git-cargo-publish" --dry-run
    [ "$status" -eq 0 ]
    grep -q 'cargo | CARGO_REGISTRY_TOKEN=plain-tok' "$CAPTURE_LOG"
}

@test "cargo-publish errors when lookup returns empty" {
    export STUB_SECRET_MISSING=1
    run "$REPO_ROOT/git-cargo-publish" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"cargo_token"* ]]
}

@test "pypi-publish resolves ref into TWINE_PASSWORD" {
    mkdir -p "$REPO_DIR/dist" && touch "$REPO_DIR/dist/x.whl"
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-pypi-publish"
    [ "$status" -eq 0 ]
    grep -q 'twine | TWINE_USERNAME=__token__ TWINE_PASSWORD=keyring-secret-1' "$CAPTURE_LOG"
}

@test "uv-publish resolves ref into UV_PUBLISH_TOKEN" {
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-uv-publish" --dry-run
    [ "$status" -eq 0 ]
    grep -q 'uv | UV_PUBLISH_TOKEN=keyring-secret-1' "$CAPTURE_LOG"
}

@test "docker-publish resolves ref into login password" {
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-docker-publish" img:1
    [ "$status" -eq 0 ]
    grep -q 'docker | login-password=keyring-secret-1' "$CAPTURE_LOG"
    grep -q 'docker | argv: login docker.io --username wu --password-stdin' "$CAPTURE_LOG"
}

@test "publish tools error when no profile matches email" {
    git -C "$REPO_DIR" config user.email "other@example.com"
    cd "$REPO_DIR"
    run "$REPO_ROOT/git-cargo-publish" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"No profile found"* ]]
}
