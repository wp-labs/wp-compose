#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
GHCR_NAMESPACE="ghcr.io/wp-labs"

usage() {
  cat <<'EOF'
用法:
  ./image-update.sh <镜像名> [分支] [选项]

参数:
  镜像名   短名 (warp-parse) 或完整名 (ghcr.io/wp-labs/warp-parse)
           仅支持 ghcr.io/wp-labs/* 下的自研镜像
  分支     alpha | beta | main
           不传 = 使用当前 git 分支
           传入 = 先 git checkout 到该分支再执行（之后停留在该分支）

选项:
  --dry-run   只打印预览，不做任何写操作（切换过分支会在结束时切回）
  --yes, -y   跳过 commit 前的交互确认
  -h, --help  显示本帮助

行为:
  1. （若显式传入分支）checkout 到目标分支
  2. 查询镜像在目标分支对应后缀下的最新 tag
  3. 扫描仓库各子目录的 docker-compose 文件，把该镜像的 image 行
     统一替换为最新 tag（无论原先是 alpha/beta/无后缀）
  4. 对每个受影响目录的 version.txt 执行 patch +1
  5. 提交改动，按 {目录}-{新版本}[-{分支}] 规则创建 tag
  6. 将分支和新创建的 tag 一起 push 到 origin
EOF
}

fail() {
  echo "错误: $1" >&2
  exit 1
}

log() {
  echo "[image-update] $*"
}

# ---------- 参数解析 ----------

IMAGE_INPUT=""
BRANCH_INPUT=""
DRY_RUN=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    -*)
      fail "未知选项: $1"
      ;;
    *)
      if [[ -z "$IMAGE_INPUT" ]]; then
        IMAGE_INPUT="$1"
      elif [[ -z "$BRANCH_INPUT" ]]; then
        BRANCH_INPUT="$1"
      else
        fail "多余参数: $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$IMAGE_INPUT" ]] || { usage; exit 1; }

# ---------- git 前置检查 ----------

git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "当前目录不是 git 仓库"

CURRENT_BRANCH="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"
[[ -n "$CURRENT_BRANCH" ]] || fail "无法获取当前分支（detached HEAD?）"

TARGET_BRANCH="${BRANCH_INPUT:-$CURRENT_BRANCH}"
EXPLICIT_BRANCH=0
[[ -n "$BRANCH_INPUT" ]] && EXPLICIT_BRANCH=1

case "$TARGET_BRANCH" in
  alpha) TAG_SUFFIX="-alpha"; TAG_REGEX='^[0-9]+\.[0-9]+\.[0-9]+-alpha$' ;;
  beta)  TAG_SUFFIX="-beta";  TAG_REGEX='^[0-9]+\.[0-9]+\.[0-9]+-beta$'  ;;
  main)  TAG_SUFFIX="";       TAG_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'        ;;
  *) fail "不支持的分支: ${TARGET_BRANCH}（仅支持 alpha / beta / main）" ;;
esac

# ---------- 镜像名归一化 ----------

if [[ "$IMAGE_INPUT" == */* ]]; then
  [[ "$IMAGE_INPUT" == "$GHCR_NAMESPACE/"* ]] \
    || fail "仅支持 $GHCR_NAMESPACE/* 下的自研镜像，收到: $IMAGE_INPUT"
  FULL_IMAGE="$IMAGE_INPUT"
else
  FULL_IMAGE="$GHCR_NAMESPACE/$IMAGE_INPUT"
fi

SHORT_NAME="${FULL_IMAGE#$GHCR_NAMESPACE/}"
GHCR_PATH="wp-labs/$SHORT_NAME"

log "镜像: $FULL_IMAGE"
log "目标分支: $TARGET_BRANCH (后缀: '${TAG_SUFFIX:-无}')"

# ---------- 工作区干净检查 ----------
# 需要 checkout（显式分支）时强制干净；否则 dry-run 允许脏工作区

NEED_CHECKOUT="$EXPLICIT_BRANCH"
REQUIRE_CLEAN=0
[[ "$DRY_RUN" -ne 1 ]] && REQUIRE_CLEAN=1
[[ "$NEED_CHECKOUT" -eq 1 ]] && REQUIRE_CLEAN=1

if [[ "$REQUIRE_CLEAN" -eq 1 ]]; then
  TRACKED_DIRTY="$(git -C "$ROOT_DIR" status --porcelain | awk '$1 !~ /^\?\?/ {print}')"
  if [[ -n "$TRACKED_DIRTY" ]]; then
    echo "$TRACKED_DIRTY" >&2
    fail "工作区有未提交的改动，请先 commit 或 stash 后再运行"
  fi
fi

# ---------- checkout 到目标分支 ----------

RESTORE_BRANCH=""
if [[ "$NEED_CHECKOUT" -eq 1 ]]; then
  log "切换到分支: $TARGET_BRANCH"
  git -C "$ROOT_DIR" checkout "$TARGET_BRANCH" \
    || fail "切换分支失败：$TARGET_BRANCH（不存在？先执行 git fetch origin）"
  # dry-run 结束后恢复原分支，保持无副作用
  if [[ "$DRY_RUN" -eq 1 && "$TARGET_BRANCH" != "$CURRENT_BRANCH" ]]; then
    RESTORE_BRANCH="$CURRENT_BRANCH"
  fi
fi

restore_branch_if_needed() {
  if [[ -n "$RESTORE_BRANCH" ]]; then
    log "dry-run 结束，切回原分支: $RESTORE_BRANCH"
    git -C "$ROOT_DIR" checkout "$RESTORE_BRANCH" >/dev/null 2>&1 \
      || log "警告: 切回 $RESTORE_BRANCH 失败，请手动切回"
  fi
}
trap restore_branch_if_needed EXIT

# ---------- 同步远端并检查分支是否落后 ----------

if git -C "$ROOT_DIR" remote get-url origin >/dev/null 2>&1; then
  log "同步远端: git fetch origin $TARGET_BRANCH"
  if ! git -C "$ROOT_DIR" fetch origin "$TARGET_BRANCH" --quiet 2>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "警告: fetch origin $TARGET_BRANCH 失败，dry-run 跳过落后检查"
    else
      fail "fetch origin $TARGET_BRANCH 失败（网络问题或分支不存在）"
    fi
  fi

  # 只有当前分支 == 目标分支（checkout 后必然成立）才能直接比较 HEAD
  if [[ "$(git -C "$ROOT_DIR" branch --show-current)" == "$TARGET_BRANCH" ]]; then
    if git -C "$ROOT_DIR" rev-parse --verify "origin/$TARGET_BRANCH" >/dev/null 2>&1; then
      BEHIND="$(git -C "$ROOT_DIR" rev-list --count "HEAD..origin/$TARGET_BRANCH" 2>/dev/null || echo 0)"
      if [[ "$BEHIND" -gt 0 ]]; then
        fail "本地 $TARGET_BRANCH 落后 origin/$TARGET_BRANCH $BEHIND 个 commit，请先 git pull --ff-only 后重试"
      fi
    fi
  fi
else
  log "未配置 origin 远程，跳过落后检查"
fi

# ---------- 查询 GitHub 源码 tag ----------
# 假设: ghcr.io/wp-labs/<X> 对应 github.com/wp-labs/<X>
# 源码 git tag 带 v 前缀 (v0.1.4-alpha)，镜像 tag 不带 (0.1.4-alpha)

query_repo_tags() {
  command -v gh >/dev/null 2>&1 \
    || fail "缺少 gh CLI，请参考 https://cli.github.com/"
  gh auth status >/dev/null 2>&1 \
    || fail "gh 未登录，请执行 gh auth login"

  local raw
  if ! raw="$(gh api --paginate "repos/wp-labs/${SHORT_NAME}/tags" --jq '.[].name' 2>&1)"; then
    if printf '%s' "$raw" | grep -q "Not Found"; then
      fail "找不到仓库 wp-labs/${SHORT_NAME}（镜像名与仓库名不一致？）"
    fi
    fail "查询 repos/wp-labs/${SHORT_NAME}/tags 失败: $raw"
  fi
  # strip 开头的 v，得到镜像 tag 风格
  printf '%s\n' "$raw" | sed -nE 's/^v([0-9].*)$/\1/p'
}

log "查询源码 tag: repos/wp-labs/${SHORT_NAME}"
ALL_TAGS="$(query_repo_tags)"
[[ -n "$ALL_TAGS" ]] || fail "仓库 wp-labs/${SHORT_NAME} 无可用 tag"

LATEST_TAG="$(printf '%s\n' "$ALL_TAGS" | grep -E "$TAG_REGEX" | sort -V | tail -n1 || true)"
[[ -n "$LATEST_TAG" ]] || fail "在分支 $TARGET_BRANCH 下未找到匹配 $TAG_REGEX 的 tag"

log "最新版本: $LATEST_TAG"

# ---------- 扫描 compose，计算要改的文件 ----------

find_compose_files() {
  find "$ROOT_DIR" -mindepth 2 -maxdepth 2 \
    \( -name 'docker-compose.yml' \
    -o -name 'docker-compose.yaml' \
    -o -name 'compose.yml' \
    -o -name 'compose.yaml' \) \
    -not -path '*/.*' \
    2>/dev/null | sort
}

# 对一个 compose 文件做替换
# 参数: <file> <write: 0|1>
# 输出到 stdout: 每个改动一行 "old_tag -> new_tag"
# 行为: 匹配到该 image 的任意 tag 行都替换为 new_tag（不按原后缀过滤）
rewrite_file() {
  local file="$1" write="$2" tmp
  tmp="$(mktemp)"
  awk -v img="$FULL_IMAGE" -v new_tag="$LATEST_TAG" -v out="$tmp" '
    {
      line = $0
      if (match(line, "^[[:space:]]*image:[[:space:]]*" img ":")) {
        head = substr(line, 1, RLENGTH)
        rest = substr(line, RLENGTH + 1)
        tag_only = rest
        sub(/[[:space:]]+$/, "", tag_only)
        if (tag_only == new_tag) {
          print line > out
        } else {
          print head new_tag > out
          print tag_only " -> " new_tag
        }
        next
      }
      print line > out
    }
  ' "$file"
  if [[ "$write" -eq 1 ]]; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
  fi
}

declare -a CHANGED_DIRS=()
declare -a CHANGED_FILES=()

while IFS= read -r compose_file; do
  [[ -n "$compose_file" ]] || continue
  dir_abs="$(dirname -- "$compose_file")"
  dir_name="$(basename -- "$dir_abs")"

  if ! grep -qE "^[[:space:]]*image:[[:space:]]*${FULL_IMAGE//\//\\/}:" "$compose_file"; then
    continue
  fi

  write_flag=1
  [[ "$DRY_RUN" -eq 1 ]] && write_flag=0

  changes="$(rewrite_file "$compose_file" "$write_flag")"
  if [[ -n "$changes" ]]; then
    count="$(printf '%s\n' "$changes" | wc -l | tr -d ' ')"
    log "修改: ${compose_file#$ROOT_DIR/} ($count 行)"
    while IFS= read -r ch; do
      log "  $ch"
    done <<<"$changes"
    CHANGED_FILES+=("$compose_file")
    already=0
    for d in "${CHANGED_DIRS[@]:-}"; do
      [[ "$d" == "$dir_name" ]] && already=1 && break
    done
    [[ "$already" -eq 0 ]] && CHANGED_DIRS+=("$dir_name")
  fi
done < <(find_compose_files)

if [[ ${#CHANGED_DIRS[@]} -eq 0 ]]; then
  log "无需更新：没有 compose 文件引用 $FULL_IMAGE 或均已是最新 $LATEST_TAG"
  exit 0
fi

# ---------- bump version.txt ----------

bump_patch() {
  local v="$1" major minor patch
  IFS='.' read -r major minor patch <<EOF
$v
EOF
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]] \
    || fail "版本格式无效: $v"
  printf '%s.%s.%s' "$major" "$minor" "$((patch + 1))"
}

declare -a BUMP_SUMMARY=()
declare -a TAGS_TO_CREATE=()
declare -a VERSION_FILES=()

for dir_name in "${CHANGED_DIRS[@]}"; do
  version_file="$ROOT_DIR/$dir_name/version.txt"
  [[ -f "$version_file" ]] || fail "缺少 version.txt: $dir_name/version.txt"
  old_version=""
  IFS= read -r old_version < "$version_file" || true
  old_version="${old_version%$'\r'}"
  [[ -n "$old_version" ]] || fail "version.txt 为空: $dir_name/version.txt"

  new_version="$(bump_patch "$old_version")"

  if [[ -n "$TAG_SUFFIX" ]]; then
    new_tag="${dir_name}-${new_version}${TAG_SUFFIX}"
  else
    new_tag="${dir_name}-${new_version}"
  fi

  if git -C "$ROOT_DIR" rev-parse "$new_tag" >/dev/null 2>&1; then
    fail "tag 已存在: $new_tag"
  fi

  BUMP_SUMMARY+=("$dir_name: $old_version -> $new_version")
  TAGS_TO_CREATE+=("$new_tag")
  VERSION_FILES+=("$version_file")

  if [[ "$DRY_RUN" -ne 1 ]]; then
    printf '%s\n' "$new_version" > "$version_file"
  fi
done

# ---------- 摘要 ----------

echo
echo "===== 变更摘要 ====="
echo "镜像:   $FULL_IMAGE:$LATEST_TAG"
echo "分支:   $TARGET_BRANCH"
echo "Compose 文件:"
for f in "${CHANGED_FILES[@]}"; do
  echo "  - ${f#$ROOT_DIR/}"
done
echo "version.txt bump:"
for s in "${BUMP_SUMMARY[@]}"; do
  echo "  - $s"
done
echo "要创建的 tag:"
for t in "${TAGS_TO_CREATE[@]}"; do
  echo "  - $t"
done
echo "push 目标: origin $TARGET_BRANCH + 上述 tag"
echo "===================="
echo

# ---------- dry-run 退出 ----------

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry-run 完成（未写文件、未 commit/tag/push）"
  exit 0
fi

# ---------- 确认 ----------

if [[ "$ASSUME_YES" -ne 1 ]]; then
  read -r -p "确认执行 commit / tag / push? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) log "已取消，文件改动未回滚（可手动 git checkout -- 回滚）"; exit 1 ;;
  esac
fi

# ---------- commit ----------

git -C "$ROOT_DIR" add -- "${CHANGED_FILES[@]}" "${VERSION_FILES[@]}"

if [[ ${#CHANGED_DIRS[@]} -eq 1 ]]; then
  commit_msg="${CHANGED_DIRS[0]}: bump ${SHORT_NAME} to ${LATEST_TAG}"
  git -C "$ROOT_DIR" commit -m "$commit_msg"
else
  commit_title="bump ${SHORT_NAME} to ${LATEST_TAG}"
  {
    printf '%s\n\n' "$commit_title"
    for s in "${BUMP_SUMMARY[@]}"; do
      printf -- '- %s\n' "$s"
    done
  } | git -C "$ROOT_DIR" commit -F -
fi

log "已提交"

# ---------- tag ----------

for t in "${TAGS_TO_CREATE[@]}"; do
  git -C "$ROOT_DIR" tag "$t"
  log "已创建 tag: $t"
done

# ---------- push ----------

git -C "$ROOT_DIR" remote get-url origin >/dev/null 2>&1 \
  || fail "未配置 origin 远程，跳过 push"

git -C "$ROOT_DIR" push origin "$TARGET_BRANCH" "${TAGS_TO_CREATE[@]}"
log "已推送到 origin: $TARGET_BRANCH + ${#TAGS_TO_CREATE[@]} 个 tag"
