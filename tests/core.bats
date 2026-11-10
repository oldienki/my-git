#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    export XDG_CONFIG_HOME="$TEST_HOME/xdg"
    mkdir -p "$XDG_CONFIG_HOME/my-git/profiles" "$XDG_CONFIG_HOME/my-git/keys"
    export PATH="$REPO_ROOT/tests/helpers:$PATH"
    # shellcheck source=my-git-core.inc.sh
    . "$REPO_ROOT/my-git-core.inc.sh"
}

teardown() {
    rm -rf "$TEST_HOME"
}

# ---------- resolve_token ----------

@test "resolve_token returns plaintext verbatim" {
    run resolve_token "plain-token-123"
    [ "$status" -eq 0 ]
    [ "$output" = "plain-token-123" ]
}

@test "resolve_token returns empty string verbatim" {
    run resolve_token ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "resolve_token resolves secret-tool: reference via lookup" {
    export STUB_SECRET_VALUE="keyring-token-xyz"
    run resolve_token "secret-tool:service=my-git,profile=work,token=cargo_token"
    [ "$status" -eq 0 ]
    [ "$output" = "keyring-token-xyz" ]
}

@test "resolve_token returns empty on lookup failure" {
    export STUB_SECRET_MISSING=1
    run resolve_token "secret-tool:service=my-git,profile=work,token=cargo_token"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "resolve_token passes pass: reference through unchanged" {
    run resolve_token "pass:my-git/work/cargo"
    [ "$status" -eq 0 ]
    [ "$output" = "pass:my-git/work/cargo" ]
}

@test "resolve_token passes malformed secret-tool ref through verbatim" {
    run resolve_token "secret-tool:not-a-valid-ref"
    [ "$status" -eq 0 ]
    [ "$output" = "secret-tool:not-a-valid-ref" ]
}

# ---------- parse_field ----------

@test "parse_field extracts trimmed value" {
    f="$TEST_HOME/profile"
    printf 'name = Jane\nemail =  jane@example.com  \n' > "$f"
    run parse_field "$f" "email"
    [ "$output" = "jane@example.com" ]
}

@test "parse_field strips quotes" {
    f="$TEST_HOME/profile"
    printf 'name = "Jane Doe"\n' > "$f"
    run parse_field "$f" "name"
    [ "$output" = "Jane Doe" ]
}

@test "parse_field skips comments and blank lines" {
    f="$TEST_HOME/profile"
    printf '# comment\n\nname = Jane\n' > "$f"
    run parse_field "$f" "name"
    [ "$output" = "Jane" ]
}

@test "parse_field returns empty for missing key" {
    f="$TEST_HOME/profile"
    printf 'name = Jane\n' > "$f"
    run parse_field "$f" "email"
    [ "$output" = "" ]
}

# ---------- find_profile_by_email ----------

@test "find_profile_by_email returns matching profile name" {
    printf 'email = work@example.com\n' > "$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'email = home@example.com\n' > "$XDG_CONFIG_HOME/my-git/profiles/personal"
    run find_profile_by_email "home@example.com"
    [ "$status" -eq 0 ]
    [ "$output" = "personal" ]
}

@test "find_profile_by_email returns empty and nonzero on no match" {
    printf 'email = work@example.com\n' > "$XDG_CONFIG_HOME/my-git/profiles/work"
    run find_profile_by_email "nobody@example.com"
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

# ---------- resolve_key_path ----------

@test "resolve_key_path returns empty for empty input" {
    run resolve_key_path ""
    [ "$output" = "" ]
}

@test "resolve_key_path keeps absolute path" {
    run resolve_key_path "/abs/key"
    [ "$output" = "/abs/key" ]
}

@test "resolve_key_path expands tilde" {
    run resolve_key_path "~/key"
    [ "$output" = "$HOME/key" ]
}

@test "resolve_key_path prefers keys dir over ~/.ssh" {
    touch "$XDG_CONFIG_HOME/my-git/keys/mykey"
    run resolve_key_path "mykey"
    [ "$output" = "$XDG_CONFIG_HOME/my-git/keys/mykey" ]
}

@test "resolve_key_path falls back to ~/.ssh" {
    run resolve_key_path "otherkey"
    [ "$output" = "$HOME/.ssh/otherkey" ]
}

# ---------- protect_profile_tokens ----------

@test "protect_profile_tokens migrates plaintext token to keyring" {
    f="$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'name = J\ncargo_token = tok-abc\n' > "$f"
    export STUB_STORE_LOG="$TEST_HOME/store.log"
    protect_profile_tokens "$f" "work" >/dev/null
    grep -q 'cargo_token = secret-tool:service=my-git,profile=work,token=cargo_token' "$f"
    grep -q 'tok-abc' "$STUB_STORE_LOG"
}

@test "protect_profile_tokens skips secret-tool: and pass: values" {
    f="$XDG_CONFIG_HOME/my-git/profiles/work"
    printf 'cargo_token = secret-tool:service=my-git,profile=work,token=cargo_token\npypi_token = pass:my/pypi\n' > "$f"
    export STUB_STORE_LOG="$TEST_HOME/store.log"
    protect_profile_tokens "$f" "work" >/dev/null
    run cat "$f"
    [[ "$output" == *"secret-tool:service=my-git"* ]]
    [[ "$output" == *"pass:my/pypi"* ]]
    [ ! -f "$STUB_STORE_LOG" ]
}

@test "protect_profile_tokens preserves comments and blank lines" {
    f="$XDG_CONFIG_HOME/my-git/profiles/work"
    printf '# my comment\n\nname = J\n' > "$f"
    protect_profile_tokens "$f" "work" >/dev/null
    run cat "$f"
    [ "$output" = "# my comment"$'\n\n'"name = J" ]
}
