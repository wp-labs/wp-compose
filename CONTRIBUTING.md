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

## 维护建议

- 新增工具目录时，把 Compose 文件放在根目录一级子目录中
- 如需支持 release 打包，优先固定镜像 tag，避免 `latest` 带来内容漂移
- 修改 CI 行为时，同时更新 `README.md` 和本开发者文档
