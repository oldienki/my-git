#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_HOME/xdg"
    TARGET="$TEST_HOME/bin"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "install-my-git copies tools and shared include" {
    run "$REPO_ROOT/install-my-git" "$TARGET"
    [ "$status" -eq 0 ]
    [ -x "$TARGET/git-cargo-publish" ]
    [ -f "$TARGET/my-git-core.inc.sh" ]
    [ ! -x "$TARGET/my-git-core.inc.sh" ]
}

@test "installed tool sources sibling include successfully" {
    "$REPO_ROOT/install-my-git" "$TARGET" >/dev/null
    run "$TARGET/git-set-profile" work
    [[ "$output" != *"my-git-core.inc.sh' not found"* ]]
}

@test "install aborts listing missing include" {
    mv "$REPO_ROOT/my-git-core.inc.sh" "$TEST_HOME/hidden"
    run "$REPO_ROOT/install-my-git" "$TARGET"
    mv "$TEST_HOME/hidden" "$REPO_ROOT/my-git-core.inc.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"my-git-core.inc.sh"* ]]
}
