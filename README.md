# Config

Personal dotfiles for macOS and Debian.

## Install

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/MarlinL/config/master/setup.sh)"
```

The repository is cloned to `~/.config` through SSH when that directory is missing or empty. GitHub SSH access is required. A non-empty `~/.config` is reused only when its `origin` matches this repository; otherwise setup refuses to touch it.

## Existing checkout

```bash
./setup.sh
```

## Dry run

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/MarlinL/config/master/setup.sh)" --dry-run
```

## Zsh render test

```bash
./setup.sh --test /tmp/zshrc-preview
```

## Layout

- `zsh/`: shared and platform-specific Zsh configuration, plus weave.
- `zsh-plugin/`: custom Zsh plugins.
- `ghostty/`: Ghostty configuration.

## Codex accounts

`zsh-plugin/codex-auth.zsh` is loaded by the shared Zsh startup block. It stores
account files only in `~/.config/codex/` and switches `CODEX_HOME/auth.json`
(`~/.codex/auth.json` by default) to a symlink to the selected file:

```zsh
codex-auth -l            # Show the current account and available files
codex-auth -p marlinl    # Select an existing ~/.config/codex/marlinl.auth.json
codex-auth --new aab     # Select a new account path for the next login
codex-auth -d aab        # Delete the named account file
codex-auth --help         # Show all commands and their behavior
```

Sign in to Codex after `--new`; the login creates the account file through the
symlink. Switching accounts or deleting the active account stops matching
`codex app-server` processes owned by the current user; a Codex client starts
a new one when needed. Restart a separately launched app-server yourself. If an
existing `auth.json` is a regular file or points outside the account directory,
the command asks before moving that entry to a timestamped backup. On first
selection, `-p` moves a same-named `CODEX_HOME/*.auth.json` file into
`~/.config/codex/` with mode `600` if the target file does not exist. Set
`cli_auth_credentials_store = "file"` in `CODEX_HOME/config.toml`; see the
[Codex authentication documentation](https://learn.chatgpt.com/docs/auth).

## Workflow

`setup.sh` installs platform packages, links `~/.zprofile`, generates `~/.zshrc`, installs and verifies the current platform's weave service, and changes the login shell to zsh when needed. On a later normal run it checks the installed packages, links, generated Zsh configuration, service, Git identity, and login shell first; when all checks pass, it skips installation. Weave combines the fixed Zsh blocks and writes edits from `~/.zshrc` back to their source blocks through a recoverable transaction.
