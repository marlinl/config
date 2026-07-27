# 快速同步 ~/.config 到远端
gconf() {
    # 记录当前所在的目录
    local current_dir=$(pwd)
    
    # 切换到 .config 目录
    cd ~/.config || { echo "❌ 找不到 ~/.config 目录"; return 1; }

    # 安全检查：确认这里真的是个 Git 仓库
    if [ ! -d ".git" ]; then
        echo "⚠️ 警告：~/.config 不是一个 Git 仓库 (找不到 .git 目录)！"
        cd "$current_dir"
        return 1
    fi

    echo "🔄 开始检测 ~/.config 的变更..."

    # 添加所有变动
    if ! git add .; then
        echo "❌ 暂存失败，未提交或推送任何变更。"
        cd "$current_dir"
        return 1
    fi

    # 检查是否有实际的修改需要提交
    if git diff --staged --quiet; then
        echo "✅ 没有发现需要提交的修改，已经是最新状态。"
    else
        # 如果你敲命令时带了参数，就用你的参数当 commit 信息
        # 如果没带参数，默认使用当前时间戳
        local commit_msg="${1:-Auto commit: $(date '+%Y-%m-%d %H:%M:%S')}"
        
        if ! git commit -m "$commit_msg"; then
            echo "❌ 提交失败，未推送任何变更。"
            cd "$current_dir"
            return 1
        fi
        
        # 推送到默认的主分支 master
        if ! git push origin master; then
            echo "❌ 推送失败，本地提交仍保留。"
            cd "$current_dir"
            return 1
        fi
        
        echo "🚀 同步远端完成！"
    fi

    # 完事后，自动退回你之前所在的目录，不打断你的工作流
    cd "$current_dir"
}
