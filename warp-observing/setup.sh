#!/usr/bin/env bash

set -u

. "$(cd -- "$(dirname -- "$0")/../scripts" && pwd)/compose-common.sh"

VERSION_FILE="$SCRIPT_DIR/version.txt"
DOWNLOAD_BASE_URL="https://github.com/wp-labs/wp-compose/releases/download"

VERSION=""
BRANCH="main"
ARCH=""
RELEASE_NAME=""
ARCHIVE_NAME=""
ARCHIVE_PATH=""
DOWNLOAD_URL=""

detect_git_branch() {
  local branch_name=""

  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi

  branch_name="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

  if [[ -z "$branch_name" || "$branch_name" == "HEAD" ]]; then
    return 1
  fi

  printf '%s' "$branch_name"
  return 0
}

read_version_info() {
  local line=""
  local first_value=""
  local branch_from_git=""

  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "未找到 version.txt，请在同级目录提供该文件。" >&2
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim_trailing_cr "$line")

    if [[ -z "$line" ]]; then
      continue
    fi

    case "$line" in
      VERSION=*|version=*)
        VERSION="${line#*=}"
        ;;
      BRANCH=*|branch=*)
        ;;
      *)
        if [[ -z "$first_value" ]]; then
          first_value="$line"
        fi
        ;;
    esac
  done < "$VERSION_FILE"

  if [[ -z "$VERSION" ]]; then
    VERSION="$first_value"
  fi

  branch_from_git="$(detect_git_branch || true)"
  if [[ -n "$branch_from_git" ]]; then
    BRANCH="$branch_from_git"
  fi

  if [[ -z "$VERSION" ]]; then
    echo "version.txt 缺少版本号。支持格式：第一行版本，或 VERSION= 形式。" >&2
    exit 1
  fi

  if [[ -z "$BRANCH" ]]; then
    BRANCH="main"
  fi
}

resolve_arch() {
  ARCH="$(uname -m 2>/dev/null || true)"

  case "$ARCH" in
    x86_64|aarch64)
      ;;
    amd64)
      ARCH="x86_64"
      ;;
    arm64)
      ARCH="aarch64"
      ;;
    *)
      echo "暂不支持当前架构：$ARCH" >&2
      exit 1
      ;;
  esac
}

build_download_url() {
  local dir_name

  dir_name="$(basename "$SCRIPT_DIR")"
  RELEASE_NAME="${dir_name}-${VERSION}"

  if [[ "$BRANCH" != "main" ]]; then
    RELEASE_NAME="${RELEASE_NAME}-${BRANCH}"
  fi

  ARCHIVE_NAME="${RELEASE_NAME}-${ARCH}-unknown-linux-gnu-images.tar.gz"
  ARCHIVE_PATH="$SCRIPT_DIR/$ARCHIVE_NAME"
  DOWNLOAD_URL="$DOWNLOAD_BASE_URL/$RELEASE_NAME/$ARCHIVE_NAME"
}

download_archive() {
  if [[ -f "$ARCHIVE_PATH" ]]; then
    echo "检测到已存在镜像包：$ARCHIVE_NAME"
    return 0
  fi

  echo "开始下载镜像包：$DOWNLOAD_URL"

  if command -v curl >/dev/null 2>&1; then
    if ! curl -fL --progress-bar -o "$ARCHIVE_PATH" "$DOWNLOAD_URL"; then
      rm -f "$ARCHIVE_PATH"
      echo "镜像包下载失败：$DOWNLOAD_URL" >&2
      exit 1
    fi
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    if ! wget -O "$ARCHIVE_PATH" "$DOWNLOAD_URL"; then
      rm -f "$ARCHIVE_PATH"
      echo "镜像包下载失败：$DOWNLOAD_URL" >&2
      exit 1
    fi
    return 0
  fi

  echo "未检测到 curl 或 wget，无法下载镜像包。" >&2
  exit 1
}

load_archive() {
  if ! command -v gunzip >/dev/null 2>&1; then
    echo "未检测到 gunzip，无法解压镜像包。" >&2
    exit 1
  fi

  echo "开始导入镜像包：$ARCHIVE_NAME"
  if ! gunzip -c "$ARCHIVE_PATH" | docker load; then
    echo "镜像导入失败：$ARCHIVE_PATH" >&2
    exit 1
  fi

  if ! rm -f "$ARCHIVE_PATH"; then
    echo "镜像导入完成，但未能删除临时镜像包：$ARCHIVE_PATH" >&2
  fi
}

ensure_images_exist() {
  local missing_images=()
  local image=""

  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    missing_images+=("$image")
  done < <(collect_missing_images)

  if [[ ${#missing_images[@]} -eq 0 ]]; then
    echo "compose 依赖的镜像已全部存在，跳过下载。"
    return 0
  fi

  echo "以下镜像当前不存在："
  printf '  - %s\n' "${missing_images[@]}"

  read_version_info
  resolve_arch
  build_download_url
  download_archive
  load_archive

  missing_images=()
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    missing_images+=("$image")
  done < <(collect_missing_images)

  if [[ ${#missing_images[@]} -gt 0 ]]; then
    echo "镜像导入后仍缺少以下镜像：" >&2
    printf '  - %s\n' "${missing_images[@]}" >&2
    exit 1
  fi

  echo "镜像已准备完成。"
}

main() {
  find_compose_file
  resolve_compose_cmd
  ensure_images_exist
}

main "$@"
