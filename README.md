# wp-compose

这个仓库用于维护基于 Docker Compose 的工具集目录，并提供可下载的离线镜像包。

## 可用目录

- `warp-observing`：本地观测环境，包含 `victoria-metrics`、`victoria-logs`、`wp-monitor`
- `warp-station`：本地管理台环境，包含 `postgres`、`gitea`、`warp-station`
- `warp-console`：本地管理台环境+日志解析+观测环境
## 怎么用

进入你需要的目录后，按下面两步执行：

```bash
./setup.sh
./start.sh
```

- `setup.sh`：准备 Docker 环境并导入所需镜像
- `start.sh`：生成配置并启动服务

如果目录下存在 `.env.example`，`start.sh` 会在 `.env` 不存在时引导你生成 `.env`。

## 使用示例

启动观测环境：

```bash
cd warp-observing
./setup.sh
./start.sh
```

启动管理台环境：

```bash
cd warp-station
./setup.sh
./start.sh
```

更具体的环境变量说明，请查看各目录下的 `README.md`。

如果你是仓库维护者，想了解打包约定、版本文件规则和发布细节，请查看 `CONTRIBUTING.md`。
