echo "Keep simple. Keep stupid. Keep hungry."

# 补全
autoload -Uz compinit && compinit
# 自动加载所有插件
for f in ~/.config/zsh-plugin/*.zsh(N); do source "$f"; done
