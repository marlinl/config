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

- `zsh/`: shared and platform-specific Zsh configuration, plus the internal rendering engine.
- `zsh-plugin/`: custom Zsh plugins.
- `ghostty/`: Ghostty configuration.

## Machine environment

Keep machine-specific environment variables in `~/.config/.env`. This file is
explicitly ignored by Git. It is a configuration file, not a Shell script:

```dotenv
NO_PROXY="127.0.0.1"
```

`zsh/before.zshrc` parses single-line `KEY=value` assignments into environment
variables before loading plugins and the remaining shared Zsh blocks. Later
assignments override these machine defaults. Whitespace around `=`, empty
values, single/double quotes, blank lines, and comments outside quotes are
supported. Double-quoted `\n` and `\r` represent line breaks. Variables and
command substitutions remain literal text; the file is never executed and
does not use `export` statements. Missing files and invalid assignment lines
are skipped. Edit this file directly for machine-specific values; `myconfig` does
not embed it in the generated `~/.zshrc` or synchronize it into the repository.

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

`setup.sh` installs platform packages, links `~/.zprofile` and `~/.vimrc`, generates
`~/.zshrc`, and changes the login shell to zsh when needed. On a later normal run
it checks packages, links, generated Zsh configuration, Git identity, and login
shell first; when all checks pass, it skips installation. It does not install
or start background services.

`zsh-plugin/myconfig.zsh` is loaded by the existing plugin loader. In an already
open shell, load it once with `source ~/.config/zsh-plugin/myconfig.zsh`.

```zsh
myconfig render                          # Generate ~/.zshrc from the three source blocks
myconfig render --output /tmp/zshrc-preview  # Generate a preview file
myconfig check                           # Validate and report differences without writing
myconfig sync                            # Validate, write back, commit, and push
myconfig sync -m "Update Zsh prompt"       # Supply a commit message
```

`render` combines `before.zshrc`, the current platform's `zshrc.macos` or
`zshrc.debian`, and `after.zshrc`. It asks before replacing an existing output
and preserves that file or symlink in a timestamped backup. Rendering does not
reload the current shell.

`check` validates Zsh syntax, exactly three fixed blocks in order, and absence
of content outside their boundaries. It reports differing source paths without
printing their contents. Differences are valid and return success; invalid
configuration returns a nonzero status. It does not change source files, the
Git index, persistent status, or logs. A pending write-back transaction is
reported instead of being recovered by a read-only check.

`sync` uses the same validation on a snapshot before writing blocks back through
a recoverable transaction. It commits changes only to the current platform's
three source blocks, preserving other staged and unstaged files. Existing staged
changes in those blocks must be resolved first. The current branch must have an
upstream; unpushed commits touching other files are refused. It pushes to that
upstream without pulling, rebasing, or forcing. A failed commit leaves the
write-back available to retry; a failed push retains the local commit, and a
later `sync` retries the push even when no new content changed.

There is no watcher or daemon. Editing `.zshrc` requires `myconfig sync` to save
and publish it; editing source blocks requires `myconfig render` to regenerate
it. Plugin files and `.env` are not part of the three-block commit scope.

If an older installation enabled weave, disable its existing service once
before using these commands. On macOS, run
`launchctl bootout gui/$(id -u)/com.marlinl.zshrc-weave` and move
`~/Library/LaunchAgents/com.marlinl.zshrc-weave.plist` to a backup filename. On
Debian, run `systemctl --user disable --now zshrc-weave.service` and move
`~/.config/systemd/user/zshrc-weave.service` to a backup filename, then run
`systemctl --user daemon-reload`. Normal setup no longer manages these legacy
service files.
