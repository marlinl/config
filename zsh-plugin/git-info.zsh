function git_branch() {
  if git rev-parse --is-inside-work-tree &> /dev/null; then
    echo "($(git rev-parse --abbrev-ref HEAD 2>/dev/null))"
  fi
}
