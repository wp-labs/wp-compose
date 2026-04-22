# 开发者文档

这个文档面向维护 `wp-compose` 仓库的开发者，说明目录约定和 release 打包 CI 的工作方式。

## 目录约定

仓库根目录下每个非隐藏一级目录都可以作为一个独立工具目录。

面向用户的入口约定如下：

- 目录内提供 `setup.sh`：用于检查 Docker 环境、准备镜像
- 目录内提供 `start.sh`：用于生成 `.env` 并启动服务
- 共用逻辑放在仓库根目录 `scripts/` 下

如果某个目录中存在以下任一文件：

- `docker-compose.yml`
- `docker-compose.yaml`
- `compose.yml`
- `compose.yaml`

那么它就会被 `/.github/workflows/release-compose-images.yml` 识别为可打包目录。

## Release 打包 CI

这个工作流会在推送 Git tag 时自动执行以下动作：

- 扫描仓库根目录下所有非隐藏一级目录
- 查找目录中的 Docker Compose 文件
- 如果 tag 以前缀 `目录名-` 开头，则只打包该目录
- 使用 `docker compose config --images` 提取目录所需镜像
- 分别按 `linux/amd64` 和 `linux/arm64` 拉取镜像并通过 `docker save` 打包
- 生成带架构后缀的 release 附件
- 创建或更新同名 GitHub Release，并上传产物

## 产物命名

生成的 release 包名格式为：

- `目录名-版本-x86_64-unknown-linux-gnu-images.tar.gz`
- `目录名-版本-aarch64-unknown-linux-gnu-images.tar.gz`

例如：

- `wp-console-0.1.0-alpha-x86_64-unknown-linux-gnu-images.tar.gz`
- `wp-console-0.1.0-alpha-aarch64-unknown-linux-gnu-images.tar.gz`

## setup/start 约定

### setup.sh

`setup.sh` 当前约定负责：

- 检查 `docker` 是否已安装
- 检查 Docker daemon 是否已启动
- 检查 `docker compose` 或 `docker-compose` 是否可用
- 检查 compose 依赖镜像是否已存在
- 镜像缺失时，按 release 规则下载 `*.tar.gz` 并执行 `docker load`
- 导入成功后删除下载下来的 tar 包

### start.sh

`start.sh` 当前约定负责：

- 在 `.env` 不存在时，根据 `.env.example` 生成 `.env`
- 启动 `docker compose up -d` 或 `docker-compose up -d`

`.env.example` 当前支持两类注释变量：

- `# ${描述}`：交互式变量，提示用户输入，回车使用默认值
- `# {描述}`：自动变量，不提示用户，直接写入默认值

生成 `.env` 时，描述会被写成普通注释，例如：

```env
# 数据保存时间
RETENTION_PERIOD=15d
```

## version.txt 约定

需要在目标目录下提供 `version.txt`，当前只需要填写版本号，例如：

```text
0.1.5
```

`setup.sh` 会结合以下信息拼接 release 下载地址：

- 目录名，例如 `warp-observing`
- `version.txt` 中的版本号，例如 `0.1.5`
- 当前 Git 分支，例如 `alpha`
- 当前机器架构，例如 `x86_64` 或 `aarch64`

下载地址格式为：

```text
https://github.com/wp-labs/wp-compose/releases/download/{目录名}-{版本}-{分支后缀}/{目录名}-{版本}-{分支后缀}-{架构}-unknown-linux-gnu-images.tar.gz
```

- 当前分支为 `main` 时，不拼接分支后缀
- 当前分支为 `alpha` 时，会拼接 `-alpha`

示例：

```text
https://github.com/wp-labs/wp-compose/releases/download/warp-observing-0.1.5-alpha/warp-observing-0.1.5-alpha-aarch64-unknown-linux-gnu-images.tar.gz
```

## Tag 规则

### 仓库级发布

直接使用版本号 tag 时，CI 会扫描并打包所有可识别目录：

```bash
git tag 0.1.0
git push origin 0.1.0
```

```bash
git tag 0.1.0-alpha
git push origin 0.1.0-alpha
```

### 组件级发布

使用 `目录名-版本` 形式的 tag 时，CI 只打包对应目录：

```bash
git tag wp-console-0.1.0-alpha
git push origin wp-console-0.1.0-alpha
```

这个例子只会为 `wp-console/` 生成 release 附件。

## 源码分支选择规则

CI 的触发方式是打 tag，但实际打包时使用的源码分支由 tag 名决定：

- tag 包含 `alpha`：从 `alpha` 分支打包
- tag 包含 `beta`：从 `beta` 分支打包
- 其他 tag：从 `main` 分支打包

示例：

- `0.1.0-alpha` -> 从 `alpha` 分支打包
- `0.1.0-beta` -> 从 `beta` 分支打包
- `0.1.0` -> 从 `main` 分支打包
- `wp-console-0.1.0-alpha` -> 从 `alpha` 分支打包 `wp-console/`

## 镜像版本升级：image-update.sh

根目录下的 `image-update.sh` 用于一键升级自研镜像的版本，并按仓库约定打 tag、推送。

### 用途

当 `ghcr.io/wp-labs/*` 下的自研镜像（`warp-parse`、`wp-station`、`wp-monitor` 等）发布新版本后，自动完成：

1. 查询该镜像在目标分支对应后缀下的最新 tag
2. 扫描所有子目录的 `docker-compose.yml` / `compose.yml`，把该镜像的**所有**版本行统一改成最新版
3. 对受影响目录的 `version.txt` 执行 patch +1
4. 一个 commit 包含全部改动
5. 为每个受影响目录按 Tag 规则创建 tag
6. `git push origin <分支> <tag...>`

### 用法

```bash
./image-update.sh <镜像名> [分支] [--dry-run] [--yes]
```

- **镜像名**：短名（`warp-parse`）或完整名（`ghcr.io/wp-labs/warp-parse`）；仅支持 `ghcr.io/wp-labs/*`
- **分支**：`alpha` / `beta` / `main`
  - 不传 = 使用当前 git 分支
  - 显式传入 = **先 `git checkout` 到该分支**，之后停留在该分支
- `--dry-run`：预览，不写文件 / 不 commit / 不 tag / 不 push
- `--yes`, `-y`：跳过 commit 前的交互确认

### 前置条件

- 已安装 `gh` CLI 并 `gh auth login`（token 需有 `repo` scope，无需 `read:packages`）
- 镜像名与 GitHub 源码仓库同名（`ghcr.io/wp-labs/<X>` ↔ `github.com/wp-labs/<X>`）
- 源码 git tag 形如 `v<版本>[-<后缀>]`（镜像 tag 不带 `v` 前缀）

### 分支 → 后缀映射

| 分支 | 镜像 tag 后缀 | 目录 tag 形式 |
|---|---|---|
| `alpha` | `-alpha` | `{目录}-{新版本}-alpha` |
| `beta` | `-beta` | `{目录}-{新版本}-beta` |
| `main` | 无 | `{目录}-{新版本}` |

### 执行前检查（自动拦截）

脚本开始业务前会做两个硬检查：

1. **工作区干净**：`git status` 有已跟踪文件的改动则中止（dry-run 不显式指定分支时放宽）
2. **本地分支不落后远端**：`git fetch origin <分支>` 后比较 `HEAD..origin/<分支>`，若落后则中止并提示 `git pull --ff-only`

此外：未登录 `gh`、镜像查不到、工作区冲突、tag 已存在 等任一条件不满足都会中止并给出原因。

### 版本查询策略

版本来源是 **GitHub 源码仓库的 git tag**，不是 container registry 的 image tag：

```bash
gh api --paginate "repos/wp-labs/<name>/tags"
  → strip 开头的 v
  → 按分支后缀正则过滤
  → sort -V | tail -1
```

好处是只需要 `repo` scope，能读 private package 对应的源码仓库，规避 GHCR 匿名 401 / `read:packages` 403 的权限问题。

### 示例

假设当前分支是 `alpha`：

```bash
# 预览把 warp-parse 升级到最新 alpha
./image-update.sh warp-parse --dry-run

# 确认无误后真执行（交互确认）
./image-update.sh warp-parse

# 切到 beta 分支升级 wp-monitor 并跳过确认
./image-update.sh wp-monitor beta --yes
```

典型输出摘要（dry-run）：

```
镜像:   ghcr.io/wp-labs/wp-monitor:0.4.1-alpha
分支:   alpha
Compose 文件:
  - warp-console/docker-compose.yml
  - warp-observing/docker-compose.yml
version.txt bump:
  - warp-console: 0.1.2 -> 0.1.3
  - warp-observing: 0.1.2 -> 0.1.3
要创建的 tag:
  - warp-console-0.1.3-alpha
  - warp-observing-0.1.3-alpha
push 目标: origin alpha + 上述 tag
```

### 与手工流程的关系

`image-update.sh` 不会替代 `version-utils.sh`——后者保留给只需要 bump 版本、不需要改镜像的场景（例如配置/脚本自身的改动）。新建工具目录或非镜像改动仍按原手工流程走。

## 维护建议

- 新增工具目录时，把 Compose 文件放在根目录一级子目录中
- 如需支持 release 打包，优先固定镜像 tag，避免 `latest` 带来内容漂移
- 修改 CI 行为时，同时更新 `README.md` 和本开发者文档
- 新增自研镜像时，保持"镜像名 == 源码仓库名"约定，`image-update.sh` 才能自动识别
