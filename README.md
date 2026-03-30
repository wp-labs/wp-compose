# wp-tools

这个仓库用于维护基于 Docker Compose 的工具集目录，以及对应的镜像离线打包发布流程。

当前仓库包含：

- `wp-console/`：本地运行 `wp-editor`、`victoria-metrics`、`victoria-logs` 的 Compose 环境

## 目录约定

仓库根目录下每个非隐藏一级目录都可以作为一个独立工具目录。

如果某个目录中存在以下任一文件：

- `docker-compose.yml`
- `docker-compose.yaml`
- `compose.yml`
- `compose.yaml`

那么它就会被 Release CI 识别为可打包目录。

## Release 打包 CI

仓库使用 `/.github/workflows/release-compose-images.yml` 进行镜像离线包发布。

这个工作流会在推送 Git tag 时自动执行以下动作：

- 扫描仓库根目录下所有非隐藏一级目录
- 查找目录中的 Compose 文件
- 使用 `docker compose config --images` 提取该目录所需镜像
- 分别按 `linux/amd64` 和 `linux/arm64` 拉取镜像并通过 `docker save` 打包
- 生成带架构后缀的附件
- 创建或更新同名 GitHub Release，并上传这些产物

例如，当前仓库中的 `wp-console/` 会产出：

- `wp-console-v0.21.2-alpha-x86_64-unknown-linux-gnu-images.tar.gz`
- `wp-console-v0.21.2-alpha-aarch64-unknown-linux-gnu-images.tar.gz`

命名格式为：

- `目录名-tag-x86_64-unknown-linux-gnu-images.tar.gz`
- `目录名-tag-aarch64-unknown-linux-gnu-images.tar.gz`

## Tag 与打包分支规则

CI 的触发方式是打 tag，但实际打包时使用的源码分支由 tag 名决定：

- tag 包含 `alpha`：从 `alpha` 分支打包
- tag 包含 `beta`：从 `beta` 分支打包
- 其他 tag：从 `main` 分支打包

示例：

- `v1.0.0-alpha.1` -> 从 `alpha` 分支打包
- `v1.0.0-beta.1` -> 从 `beta` 分支打包
- `v1.0.0` -> 从 `main` 分支打包

## 使用方式

发布正式包：

```bash
git tag v1.0.0
git push origin v1.0.0
```

发布 alpha 包：

```bash
git tag v1.0.0-alpha.1
git push origin v1.0.0-alpha.1
```

发布 beta 包：

```bash
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
```

## 离线导入镜像

从 Release 下载 `*.tar.gz` 后，可以这样导入本地 Docker：

```bash
gunzip -c wp-console-v0.21.2-alpha-x86_64-unknown-linux-gnu-images.tar.gz | docker load
```

## 子目录说明

### `wp-console/`

`wp-console` 提供一套本地可运行的 Compose 环境，包含：

- `wp-editor`：Web 控制台，默认端口 `8080`
- `victoria-metrics`：指标存储，默认端口 `8428`
- `victoria-logs`：日志存储，默认端口 `9428`

进入目录后可直接启动：

```bash
docker compose up -d
```
