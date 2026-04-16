#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

COMPOSE_FILE=""
COMPOSE_CMD=()

find_compose_file() {
  if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
    return 0
  fi

  if [[ -f "$SCRIPT_DIR/docker-compose.yaml" ]]; then
    COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yaml"
    return 0
  fi

  echo "未找到 docker-compose.yml 或 docker-compose.yaml，请将脚本放在 compose 文件所在目录后重试。" >&2
  exit 1
}

resolve_compose_cmd() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "未检测到 docker，请先安装 Docker。" >&2
    exit 1
  fi

  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
    return 0
  fi

  echo "未检测到 docker compose 或 docker-compose，请先安装 Docker Compose。" >&2
  exit 1
}

list_compose_images() {
  local images_output

  if ! images_output=$("${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" config --images 2>/dev/null); then
    echo "无法解析 compose 镜像列表，请检查 $COMPOSE_FILE 是否有效。" >&2
    exit 1
  fi

  printf '%s\n' "$images_output" | while IFS= read -r image; do
    if [[ -n "$image" ]]; then
      printf '%s\n' "$image"
    fi
  done
}

collect_missing_images() {
  local image
  local missing=()

  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    if ! docker image inspect "$image" >/dev/null 2>&1; then
      missing+=("$image")
    fi
  done < <(list_compose_images)

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%s\n' "${missing[@]}"
  fi
}

ensure_images_exist() {
  local missing_images=()
  local bundle_path=""
  local image=""

  while true; do
    missing_images=()
    while IFS= read -r image; do
      [[ -z "$image" ]] && continue
      missing_images+=("$image")
    done < <(collect_missing_images)

    if [[ ${#missing_images[@]} -eq 0 ]]; then
      break
    fi

    echo "以下镜像当前不存在："
    printf '  - %s\n' "${missing_images[@]}"
    echo "请提供镜像包地址，通常文件名类似：xxx-alpha-x86_64-unknown-linux-gnu-images.tar.gz"

    while true; do
      read -r -p "请输入镜像包路径: " bundle_path

      if [[ -z "$bundle_path" ]]; then
        echo "镜像包路径不能为空，请重新输入。"
        continue
      fi

      if [[ ! -f "$bundle_path" ]]; then
        echo "文件不存在：$bundle_path"
        continue
      fi

      if gunzip -c "$bundle_path" | docker load; then
        break
      fi

      echo "镜像导入失败，请确认文件路径和文件内容后重新输入。"
    done
  done
}

trim_trailing_cr() {
  local value="$1"
  printf '%s' "${value%$'\r'}"
}

create_env_if_missing() {
  local env_file="$SCRIPT_DIR/.env"
  local env_example_file="$SCRIPT_DIR/.env.example"
  local prompt_input="/dev/tty"
  local line=""
  local description=""
  local description_mode="interactive"
  local key=""
  local default_value=""
  local user_value=""
  local intro_shown="0"
  local generated_lines=()

  if [[ -f "$env_file" ]]; then
    echo "检测到已存在的 .env，跳过生成。"
    return 0
  fi

  if [[ ! -f "$env_example_file" ]]; then
    echo "未找到 .env.example，无法生成 .env。" >&2
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim_trailing_cr "$line")

    if [[ -z "$line" ]]; then
      continue
    fi

    if [[ "$line" =~ ^#[[:space:]]*\$\{(.*)\}$ ]]; then
      description="${BASH_REMATCH[1]}"
      description_mode="interactive"
      continue
    fi

    if [[ "$line" =~ ^#[[:space:]]*\{(.*)\}$ ]]; then
      description="${BASH_REMATCH[1]}"
      description_mode="auto"
      continue
    fi

    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      default_value="${BASH_REMATCH[2]}"
      user_value="$default_value"

      if [[ "$description_mode" == "interactive" ]]; then
        if [[ "$intro_shown" == "0" ]]; then
          echo "请输入以下配置，直接回车使用默认值。"
          intro_shown="1"
        fi

        if [[ ! -r "$prompt_input" ]]; then
          echo "当前终端不可交互，无法根据 .env.example 生成 .env。" >&2
          exit 1
        fi

        if [[ -n "$description" ]]; then
          read -r -p "[${description}] (默认值：${default_value}): " user_value < "$prompt_input"
        else
          read -r -p "[${key}] (默认值：${default_value}): " user_value < "$prompt_input"
        fi

        if [[ -z "$user_value" ]]; then
          user_value="$default_value"
        fi
      fi

      if [[ -n "$description" ]]; then
        generated_lines+=("# ${description}")
      fi
      generated_lines+=("${key}=${user_value}")
      description=""
      description_mode="interactive"
    fi
  done < "$env_example_file"

  : > "$env_file"
  if [[ ${#generated_lines[@]} -gt 0 ]]; then
    printf '%s\n' "${generated_lines[@]}" > "$env_file"
  fi
  echo "配置已经保存到 .env 中。"
}

start_compose() {
  echo "开始启动服务..."
  "${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" up -d
}

main() {
  find_compose_file
  resolve_compose_cmd
  ensure_images_exist
  create_env_if_missing
  start_compose
}

main "$@"
