_git_source_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local cmd="${COMP_WORDS[0]}"

    # Use the actual command typed, fallback to ROOT_DIR/git-source.sh
    local src="$ROOT_DIR/git-source.sh"
    if which "$cmd" &>/dev/null; then
        src="$(which "$cmd")"
    fi

    # Extract flags dynamically
    local opts
    if opts=$("$src" -h 2>/dev/null | grep -oE '(-{1,2}[a-zA-Z0-9_-]+)'); then
        :
    else
        # fallback hardcoded flags
        opts="-b --list-branches -v --verbose --debug -h --help --generate-mxe-makefile --generate-mxe-testfile"
    fi

    COMPREPLY=( $(compgen -W "${opts}" -- "$cur") )
}

complete -F _git_source_completions ./git-source.sh
complete -F _git_source_completions gsrc
