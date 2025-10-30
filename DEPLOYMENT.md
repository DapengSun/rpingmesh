# R-Pingmesh 部署指南

## 快速开始

### 1. 环境检测

在部署前，建议先检测RDMA环境兼容性：

```bash
# 构建环境监测镜像
./build_monitor.sh

# 快速环境检测
docker run -it --rm --privileged --network host rpingmesh-monitor:latest ./quick_check.sh

# 完整环境检测报告
docker run -it --rm --privileged --network host rpingmesh-monitor:latest ./comprehensive_test.sh
```

### 2. 构建镜像

#### 分离式部署（算力平台）
```bash
# 构建所有镜像
./build_separate.sh

# 或分别构建
./build_controller.sh  # 构建Controller镜像
./build_agent.sh       # 构建Agent镜像
./build_rqlite.sh      # 构建自定义RQLite镜像
```

#### 统一镜像部署
```bash
# 构建统一镜像
./build_unified.sh
```

### 3. 创建配置文件

```bash
# 创建配置目录
mkdir -p config

# Controller配置
cat > config/controller.yaml << 'EOF'
listen-addr: "0.0.0.0:50051"
database-uri: "http://rqlite:4001"
log-level: "info"
EOF

# Agent配置
cat > config/agent.yaml << 'EOF'
controller-addr: "controller:50051"
analyzer-addr: "127.0.0.1:50052"
log-level: "info"
probe-interval-ms: 500
ebpf-enabled: false
EOF
```

### 4. 部署服务

#### 分离式部署
```bash
# 创建网络
docker network create rpingmesh-network

# 启动自定义RQLite数据库（支持bash和持久化）
docker run -d --name rqlite --network rpingmesh-network \
  -v $(pwd)/data:/data -e NODE_ID=rqlite-001 rpingmesh-rqlite:latest

# 启动Controller
docker run -d --name controller --network rpingmesh-network \
  -v $(pwd)/config:/config:ro rpingmesh-controller:latest

# 启动Agent
docker run -d --name agent --privileged --network rpingmesh-network \
  -v $(pwd)/config:/config:ro rpingmesh-agent:latest
```

#### 统一镜像部署
```bash
# 创建网络
docker network create rpingmesh-network

# 启动自定义RQLite数据库（支持bash和持久化）
docker run -d --name rqlite --network rpingmesh-network \
  -v $(pwd)/data:/data -e NODE_ID=rqlite-001 rpingmesh-rqlite:latest

# 启动R-Pingmesh（包含Controller和Agent）
docker run -d --name rpingmesh --privileged --network rpingmesh-network \
  -v $(pwd)/config:/config:ro rpingmesh-deployment:latest
```

## 环境监测

### 监测工具
```bash
# 构建监测镜像
./build_monitor.sh

# 快速检测
docker run -it --rm --privileged --network host rpingmesh-monitor:latest ./quick_check.sh

# 完整检测报告
docker run -it --rm --privileged --network host rpingmesh-monitor:latest ./comprehensive_test.sh

# 增强RDMA测试
docker run -it --rm --privileged --network host rpingmesh-monitor:latest ./enhanced_rdma_test.sh

# 交互式使用
docker run -it --rm --privileged --network host rpingmesh-monitor:latest
```

## 管理命令

### 查看状态
```bash
# 分离式部署
docker exec rqlite ./status.sh
docker exec controller ./status.sh
docker exec agent ./status.sh

# 统一镜像部署
docker exec rqlite ./status.sh
docker exec rpingmesh ./status.sh
```

### 查看日志
```bash
# 分离式部署
docker exec rqlite tail -f /var/log/supervisor/rqlite.log
docker logs controller
docker logs agent

# 统一镜像部署
docker exec rqlite tail -f /var/log/supervisor/rqlite.log
docker exec rpingmesh tail -f /var/log/supervisor/controller.log
docker exec rpingmesh tail -f /var/log/supervisor/agent.log
```

### 重启服务
```bash
# 分离式部署
docker exec rqlite supervisorctl restart rqlite
docker restart controller
docker restart agent

# 统一镜像部署
docker exec rqlite supervisorctl restart rqlite
docker exec rpingmesh supervisorctl restart all
```

### 停止服务
```bash
docker stop agent controller rqlite
docker rm agent controller rqlite
```

## 镜像导出/导入

### 导出镜像
```bash
# 分离式部署
docker save rpingmesh-rqlite:latest | gzip > rqlite.tar.gz
docker save rpingmesh-controller:latest | gzip > controller.tar.gz
docker save rpingmesh-agent:latest | gzip > agent.tar.gz
docker save rpingmesh-analyzer:latest | gzip > analyzer.tar.gz

# 统一镜像部署
docker save rpingmesh-rqlite:latest | gzip > rqlite.tar.gz
docker save rpingmesh-deployment:latest | gzip > rpingmesh.tar.gz

# 环境监测镜像
docker save rpingmesh-checker:latest | gzip > checker.tar.gz
```

### 导入镜像
```bash
docker load < rqlite.tar.gz
docker load < controller.tar.gz
docker load < agent.tar.gz
# 或
docker load < rpingmesh.tar.gz
# 或
docker load < checker.tar.gz
```

## 配置说明

### Controller配置 (config/controller.yaml)
- `listen-addr`: Controller监听地址
- `database-uri`: RQLite数据库地址
- `log-level`: 日志级别

### Agent配置 (config/agent.yaml)
- `controller-addr`: Controller地址
- `analyzer-addr`: Analyzer地址
- `ebpf-enabled`: 是否启用eBPF
- `probe-interval-ms`: 探测间隔

### 调试模式
```bash
# 进入容器调试
docker exec -it controller /bin/bash
docker exec -it agent /bin/bash
docker exec -it rpingmesh /bin/bash
docker exec -it rqlite /bin/bash
```

