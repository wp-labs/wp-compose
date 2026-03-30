# wp-console

这个目录提供了一套基于 Docker Compose 的本地运行环境，用来快速启动以下 3 个服务：

- `wp-editor`：Web 控制台，默认暴露 `8080`
- `victoria-metrics`：指标存储服务，默认暴露 `8428`
- `victoria-logs`：日志存储服务，默认暴露 `9428`

## 环境变量

当前使用 `wp-console/.env` 管理配置：

```env
RETENTION_PERIOD=15d
```

- `RETENTION_PERIOD`: 指标和日志数据保留时间

## 启动
```bash
docker compose up -d
# docker compose老版本使用下面命令
docker-compose up -d
```
