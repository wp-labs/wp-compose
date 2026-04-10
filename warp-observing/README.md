# warp-observing

这个目录提供了一套观测wparse 的 Docker Compose 的本地运行环境，用来快速启动以下 3 个服务：

- `victoria-metrics`：指标存储服务，默认暴露 `8428`
- `victoria-logs`：日志存储服务，默认暴露 `9428`
- `wp-monitor`：wparse监控面板，默认端口 `18080`

## 环境变量

当前使用 `warp-observing/.env` 管理配置：

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

## 接入方式
在wparse的`topology/sinks/infra.d/monitor.toml`中添加如下配置
```toml
[[sink_group.sinks]]
name = "metrics_vmetrics_sink"
connect = "victoriametrics_sink"
params = { insert_url = "http://localhost:8428/api/v1/import/prometheus",flush_interval_secs = 1}
```
