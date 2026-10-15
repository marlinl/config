# Repository Guide

## Scope and ownership

This is a personal, cross-platform dotfiles repository for macOS and Debian. It is not an application service.

- `setup.sh` is the only bootstrap entry point. When executed outside a checkout, it clones `git@github.com:marlinl/config.git` over SSH into a missing or empty `~/.config` and then runs the cloned script. It may reuse a non-empty target only when that target's `origin` matches the configured repository URL; otherwise it must refuse it. In normal mode it may install packages, change global Git settings, create `~/.zprofile` and `~/.vimrc` links, generate `~/.zshrc`, and change the login shell to zsh when needed. A later normal run must check packages, links, generated Zsh configuration, Git identity, and login shell first, and skip installation when all checks pass.
- `./setup.sh --dry-run` and the remote `bash -c` invocation with `--dry-run` must print their plans without cloning, installing packages, changing files, changing Git configuration, enabling services, or changing the login shell.
- `./setup.sh --test <directory>` is the safe rendering path. It writes `<directory>/.zshrc` plus only the fixed, ignored `~/.config/zsh/weave/.status` file; it must not install packages, create links below `~`, change Git configuration, enable services, or change the login shell.
- The user owns all pre-existing modifications and untracked files. Start with `git status --short`; do not modify, stage, move, or delete unrelated work.
- `vcd/` is local container-development configuration. `vcd/plugins/superpowers/` is an independent plugin copy: do not bulk format, upgrade dependencies, or treat it as root configuration unless the task explicitly targets it.

## Zsh layout

The generated `~/.zshrc` has exactly three visible blocks, in this fixed order:

1. `zsh/before.zshrc`
2. `zsh/zshrc.macos` or `zsh/zshrc.debian`
3. `zsh/after.zshrc`

- **Mandatory: `.env` is configuration data, never a Shell script.** Parse
  `~/.config/.env` as single-line `KEY=value` assignments. Support whitespace
  around `=`, empty values, single/double quotes, blank lines, and `#` comments
  outside quotes. Double-quoted `\n` and `\r` represent line breaks. Values are
  literal: do not expand variables, command substitutions, or Shell expressions;
  do not interpret an `export` prefix or execute commands. Never load this file
  with `source`, `.`, or `eval`, and never use `set -a`/`allexport` to load it.
  Do not add Shell execution, option-preservation branches, new configuration
  layers, or parser dependencies without explicit user authorization.
- `zsh/before.zshrc` reads a readable `~/.config/.env` at the start of the first
  generated block and assigns parsed values to environment variables. Missing
  files and invalid assignment lines are skipped. This file contains machine
  defaults and must remain explicitly ignored by Git (`/.env`); later plugin
  and Zsh block assignments take precedence. Never stage or commit it, and never
  inline machine-specific values into the generated blocks or tracked files.
- Keep the block bodies faithful to their source configuration. Do not add generated headers, explanatory comments, hidden configuration variables, extra blocks, or platform-condition logic unless requested.
- `myconfig` uses the three visible `BEGIN`/`END` markers only as fixed boundaries. It runs on demand and exits; do not add watchers, daemons, LaunchAgents, or systemd services.
- `zsh-plugin/` remains a root-level collection of custom plugins. It is loaded by `zsh/before.zshrc` and is not a generated block or part of the three-block sync commit scope.
- `zsh/weave/zshrc-weave.zsh` is the internal renderer, checker, and transactional fixed-block writer used by `myconfig` and setup. Its only persistent log is error output at `~/.config/logs/zshrc-weave.error.log`; do not add trace, info, warning, or event logs.
- A changed three-block write-back must first activate the fixed, ignored `zsh/weave/.sync-transaction` directory and then roll all source blocks forward from it. Normal `render` and `sync` must recover a pending transaction before continuing; `check`, `myconfig render --print`, and `setup.sh --test` must instead refuse a pending transaction without changing source blocks. Temporary/completed transaction directories are ignored and may be cleaned only while holding the `.status` advisory lock.
- Setup must not install, enable, or verify weave services. Existing legacy service registrations require a one-time disable and backup migration; do not silently remove user service files.
- Do not remove the legacy root-level Zsh files or rename user-defined plugin files unless the task explicitly authorizes that migration. A user-requested rename of a plugin's primary public command also authorizes renaming its owning Zsh file to match.

## Zsh plugin responsibilities

- When adding or renaming a primary plugin command, its owning file must be `zsh-plugin/<command>.zsh`; for example, `mycodex` belongs in `zsh-plugin/mycodex.zsh`. Update the function name, command dispatch/help, filename, loader or source references, README, and AGENTS.md together. Do not leave a duplicate file under the old command name unless the user explicitly requests compatibility.

- `zsh-plugin/myconfig.zsh` provides `myconfig render [--print | --output FILE]`, `myconfig check`, and `myconfig sync [-m MESSAGE]`. Default render confirms and backs up an existing `~/.zshrc`, regenerates it, and sources it in the calling shell only after success. `--print` emits validated configuration only to stdout without persistent writes or reloading; `--output FILE` writes the specified file without reloading. Cancellation or failure returns nonzero and must not reload the shell. Check validates syntax and the fixed block layout and reports source differences without changing source files, Git state, persistent status, or logs. Sync validates before write-back, commits only the current platform's three source blocks, and pushes to the current branch's configured upstream. Preserve unrelated staged/unstaged work; refuse pre-staged block changes and outgoing commits touching other paths. Do not pull, rebase, or force-push. Retry failed pushes even when the next write-back has no changes.

- `zsh-plugin/var.zsh` provides `var NAME VALUE`, `var -g`, and `var -l` variable assignment modes.
- `zsh-plugin/jenv.zsh` is the repository's Java environment manager. Its public commands are `jenv list`, `add`, `rm`, `set`, and `info`; preserve their names and behavior.
- `zsh-plugin/git-info.zsh` provides `git_branch()` for the prompt.
- `zsh-plugin/proxy.zsh` owns the terminal proxy helpers.
- `zsh-plugin/gconf.zsh` runs `git add .` and pushes `origin master`. Do not use it in automated work or as a substitute for explicit staging and user-approved commits.
- `zsh-plugin/mycodex.zsh` provides `mycodex info`, `set`, `new`, `delete`, `codex [args] -p <account>`, and `--help`. It manages ignored `codex/<account>.auth.json` files and switches the original `CODEX_HOME/auth.json` symlink only for account-management commands. `codex` consumes one account `-p` before `--`, forwards all other arguments, and uses native `codex --no-daemon` with file credentials; native config profiles use `--profile`. Each account has a real `codex/<account>/` home with its own auth symlink. Configuration, .env, plugins, instructions, sessions/history, and other shared data link to the original Codex home; displayed paths may differ. SQLite storage uses the inherited `CODEX_SQLITE_HOME` or original home, subject to native `sqlite_home` precedence; never link individual database/sidecar files. Keep daemon, IPC, temporary, and process-manager state account-local. Never overwrite conflicting runtime entries or delete previous account records. There is no Python bridge or extra Python package dependency. Preserve cwd and ordinary environment; clear only authentication environment overrides for the child. Never source .env, inspect/log credentials, put secrets in argv, switch the default auth during launch, or stop unrelated processes. An explicit account switch retains the existing matching app-server restart behavior.

## Platform boundaries

- macOS uses Homebrew, `/opt/homebrew/share/zsh-*` plugin paths, and Homebrew `libpq` for `psql` and `pg_dump`. OrbStack initialization belongs in `zsh/zprofile`.
- Debian uses `apt-get`, `/usr/share/zsh-*` plugin paths, and system PostgreSQL client tools. Ghostty, VS Code, and Chrome are not installed by the Debian package list.
- `macos.txt` and `debian.txt` are the root-level package lists read by setup. Each non-empty Debian line is one package name. A macOS formula line is one package name, while a cask line must be written as `package --cask`; setup passes the list to Homebrew without guessing the package type.
- Put platform-only behavior in the matching `zsh/zshrc.<platform>` file. Put shared prompt and shell behavior in the fixed before/after blocks. Keep Ghostty and Fish configuration in `ghostty/` and `fish/` respectively.

## Safe changes

1. Identify the actual load path and configuration owner before editing. Do not make a mirrored macOS/Debian change merely because file names look similar.
2. Explain before running a command that affects the user home directory, installed packages, Docker, global Git settings, or user services. Do not run normal `setup.sh` as a routine test.
3. Before replacing an existing link or generated file, inspect its type and target. Preserve user data with an explicit confirmation and backup; never silently overwrite a regular file.
4. Keep startup files lightweight and idempotent. Do not change existing aliases, commands, function names, routes, fields, or method signatures without explicit authorization.
5. When changing bootstrap behavior, links, supported platforms, or package dependencies, update `README.md` and this `AGENTS.md` in the same change.

## Secrets and version control

- This is a whitelist repository. `.gitignore` ignores everything by default and permits only `.gitignore`, `.vimrc`, `AGENTS.md`, `README.md`, `setup.sh`, `macos.txt`, `debian.txt`, `zsh/`, `zsh-plugin/`, and `ghostty/`. Do not widen that set without explicit user approval.
- After the initial `init` commit, use ordinary additive commits for later changes. Amend, squash, or rewrite history only when the user explicitly requests it.
- Never add, repeat, stage, commit, log, or copy access tokens, private keys, cloud credentials, proxy credentials, or other real secrets.
- Treat `glm-acp-agent/`, `vcd/`, and comparable machine-local state as sensitive. `fish/`, `uv/`, `vcd/`, and `glm-acp-agent/` are local-only and must remain ignored. Verify ignore behavior with `git check-ignore` when changing related files.
- `codex/` and all `auth.json` account files are local-only credentials and must remain ignored.
- If a plaintext credential already exists, report its file scope without reproducing the value and recommend rotation. Do not duplicate it into a new configuration path without explicit user direction.
- `zshrc-weave` status is pinned to `~/.config/zsh/weave/.status` and error logs to `~/.config/logs/`. Both are ignored from version control. Do not use `git add .`; stage only task files and commit or push only with explicit user approval. An explicit user invocation of `myconfig sync` authorizes its documented three-block commit and push; implementation tests must use disposable repositories and local remotes.

## Verification

- After changing `setup.sh`, run `bash -n setup.sh` and exercise `./setup.sh --test <temporary-directory>`. Never use normal setup as routine verification.
- After changing Zsh files or the synchronizer, run `zsh -n` on every modified file and on a generated test `.zshrc`.
- For rendering/write-back changes, verify exactly three fixed blocks and a no-op internal `sync` reporting `changed=0`. Verify `check` rejects invalid syntax/boundaries without persistent writes. Test `myconfig sync` against a disposable local remote, including commit scope, staged-work preservation, and failed-push retry.
- For a non-empty test directory, verify `n` leaves it untouched and `y` replaces only the generated `.zshrc` while preserving other files.
- Run `git diff --check` before handoff and state what high-impact operations were intentionally not executed.
