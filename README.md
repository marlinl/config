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
are skipped. Edit this file directly for machine-specific values; weave does
not embed it in the generated `~/.zshrc` or synchronize it into the repository.

## Codex accounts

`zsh-plugin/mycodex.zsh` is loaded by the shared Zsh startup block. It stores
account files only in `~/.config/codex/` and switches `CODEX_HOME/auth.json`
(`~/.codex/auth.json` by default) to a symlink to the selected file:

```zsh
mycodex info             # Show accounts and runtime directory links
mycodex set marlinl      # Select an existing ~/.config/codex/marlinl.auth.json
mycodex new aab          # Select a new account path for the next login
mycodex delete aab       # Delete the named account file
mycodex codex -p marlinl # Run an independent CLI in this terminal as this account
mycodex codex resume <id> -p marlinl # Resume a session with this account
mycodex --help           # Show all commands and their behavior
```

`info` lists accounts in `~/.config/codex/` and the actual entries in each
account's runtime directory: symlink targets, missing targets, and local files
or directories. Accounts without a runtime directory are marked as uninitialized.
It also shows the shared home used for launches and the `CODEX_SQLITE_HOME`
directory, with a reminder that `sqlite_home` configuration takes precedence.
The command reads paths and links without opening credential files or creating
runtime directories.

Sign in to Codex after `new`; the login creates the account file through the
symlink. Switching accounts or deleting the active account stops matching
`codex app-server` processes owned by the current user; a Codex client starts
a new one when needed. Restart a separately launched app-server yourself. If an
existing `auth.json` is a regular file or points outside the account directory,
the command asks before moving that entry to a timestamped backup. On first
selection, `set` moves a same-named `CODEX_HOME/*.auth.json` file into
`~/.config/codex/` with mode `600` if the target file does not exist. Set
`cli_auth_credentials_store = "file"` in `CODEX_HOME/config.toml`; see the
[Codex authentication documentation](https://learn.chatgpt.com/docs/auth).

To use multiple accounts concurrently, run `mycodex codex -p marlinl` in one
terminal tab and `mycodex codex -p aab` in another. An existing ordinary file at
`~/.config/codex/<account>.auth.json` is required. The wrapper consumes exactly one
`-p <account>` before `--`, anywhere among the Codex arguments, and forwards the
remaining arguments unchanged. Use `--profile <name>` for Codex's own config
profile. For example:

```zsh
mycodex codex resume <id> -p marlinl
mycodex codex exec -p marlinl "Explain this repository"
mycodex codex -p marlinl --profile work
mycodex codex -p marlinl -- "A prompt containing -p literally"
```

The native CLI runs with `--no-daemon` and file-based credentials, using the real
directory `~/.config/codex/<account>/` as its `CODEX_HOME`. Its `auth.json` links to
the selected account file, including native credential refresh writes. Other
options and commands follow native Codex behavior; `agents` and `--remote` are
incompatible with `--no-daemon`. Explicitly invoking `app-server` still starts
the native server command requested by the user.

Configuration, `.env`, AGENTS instructions, profiles, plugins, skills, sessions,
archived sessions, history, and other existing data entries link back to the
original Codex home (`CODEX_HOME` before invocation, or `~/.codex`). Shared data
directories are created if missing. Codex reads `.env` itself; the plugin never
sources it. The current working directory and other environment values are
inherited; `OPENAI_API_KEY`, `CODEX_API_KEY`, and `CODEX_ACCESS_TOKEN` are cleared
for this invocation so they cannot override the selected account. The original
`auth.json` is not switched or rewritten. Paths displayed by `/status` can use
the account directory even when they resolve to the same shared files.

SQLite databases and their sidecars are not individually linked. The child
inherits `CODEX_SQLITE_HOME`, or defaults it to the original Codex home; native
`sqlite_home` configuration still takes precedence. App-server runtime state,
IPC, temporary files, and process-manager state remain account-local. Existing
shared entries are checked at every launch; a conflicting ordinary file or
unexpected link stops the launch without overwriting it. Newly introduced Codex
storage paths may require updating this layout, and a native command that
replaces a file symlink rather than following it will be reported as a conflict
on the next launch.

Exit that account's CLI sessions before deleting its account file. Deleting an
account leaves its home directory and session records in place.

## Workflow

`setup.sh` installs platform packages, links `~/.zprofile`, generates `~/.zshrc`, installs and verifies the current platform's weave service, and changes the login shell to zsh when needed. On a later normal run it checks the installed packages, links, generated Zsh configuration, service, Git identity, and login shell first; when all checks pass, it skips installation. Weave combines the fixed Zsh blocks and writes edits from `~/.zshrc` back to their source blocks through a recoverable transaction.
