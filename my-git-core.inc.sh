# shellcheck shell=bash
# my-git-core.inc.sh — shared library for my-git tools.
# Source this file from sibling scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$SCRIPT_DIR/my-git-core.inc.sh"

MY_GIT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/my-git"
MY_GIT_PROFILES_DIR="$MY_GIT_CONFIG_DIR/profiles"
MY_GIT_KEYS_DIR="$MY_GIT_CONFIG_DIR/keys"

# Keys treated as sensitive and subject to keyring migration.
MY_GIT_SENSITIVE_KEYS=("cargo_token" "pypi_token" "docker_token")

# Resolve a token field value.
#   secret-tool:service=S,profile=P,token=K -> secret-tool lookup result ("" on failure)
#   pass:*                                  -> returned verbatim (already secured)
#   anything else                           -> returned verbatim
resolve_token() {
    local val="$1"
    if [[ "$val" =~ ^secret-tool:service=([^,]+),profile=([^,]+),token=([^,]+)$ ]]; then
        local service="${BASH_REMATCH[1]}"
        local profile="${BASH_REMATCH[2]}"
        local token_name="${BASH_REMATCH[3]}"
        secret-tool lookup service "$service" profile "$profile" token "$token_name" 2>/dev/null || echo ""
    else
        echo "$val"
    fi
}

# Extract a field value from a profile file. Prints "" when absent.
#   $1 = profile file path, $2 = key name
parse_field() {
    local file="$1"
    local target_key="$2"
    local value=""

    while IFS='=' read -r key val || [ -n "$key" ]; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${key// /}" ]] && continue
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
            val="${BASH_REMATCH[1]}"
        fi
        if [ "$key" = "$target_key" ]; then
            value="$val"
            break
        fi
    done <"$file"

    echo "$value"
}

# Extract a field value from a [section] of a profile file. Prints "" when
# the section or the key is absent.
#   $1 = profile file path, $2 = section name without brackets
#        (e.g. "docker:ghcr.io"), $3 = key name
parse_section_field() {
    local file="$1"
    local target_section="$2"
    local target_key="$3"
    local value=""
    local in_section=0
    local line key val

    while IFS= read -r line || [ -n "$line" ]; do
        # trim leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            if [ "$in_section" -eq 1 ]; then
                break
            fi
            if [ "${BASH_REMATCH[1]}" = "$target_section" ]; then
                in_section=1
            fi
            continue
        fi

        [ "$in_section" -eq 0 ] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        [[ "$line" != *"="* ]] && continue

        key="${line%%=*}"
        val="${line#*=}"
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
            val="${BASH_REMATCH[1]}"
        fi
        if [ "$key" = "$target_key" ]; then
            value="$val"
            break
        fi
    done <"$file"

    echo "$value"
}

# List registry names of all [docker:<registry>] sections in a profile file,
# one per line.
#   $1 = profile file path
list_docker_sections() {
    local file="$1"
    local line

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ "$line" =~ ^\[docker:(.+)\]$ ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done <"$file"
}

# Find the profile name matching an email address. Prints "" when no match.
#   $1 = email
find_profile_by_email() {
    local email="$1"
    local profile_file prof_email

    for profile_file in "$MY_GIT_PROFILES_DIR"/*; do
        [ ! -f "$profile_file" ] && continue
        prof_email=$(parse_field "$profile_file" "email")
        if [ "$prof_email" = "$email" ]; then
            basename "$profile_file"
            return 0
        fi
    done

    echo ""
    return 1
}

# Resolve an SSH key reference to an absolute path.
#   $1 = raw value: absolute, ~-prefixed, name in KEYS_DIR, or name in ~/.ssh
resolve_key_path() {
    local raw_path="$1"
    if [ -z "$raw_path" ]; then
        echo ""
    elif [[ "$raw_path" = /* ]]; then
        echo "$raw_path"
    elif [[ "$raw_path" == "~"* ]]; then
        echo "${raw_path/#\~/$HOME}"
    elif [ -f "$MY_GIT_KEYS_DIR/$raw_path" ]; then
        echo "$MY_GIT_KEYS_DIR/$raw_path"
    else
        echo "$HOME/.ssh/$raw_path"
    fi
}

# Rewrite sensitive token fields of a profile file into secret-tool references,
# migrating plaintext values into the system keyring. Preserves comments, blank
# lines, and field order. Requires secret-tool on PATH.
#   $1 = profile file path, $2 = profile name
# Prints status lines; exit code is 0 always (migration count kept in output).
protect_profile_tokens() {
    local profile_file="$1"
    local profile="$2"

    local tmp_file
    tmp_file=$(mktemp)
    local key val is_sensitive s_key token_attr section_registry
    local current_section=""

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*\[(.*)\][[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            echo "$line" >>"$tmp_file"
        elif [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"

            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"
            if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
                val="${BASH_REMATCH[1]}"
            fi

            is_sensitive=false
            token_attr="$key"
            for s_key in "${MY_GIT_SENSITIVE_KEYS[@]}"; do
                if [ "$key" = "$s_key" ] && [ -z "$current_section" ]; then
                    is_sensitive=true
                    break
                fi
            done
            if [ "$is_sensitive" = false ] && [ "$key" = "token" ] &&
                [[ "$current_section" == docker:* ]]; then
                is_sensitive=true
                section_registry="${current_section#docker:}"
                token_attr="docker_${section_registry//./_}"
            fi

            if [ "$is_sensitive" = true ] && [ -n "$val" ]; then
                if [[ "$val" =~ ^secret-tool: ]] || [[ "$val" =~ ^pass: ]]; then
                    echo "  [OK] $key: already secured via external vault reference"
                    echo "$line" >>"$tmp_file"
                else
                    printf "%s" "$val" | secret-tool store \
                        --label="my-git $token_attr for $profile" \
                        service my-git \
                        profile "$profile" \
                        token "$token_attr"

                    echo "$key = secret-tool:service=my-git,profile=$profile,token=$token_attr" >>"$tmp_file"
                    echo "  [SECURED] $key: moved plaintext token to system keyring"
                    continue
                fi
            else
                echo "$line" >>"$tmp_file"
            fi
        else
            echo "$line" >>"$tmp_file"
        fi
    done <"$profile_file"

    mv "$tmp_file" "$profile_file"
    chmod 600 "$profile_file"
}
