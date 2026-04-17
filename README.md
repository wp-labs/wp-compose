# wp-compose

这个仓库用于维护基于 Docker Compose 的工具集目录，并提供可下载的离线镜像包。

## 目录说明

- `warp-observing`：本地观测环境，包含 `victoria-metrics`、`victoria-logs`、`wp-monitor`
- `warp-station`：本地管理台环境，包含 `postgres`、`gitea`、`warp-station`
- `scripts/compose-common.sh`：`setup.sh` / `start.sh` 共用的检查逻辑

## 最新使用方式

每个工具目录都按下面的两步执行：

```bash
./setup.sh
./start.sh
```

- `setup.sh`：检查 Docker / Compose、检查镜像是否存在、按约定下载离线镜像包并执行 `docker load`
- `start.sh`：根据 `.env.example` 生成 `.env`，然后执行 `docker compose up -d` 或 `docker-compose up -d`

## setup.sh 做了什么

`setup.sh` 会先检查：

- `docker` 是否已安装
- Docker daemon 是否已启动
- `docker compose` 或 `docker-compose` 是否可用

如果当前 compose 依赖镜像缺失，脚本会自动从 GitHub Release 下载镜像包并导入。

## version.txt 约定

需要在目标目录下提供 `version.txt`，当前只需要填写版本号，例如：

```text
0.1.5
```

脚本会自动读取：

- 目录名，例如 `warp-observing`
- 当前 Git 分支，例如 `alpha`
- 当前机器架构，例如 `x86_64` 或 `aarch64`

然后拼出下载地址：

```text
https://github.com/wp-labs/wp-compose/releases/download/{目录名}-{版本}-{分支后缀}/{目录名}-{版本}-{分支后缀}-{架构}-unknown-linux-gnu-images.tar.gz
```

- 当前分支是 `main` 时，不拼接分支后缀
- 当前分支是 `alpha` 时，会拼接 `-alpha`

例如在 `warp-observing` 目录、版本 `0.1.5`、当前分支 `alpha`、ARM64 环境下，实际地址会是：

```text
https://github.com/wp-labs/wp-compose/releases/download/warp-observing-0.1.5-alpha/warp-observing-0.1.5-alpha-aarch64-unknown-linux-gnu-images.tar.gz
```

镜像导入成功后，脚本会自动删除下载下来的 tar 包，不会在目录中保留。

## start.sh 做了什么

`start.sh` 会在 `.env` 不存在时，根据 `.env.example` 自动生成配置。

当前支持两种变量注释格式：

- `# ${描述}`：与用户交互，按回车时使用默认值
- `# {描述}`：不交互，直接写入默认值

生成 `.env` 时，会把描述一并写成普通注释：

```env
# 数据保存时间
RETENTION_PERIOD=15d
```

## 使用示例

以 `warp-observing` 为例：

```bash
cd warp-observing
./setup.sh
./start.sh
```

以 `warp-station` 为例：

```bash
cd warp-station
./setup.sh
./start.sh
```

更具体的环境变量说明，请查看各目录下的 `README.md`。

如果你是仓库维护者，想了解 tag 规则、目录约定和打包流程，请查看 `CONTRIBUTING.md`。
