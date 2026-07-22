# 设置代理
set_proxy() {
  # 检查是否传入了参数
  if [[ -z "$1" ]]; then
    echo "❌ 请提供代理地址！"
    echo "用法: set_proxy <proxy_url>"
    return 1
  fi

  local proxy_url="$1"

  # 设置大小写环境变量，提高兼容性
  export http_proxy="$proxy_url"
  export HTTP_PROXY="$proxy_url"
  export https_proxy="$proxy_url"
  export HTTPS_PROXY="$proxy_url"
  export all_proxy="$proxy_url"
  export ALL_PROXY="$proxy_url"

  echo "✅ Terminal proxy is ON. [Proxy: $proxy_url]"
}

# 取消代理
unset_proxy() {
  # 清除所有相关的环境变量
  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY
  echo "🚫 Terminal proxy is OFF."
}
