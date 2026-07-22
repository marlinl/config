
# 主题
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
autoload -U colors && colors

ZSH_HIGHLIGHT_STYLES[commandnotfound]='fg=red,bold'
ZSH_HIGHLIGHT_STYLES[command]='fg=green'
ZSH_HIGHLIGHT_STYLES[option]='fg=yellow'

setopt PROMPT_SUBST
PROMPT='%K{#006666}%F{#B2EBF2}%n%F{#FAFAFA}${OS_ICON} %F{#cccccc}%m%K{#003333}%F{#006666}%F{white} %~$(git_branch)%k%F{#003333}%f'
