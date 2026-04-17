#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

usage() {
  cat <<'EOF'
用法:
  ./version-utils.sh update_tag <目录名>
  ./version-utils.sh push_tag <目录名>

说明:
  update_tag 读取 <目录名>/version.txt，将小版本号加 1，写回文件，并按
             {目录名}-{新版本}-{当前分支名} 创建 tag。
  push_tag   查找当前分支下该目录最新的 tag，并推送到 origin。
EOF
}

fail() {
  echo "$1" >&2
  exit 1
}

ensure_git_repo() {
  git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "当前目录不是 git 仓库。"
}

get_current_branch() {
  local branch

  branch="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"
  [[ -n "$branch" ]] || fail "无法获取当前分支，请确认当前不是 detached HEAD。"
  printf '%s\n' "$branch"
}

ensure_origin_remote() {
  git -C "$ROOT_DIR" remote get-url origin >/dev/null 2>&1 || fail "未找到远程 origin，请先配置远程仓库。"
}

get_version_file() {
  local dir_name="$1"
  local version_file="$ROOT_DIR/$dir_name/version.txt"

  [[ -d "$ROOT_DIR/$dir_name" ]] || fail "目录不存在：$dir_name"
  [[ -f "$version_file" ]] || fail "未找到 version.txt：$dir_name/version.txt"
  printf '%s\n' "$version_file"
}

read_version() {
  local version_file="$1"
  local version

  IFS= read -r version < "$version_file" || true
  version="${version%$'\r'}"
  [[ -n "$version" ]] || fail "version.txt 为空：$version_file"
  printf '%s\n' "$version"
}

bump_patch_version() {
  local version="$1"
  local major=""
  local minor=""
  local patch=""

  IFS='.' read -r major minor patch <<EOF
$version
EOF

  [[ -n "$major" && -n "$minor" && -n "$patch" ]] || fail "版本格式无效：$version，期望格式为 x.y.z"
  [[ "$major" =~ ^[0-9]+$ ]] || fail "版本格式无效：$version，major 不是数字"
  [[ "$minor" =~ ^[0-9]+$ ]] || fail "版本格式无效：$version，minor 不是数字"
  [[ "$patch" =~ ^[0-9]+$ ]] || fail "版本格式无效：$version，patch 不是数字"

  patch=$((patch + 1))
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

update_tag() {
  local dir_name="$1"
  local version_file=""
  local old_version=""
  local new_version=""
  local branch=""
  local new_tag=""

  version_file="$(get_version_file "$dir_name")"
  old_version="$(read_version "$version_file")"
  new_version="$(bump_patch_version "$old_version")"
  branch="$(get_current_branch)"
  new_tag="${dir_name}-${new_version}-${branch}"

  git -C "$ROOT_DIR" rev-parse "$new_tag" >/dev/null 2>&1 && fail "tag 已存在：$new_tag"

  printf '%s\n' "$new_version" > "$version_file"
  git -C "$ROOT_DIR" tag "$new_tag"

  echo "已更新版本：$dir_name $old_version -> $new_version"
  echo "已创建 tag：$new_tag"
}

find_latest_branch_tag() {
  local dir_name="$1"
  local branch="$2"
  local latest_tag=""

  latest_tag="$(git -C "$ROOT_DIR" tag --list "${dir_name}-*-${branch}" --sort=-v:refname | while IFS= read -r line; do printf '%s' "$line"; break; done)"
  [[ -n "$latest_tag" ]] || fail "未找到目录 $dir_name 在分支 $branch 下的 tag。"
  printf '%s\n' "$latest_tag"
}

push_tag() {
  local dir_name="$1"
  local branch=""
  local latest_tag=""

  [[ -d "$ROOT_DIR/$dir_name" ]] || fail "目录不存在：$dir_name"
  ensure_origin_remote

  branch="$(get_current_branch)"
  latest_tag="$(find_latest_branch_tag "$dir_name" "$branch")"

  git -C "$ROOT_DIR" push origin "$latest_tag"
  echo "已推送 tag：$latest_tag"
}

main() {
  local command="${1:-}"
  local dir_name="${2:-}"

  ensure_git_repo

  case "$command" in
    -h|--help|help)
      usage
      exit 0
      ;;
  esac

  [[ -n "$command" && -n "$dir_name" ]] || {
    usage
    exit 1
  }

  case "$command" in
    update_tag)
      update_tag "$dir_name"
      ;;
    push_tag)
      push_tag "$dir_name"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
