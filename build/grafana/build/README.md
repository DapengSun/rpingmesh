# Grafana 构建配置

基于 `grafana/grafana:11.1.0` 构建的自定义镜像，自动完成基础配置与数据源/仪表盘的预配置。

## 快速开始

```bash
# 构建镜像
bash ../build.sh

# 或手动执行
# docker build -t rpingmesh-grafana:latest .
```

镜像启动后自动挂载到 `/private/rpingmesh/grafana`，默认账号 `admin/admin`。

## 目录结构

```
/private/rpingmesh/grafana/
├── config/
│   └── grafana.ini
├── data/
├── logs/
├── plugins/
└── provisioning/
    ├── datasources/
    │   └── datasources.yml
    └── dashboards/
        ├── dashboards.yml
        └── default_dashboard.json
```

首次启动时会将镜像内的默认配置复制到上述目录。若在主机侧提供 `/mnt/config-source/*.yml` 或 `grafana.ini`，脚本会优先使用挂载文件。

## 数据源

默认已经配置 Prometheus 数据源，指向同一 docker-compose 网络中的 `http://prometheus:9090`。如需修改可编辑 `datasources.yml`。

## 仪表盘

镜像内置 `R-Pingmesh Simulation Overview` 仪表盘，展示 RTT、延迟、超时等模拟指标。放置新的 JSON 仪表盘到 `provisioning/dashboards` 目录即可自动加载。