# Rpingmesh E2E 部署指南

本文档介绍如何在 RDMA 集群中部署 Rpingmesh 的服务端和客户端组件。所有组件均已容器化，部署前需要先构建或导入 Docker 镜像。

## 目录

- [前置准备](#前置准备)
- [服务端部署](#服务端部署)
- [客户端部署](#客户端部署)
- [验证部署](#验证部署)

## 前置准备

### 拉取代码
```bash
git clone -b refactor/build-deploy git@github.com:DapengSun/rpingmesh.git
```


### 镜像构建（在线环境）

如果部署环境可以访问 Docker Hub，可以直接构建镜像：

```bash
cd ${PROJECT_ROOT}
bash ./build_images.sh
```

> **注意**: `${PROJECT_ROOT}` 为项目根目录路径。

### 镜像导出与导入（离线环境）

如果部署环境无法访问网络，需要先在在线环境导出镜像，然后在离线环境导入：

**1. 在在线环境导出镜像：**

```bash
cd ${PROJECT_ROOT}

# images 为导出镜像的存放目录
bash ./save_images.sh images
```

**2. 在离线环境导入镜像：**

```bash
# 导入导出的镜像文件
docker load -i images/xxx.tar.gz
```

> **提示**: 如果镜像已构建或导入，可跳过此步骤。

## 服务端部署

服务端组件（Controller 和 Analyzer）需要部署在 RDMA 集群中的任意一台主机上。

### 步骤 1: 进入部署目录

```bash
cd e2e/server
```

### 步骤 2: 配置环境变量

根据 `env.example` 创建 `.env` 文件：

```bash
cp env.example .env
```

编辑 `.env` 文件，修改以下参数：

- `RPINGMESH_DATA_DIR`: 服务端持久化数据目录，默认为 `./data_dir`。该目录用于容器内数据持久化存储，可根据实际需求修改为其他路径。

### 步骤 3: 执行部署脚本

```bash
bash run_e2e.sh
```

该脚本会自动完成所有部署步骤，包括：
- 创建必要的目录结构
- 启动 Controller 和 Analyzer 容器
- 执行健康检查

### 步骤 4: 验证部署

部署完成后，可通过以下方式验证：

1. **查看部署日志**: 检查 `run_e2e.sh` 执行日志，确认验证脚本输出全部正常。

2. **手动执行验证脚本**:
   ```bash
   bash e2e/server/05-verify.sh
   ```

## 客户端部署

客户端组件（Agent）需要部署在 RDMA 集群中的**所有主机**上。

### 步骤 1: 进入部署目录

```bash
cd e2e/client
```

### 步骤 2: 配置环境变量

根据 `env.example` 创建 `.env` 文件：

```bash
cp env.example .env
```

编辑 `.env` 文件，修改以下参数：

- `RPINGMESH_DATA_DIR`: 客户端持久化数据目录，默认为 `./data_dir`。该目录用于容器内数据持久化存储，可根据实际需求修改为其他路径。

### 步骤 3: 配置 Agent

编辑 `client_config/agent.yaml` 文件，修改以下**必需**的配置项：

```yaml
controller-addr: "127.0.0.1:50051"          # Controller gRPC 地址，将 IP 改为服务端 IP
analyzer-addr: "127.0.0.1:50052"            # Analyzer gRPC 地址，将 IP 改为服务端 IP
otel-collector-addr: "grpc://127.0.0.1:4317" # OpenTelemetry Collector 地址，将 IP 改为服务端 IP
```

> **重要**: 请确保将上述配置中的 `127.0.0.1` 替换为实际的服务端 IP 地址。

### 步骤 4: 执行部署脚本

```bash
bash run_e2e.sh
```

该脚本会自动完成所有部署步骤，包括：
- 创建必要的目录结构
- 启动 Agent 容器
- 执行健康检查

### 步骤 5: 验证部署

部署完成后，可通过以下方式验证：

1. **查看部署日志**: 检查 `run_e2e.sh` 执行日志，确认验证脚本输出全部正常。

2. **手动执行验证脚本**:
   ```bash
   bash e2e/client/05-verify.sh
   ```

## 验证部署

### 服务端验证

在服务端主机上执行：

```bash
cd e2e/server
bash 05-verify.sh
```

验证脚本会检查：
- Controller 服务是否正常运行
- Analyzer 服务是否正常运行
- 容器健康状态

### 客户端验证

在每台客户端主机上执行：

```bash
cd e2e/client
bash 05-verify.sh
```

验证脚本会检查：
- Agent 服务是否正常运行
- Agent 与 Controller 的连接状态
- 容器健康状态
