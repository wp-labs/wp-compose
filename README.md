# wp-tools

这个仓库用于维护基于 Docker Compose 的工具集目录，并提供可下载的离线镜像包。

当前仓库包含：

- `wp-console/`：本地运行 `wp-editor`、`victoria-metrics`、`victoria-logs` 的 Docker Compose 环境

## 获取镜像包

仓库会通过 GitHub Release 提供离线镜像包。

当前 `wp-console/` 对应的 release 产物会包含两种架构：

- `wp-console-0.1.0-alpha-x86_64-unknown-linux-gnu-images.tar.gz`
- `wp-console-0.1.0-alpha-aarch64-unknown-linux-gnu-images.tar.gz`

下载时请按你的运行环境选择：

- `x86_64-unknown-linux-gnu`：适用于常见 Intel / AMD Linux 环境
- `aarch64-unknown-linux-gnu`：适用于 ARM64 Linux 环境

如果你是仓库维护者，想了解 tag 规则、目录约定和打包流程，请查看 `CONTRIBUTING.md`。

## 离线导入镜像

从 Release 下载 `*.tar.gz` 后，可以这样导入本地 Docker：

```bash
gunzip -c wp-console-0.1.0-alpha-x86_64-unknown-linux-gnu-images.tar.gz | docker load
```

或者先解压，再通过 `-i` 参数导入：

```bash
gunzip wp-console-0.1.0-alpha-x86_64-unknown-linux-gnu-images.tar.gz
docker load -i wp-console-0.1.0-alpha-x86_64-unknown-linux-gnu-images.tar
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
