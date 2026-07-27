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

## Workflow

`setup.sh` installs platform packages, links `~/.zprofile`, generates `~/.zshrc`, and installs the current platform's weave service. Weave combines the fixed Zsh blocks and writes edits from `~/.zshrc` back to their source blocks.
