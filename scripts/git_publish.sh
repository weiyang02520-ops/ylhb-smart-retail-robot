#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '用法: %s "提交说明"\n' "$0"
}

die() {
  printf '错误: %s\n' "$*" >&2
  exit 1
}

confirm() {
  local answer
  printf '\n确认执行 git add -A、commit、同步远程最新提交并推送吗？[y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

fetch_remote_branch() {
  if git fetch origin "$branch"; then
    return 0
  fi

  printf '\n普通 fetch 失败，正在使用 HTTP/1.1 兼容模式重试...\n' >&2
  git -c http.version=HTTP/1.1 fetch origin "$branch"
}

rebase_remote_branch() {
  if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    printf '\n远程 origin/%s 尚不存在，跳过 rebase。\n' "$branch"
    return 0
  fi

  printf '\n正在同步远程最新提交: git rebase origin/%s\n' "$branch"
  if git rebase "origin/$branch"; then
    return 0
  fi

  printf '\n本地提交已创建，但同步远程时发生冲突。\n' >&2
  printf '请解决冲突后执行:\n' >&2
  printf '  git add <文件>\n' >&2
  printf '  git rebase --continue\n' >&2
  printf '然后重试 ./scripts/git_publish.sh 或手动执行:\n' >&2
  printf '  git push origin %s\n' "$branch" >&2
  printf '如果需要放弃本次同步，请执行:\n' >&2
  printf '  git rebase --abort\n' >&2
  exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "当前目录不在 git 仓库中"

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

branch="$(git branch --show-current)"
[ -n "$branch" ] || die "当前处于 detached HEAD 状态，脚本不支持直接发布"

remote_url="$(git remote get-url origin 2>/dev/null || true)"
[ -n "$remote_url" ] || die "未配置远程仓库 origin"

message="${1:-}"
if [ -z "$message" ]; then
  printf '提交说明: '
  read -r message
fi
[ -n "$message" ] || die "必须提供提交说明"

if [ -z "$(git status --porcelain)" ]; then
  printf '没有未提交的工作区改动，将检查是否存在待推送的本地提交。\n'
  printf '仓库:   %s\n' "$repo_root"
  printf '分支:   %s\n' "$branch"
  printf '远程:   %s\n' "$remote_url"

  printf '\n正在获取远程 origin/%s 的最新提交...\n' "$branch"
  if ! fetch_remote_branch; then
    printf '\n获取远程最新提交失败。\n' >&2
    printf '可稍后重试以下命令:\n' >&2
    printf '  git fetch origin %s\n' "$branch" >&2
    printf '  git -c http.version=HTTP/1.1 fetch origin %s\n' "$branch" >&2
    exit 1
  fi

  rebase_remote_branch

  if [ "$(git rev-list --count "origin/$branch"..HEAD 2>/dev/null || printf '1')" = "0" ]; then
    printf '没有需要发布的改动。\n'
    exit 0
  fi

  if ! git push origin "$branch"; then
    printf '\n普通推送失败，正在使用 HTTP/1.1 兼容模式重试...\n' >&2
    if ! git -c http.version=HTTP/1.1 push origin "$branch"; then
      printf '\n远程推送失败。\n' >&2
      printf '可稍后重试以下命令:\n' >&2
      printf '  git push origin %s\n' "$branch" >&2
      printf '  git -c http.version=HTTP/1.1 push origin %s\n' "$branch" >&2
      exit 1
    fi
  fi

  printf '\n已发布到 origin/%s。\n' "$branch"
  exit 0
fi

printf '仓库:   %s\n' "$repo_root"
printf '分支:   %s\n' "$branch"
printf '远程:   %s\n' "$remote_url"
printf '\n工作区状态:\n'
git status --short

printf '\n改动摘要:\n'
git diff --stat
git diff --cached --stat
untracked_files="$(git ls-files --others --exclude-standard)"
if [ -n "$untracked_files" ]; then
  printf '\n未跟踪文件（将随 git add -A 提交）:\n'
  while IFS= read -r path; do
    printf '  %s\n' "$path"
  done <<< "$untracked_files"
fi

if ! confirm; then
  printf '已取消。脚本没有暂存、提交或推送任何改动。\n'
  exit 0
fi

git add -A

if git diff --cached --quiet; then
  printf '执行 git add -A 后没有可提交的暂存改动。\n'
  exit 0
fi

git commit -m "$message"

printf '\n正在获取远程 origin/%s 的最新提交...\n' "$branch"
if ! fetch_remote_branch; then
  printf '\n本地提交已创建，但获取远程最新提交失败。\n' >&2
  printf '可稍后重试以下命令:\n' >&2
  printf '  git fetch origin %s\n' "$branch" >&2
  printf '  git -c http.version=HTTP/1.1 fetch origin %s\n' "$branch" >&2
  printf '然后重试 ./scripts/git_publish.sh 或手动 rebase 后 push。\n' >&2
  exit 1
fi

rebase_remote_branch

if ! git push origin "$branch"; then
  printf '\n普通推送失败，正在使用 HTTP/1.1 兼容模式重试...\n' >&2
  if ! git -c http.version=HTTP/1.1 push origin "$branch"; then
    printf '\n本地提交已创建，但远程推送失败。\n' >&2
    printf '可稍后重试以下命令:\n' >&2
    printf '  git push origin %s\n' "$branch" >&2
    printf '  git -c http.version=HTTP/1.1 push origin %s\n' "$branch" >&2
    exit 1
  fi
fi

printf '\n已发布到 origin/%s。\n' "$branch"
