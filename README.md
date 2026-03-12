# Git Fetcher (`git-source` / `gsrc`)

`git-source` (or `gsrc` for short) is a command-line tool to fetch archives, latest tags, or branches from Git repositories hosted on **GitHub, GitLab, Bitbucket, or Googlesource**.  

It automates the retrieval of the latest version of a repository, saving archives locally, and supports listing branches.

---

## Features

- Fetch the **latest release tag** or **default branch** automatically.
- Download the repository as a `.tar.gz` archive.
- List all branches of a repository.
- Supports **GitHub**, **GitLab**, **Bitbucket**, and **Googlesource**.
- Optional **verbose** and **debug** output.
- Cross-platform: works anywhere Bash, `curl`, and `git` are available.

---

## Installation

You can run `git-source` directly from the repository without installing:

```bash
# From the project root
./git-source.sh <repo_url_or_owner/repo>

# Install to default prefix (/usr/local)
./install.sh

# Install to a custom prefix, e.g., local user directory
./install.sh --prefix $HOME/.local
```

This installation process will:

* Copy the wrapper `git-source` to `$PREFIX/bin/git-source`
* Create a symlink `gsrc` pointing to the same executable
* Install the man page to `$PREFIX/share/man/man1/git-source.1`
* Record all installed files in `$PREFIX/git-source.install-manifest`

Make sure your `PATH` includes the installation bin directory:

```bash
export PATH="$PREFIX/bin:$PATH"
```

And if you want man pages accessible:

```bash
export MANPATH="$PREFIX/share/man:$MANPATH"
```

## Enable Bash Autocomplete

`git-source` supports `Tab` completion for all flags and options. To enable it:

1. Source the completion script in your current shell:

```bash
source scripts/git-source-completion.sh
```

## Uninstallation

To remove installed files, use the `uninstall.sh` script with the same prefix you used for installation:

```bash
# Default prefix
./uninstall.sh

# Custom prefix
./uninstall.sh --prefix $HOME/.local
```

Note: Uninstallation does not affect other system-wide tools or Git repositories you manage. It only removes the installed wrapper, symlink, and `man` page.
