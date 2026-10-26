#!/usr/bin/env bash
# Autocompletion script for my-git CLI tools

_my_git_get_profiles() {
    local profiles_dir="${XDG_CONFIG_HOME:-$HOME/.config}/my-git/profiles"
    if [ -d "$profiles_dir" ]; then
        command ls -1 "$profiles_dir" 2>/dev/null
    fi
}

# Completion for git-clone
_my_git_clone_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    # First argument is always a profile name
    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$(_my_git_get_profiles)" -- "$cur") )
        return 0
    fi
}
complete -F _my_git_clone_complete git-clone

# Completion for git-init
_my_git_init_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$(_my_git_get_profiles)" -- "$cur") )
    elif [ "$COMP_CWORD" -eq 2 ]; then
        # Second optional argument is a target directory
        COMPREPLY=( $(compgen -d -- "$cur") )
    fi
}
complete -F _my_git_init_complete git-init

# Completion for git-set-profile
_my_git_set_profile_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$(_my_git_get_profiles)" -- "$cur") )
    fi
}
complete -F _my_git_set_profile_complete git-set-profile

# Completion for git-export-profile
_my_git_export_profile_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [[ "$prev" == "-o" || "$prev" == "--output" ]]; then
        COMPREPLY=( $(compgen -f -- "$cur") )
        return 0
    fi

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "--all -a --output -o --help -h" -- "$cur") )
    else
        COMPREPLY=( $(compgen -W "$(_my_git_get_profiles)" -- "$cur") )
    fi
}
complete -F _my_git_export_profile_complete git-export-profile

# Completion for git-import-profile
_my_git_import_profile_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    if [ "$COMP_CWORD" -eq 1 ]; then
        # Suggest .tar.enc files first, otherwise fallback to any file
        local archives
        archives=$(compgen -f -X '!*.tar.enc' -- "$cur")
        if [ -n "$archives" ]; then
            COMPREPLY=( $archives )
        else
            COMPREPLY=( $(compgen -f -- "$cur") )
        fi
        return 0
    fi

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "--list -l --all -a --help -h" -- "$cur") )
    fi
}
complete -F _my_git_import_profile_complete git-import-profile

# Completion for install-my-git
_install_my_git_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "--force -f --help -h" -- "$cur") )
    else
        COMPREPLY=( $(compgen -d -- "$cur") )
    fi
}
complete -F _install_my_git_complete install-my-git

