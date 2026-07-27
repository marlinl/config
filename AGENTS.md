# Repository Guide

## Scope and ownership

This is a personal, cross-platform dotfiles repository for macOS and Debian. It is not an application service.

- `setup.sh` is the only bootstrap entry point. When executed outside a checkout, it clones `git@github.com:marlinl/config.git` over SSH into a missing or empty `~/.config` and then runs the cloned script. It may reuse a non-empty target only when that target's `origin` matches the configured repository URL; otherwise it must refuse it. In normal mode it may install packages, change global Git settings, create `~/.zprofile` and `~/.vimrc` links, generate `~/.zshrc`, and enable the user-level `zshrc-weave` service.
- `./setup.sh --dry-run` and the remote `bash -c` invocation with `--dry-run` must print their plans without cloning, installing packages, changing files, changing Git configuration, or enabling services.
- `./setup.sh --test <directory>` is the safe rendering path. It writes `<directory>/.zshrc` plus only the fixed, ignored `~/.config/zsh/weave/.status` file; it must not install packages, create links below `~`, change Git configuration, or enable services.
- The user owns all pre-existing modifications and untracked files. Start with `git status --short`; do not modify, stage, move, or delete unrelated work.
- `vcd/` is local container-development configuration. `vcd/plugins/superpowers/` is an independent plugin copy: do not bulk format, upgrade dependencies, or treat it as root configuration unless the task explicitly targets it.

## Zsh layout

The generated `~/.zshrc` has exactly three visible blocks, in this fixed order:

1. `zsh/before.zshrc`
2. `zsh/zshrc.macos` or `zsh/zshrc.debian`
3. `zsh/after.zshrc`

- Keep the block bodies faithful to their source configuration. Do not add generated headers, explanatory comments, hidden configuration variables, extra blocks, or platform-condition logic unless requested.
- `zshrc-weave` uses the three visible `BEGIN`/`END` markers only as fixed boundaries. It watches only `~/.zshrc`; it does not watch, regenerate from, or react to changes under `zsh/` or `zsh-plugin/`.
- `zsh-plugin/` remains a root-level collection of custom plugins. It is loaded by `zsh/before.zshrc` and is not a weave block or a weave watch target.
- `zsh/weave/zshrc-weave.zsh` is the renderer, fixed-block synchronizer, daemon, and status command. Its only persistent log is error output at `~/.config/logs/zshrc-weave.error.log`; do not add trace, info, warning, or event logs.
- `zsh/weave/com.marlinl.zshrc-weave.plist` and `zsh/weave/zshrc-weave.service` are source templates for the macOS LaunchAgent and Debian systemd user service. They are not active until normal setup installs them. If the destination service file already exists, setup must ask before replacing it; declining keeps it untouched and skips service activation.
- Do not remove the legacy root-level Zsh files or rename user-defined plugin files unless the task explicitly authorizes that migration.

## Zsh plugin responsibilities

- `zsh-plugin/var.zsh` provides `var NAME VALUE`, `var -g`, and `var -l` variable assignment modes.
- `zsh-plugin/jenv.zsh` is the repository's Java environment manager. Its public commands are `jenv list`, `add`, `rm`, `set`, and `info`; preserve their names and behavior.
- `zsh-plugin/git-info.zsh` provides `git_branch()` for the prompt.
- `zsh-plugin/proxy.zsh` owns the terminal proxy helpers.
- `zsh-plugin/gconf.zsh` runs `git add .` and pushes `origin master`. Do not use it in automated work or as a substitute for explicit staging and user-approved commits.

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
- If a plaintext credential already exists, report its file scope without reproducing the value and recommend rotation. Do not duplicate it into a new configuration path without explicit user direction.
- `zshrc-weave` status is pinned to `~/.config/zsh/weave/.status` and error logs to `~/.config/logs/`. Both are ignored from version control. Do not use `git add .`; stage only task files and commit or push only with explicit user approval.

## Verification

- After changing `setup.sh`, run `bash -n setup.sh` and exercise `./setup.sh --test <temporary-directory>`. Never use normal setup as routine verification.
- After changing Zsh files or the synchronizer, run `zsh -n` on every modified file and on a generated test `.zshrc`.
- For weave changes, verify the generated output contains exactly the three fixed blocks and that a no-op `sync` reports `changed=0`.
- For a non-empty test directory, verify `n` leaves it untouched and `y` replaces only the generated `.zshrc` while preserving other files.
- Run `git diff --check` before handoff and state what high-impact operations were intentionally not executed.
