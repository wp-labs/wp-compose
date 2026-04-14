# wp-compose

这个仓库用于维护基于 Docker Compose 的工具集目录，并提供可下载的离线镜像包。


## 获取镜像包

仓库会通过 GitHub Release 提供离线镜像包。

当前的 release 产物会包含两种架构：

- `warp-observing-0.1.4-alpha-x86_64-unknown-linux-gnu-images.tar.gz`
- `warp-observing-0.1.4-alpha-aarch64-unknown-linux-gnu-images.tar.gz`

下载时请按你的运行环境选择：

- `x86_64-unknown-linux-gnu`：适用于常见 Intel / AMD Linux 环境
- `aarch64-unknown-linux-gnu`：适用于 ARM64 Linux 环境

如果你是仓库维护者，想了解 tag 规则、目录约定和打包流程，请查看 `CONTRIBUTING.md`。

## 离线导入镜像

从 Release 下载 `*.tar.gz` 后，可以这样导入本地 Docker：

```bash
gunzip -c warp-observing-0.1.4-alpha-x86_64-unknown-linux-gnu-images.tar.gz | docker load
```

或者先解压，再通过 `-i` 参数导入：

```bash
gunzip warp-observing-0.1.4-alpha-x86_64-unknown-linux-gnu-images.tar.gz
docker load -i warp-observing-0.1.4-alpha-x86_64-unknown-linux-gnu-images.tar
```

最后进入到对应目录
```bash
docker compose up -d
# 老版本
docker-compose up -d
```