# Rpingmesh E2E 部署指南

本文档介绍如何在 RDMA 集群中部署 Rpingmesh 的服务端和客户端组件。所有组件均已容器化，部署前需要先构建或导入 Docker 镜像。

## 目录

- [前置准备](#1-前置准备)
  - [1.1 拉取代码](#11-拉取代码)
  - [1.2 创建 rpingmesh 账户](#12-创建-rpingmesh-账户)
  - [1.3 镜像构建](#13-镜像构建在线环境已有镜像包可跳过该步骤)
  - [1.4 镜像导出与导入](#14-镜像导出与导入离线环境)
- [服务端部署](#2-服务端部署)
- [客户端部署](#3-客户端部署)
- [验证部署](#4-验证部署)

## 1. 前置准备

### 1.1 拉取代码
```bash
git clone -b refactor/build-deploy git@github.com:DapengSun/rpingmesh.git
```

### 1.2 创建 rpingmesh 账户

Rpingmesh 需要在服务端和客户端主机上创建专用的 `rpingmesh` 用户账户，默认 UID 和 GID 为 **1003:1003**。

**在服务端和客户端主机上执行以下命令：**

```bash
# 检查 UID 1003 是否已被占用
if id -u 1003 &>/dev/null; then
    echo "警告: UID 1003 已被占用，需要重新构建镜像"
    exit 1
fi

# 检查 GID 1003 是否已被占用
if getent group 1003 &>/dev/null; then
    echo "警告: GID 1003 已被占用，需要重新构建镜像"
    exit 1
fi

# 创建 rpingmesh 组和用户
groupadd -g 1003 rpingmesh
useradd -m -u 1003 -g 1003 -s /bin/bash -d /home/rpingmesh rpingmesh
```

> **重要说明**:
> - 如果 UID 1003 或 GID 1003 已被占用，需要使用其他 UID:GID 重新构建镜像（参考 [1.3 镜像构建](#13-镜像构建在线环境已有镜像包可跳过该步骤) 章节）
> - 必须在**所有**服务端和客户端主机上创建该账户
> - 账户创建完成后，确保该账户对 RDMA 设备有适当的访问权限
> - 如果使用了自定义 UID:GID 构建镜像，请确保在所有主机上使用相同的 UID:GID 创建账户

### 1.3 镜像构建（在线环境，已有镜像包可跳过该步骤）

如果部署环境可以访问 Docker Hub，可以直接构建镜像。默认构建的镜像使用 UID:GID **1003:1003**。

**使用默认 UID:GID (1003:1003) 构建：**

```bash
cd ${PROJECT_ROOT}
bash ./build/build_images.sh
```

**如果 UID 1003 或 GID 1003 已被占用，需要指定其他 UID:GID 重新构建：**

```bash
cd ${PROJECT_ROOT}
bash ./build/build_images.sh --uid <自定义UID> --gid <自定义GID>
```

**示例：使用 UID 2000 和 GID 2000 构建：**

```bash
bash ./build/build_images.sh --uid 2000 --gid 2000
```

**仅构建特定组件：**

```bash
# 构建所有组件（默认）
bash ./build/build_images.sh all

# 构建指定组件
bash ./build/build_images.sh agent --uid 1003 --gid 1003
bash ./build/build_images.sh controller --uid 1003 --gid 1003
bash ./build/build_images.sh analyzer --uid 1003 --gid 1003
```

> **注意**: 
> - `${PROJECT_ROOT}` 为项目根目录路径
> - 如果使用自定义 UID:GID，请确保在所有部署主机上创建对应的账户（UID 和 GID 需与构建时指定的一致）
> - 构建完成后，镜像中的 `rpingmesh` 用户将使用指定的 UID:GID

### 1.4 镜像导出与导入（离线环境）

如果部署环境无法访问网络，需要先在在线环境导出镜像，然后在离线环境导入：

**1. 在在线环境导出镜像：**

```bash
cd ${PROJECT_ROOT}

# images 为导出镜像的存放目录
bash ./build/save_images.sh images
```

**2. 在离线环境导入镜像：**

```bash
# 导入导出的镜像文件
docker load -i images/xxx.tar.gz
```

> **提示**: 如果镜像已构建或导入，可跳过此步骤。

## 2. 服务端部署

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

## 3. 客户端部署

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
controller-addr: "$server_ip:50051"          # Controller gRPC 地址，将 IP 改为服务端 IP
analyzer-addr: "$server_ip:50052"            # Analyzer gRPC 地址，将 IP 改为服务端 IP
otel-collector-addr: "grpc://$server_ip:4317" # OpenTelemetry Collector 地址，将 IP 改为服务端 IP
```

> **重要**: 请确保将上述配置中的 `{$server_ip}` 替换为实际的服务端 IP 地址。

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

## 4. 验证部署

完成服务端和客户端的部署后，可以通过以下方式验证系统是否正常运行：

### 4.1 访问监控 Dashboard

服务端部署完成后，Grafana Dashboard 会运行在服务端的 **3000 端口**上。您可以通过 SSH 端口映射将服务端的 3000 端口映射到本地，然后在本地浏览器中访问 Dashboard。

**1. 建立 SSH 端口映射：**

在本地机器上执行以下命令，将服务端的 3000 端口映射到本地的 3000 端口：

```bash
ssh -L 3000:localhost:3000 user@server_ip
```

> **说明**: 
> - `user@server_ip` 替换为实际的 SSH 用户名和服务端 IP 地址
> - 如果需要映射到本地其他端口，可以使用 `-L local_port:localhost:3000` 的格式

**2. 访问 Dashboard：**

保持 SSH 连接开启，在本地浏览器中访问：

```
http://localhost:3000
```

默认账户密码：admin/admin

### 4.2 等待数据采集

部署完成后，系统需要一定时间进行数据采集和处理。**建议在部署完客户端和服务端后，等待 1~2 分钟**，让 Agent 完成初始数据上报和 Controller/Analyzer 完成数据处理。

### 4.3 观察数据

等待时间过后，在 Dashboard 中观察以下内容，确认系统运行正常：

- **Agent 连接状态**: 检查所有部署了客户端的节点是否正常连接到 Controller
- **RDMA 性能指标**: 观察延迟、吞吐量等 RDMA 性能数据是否正常采集
- **网络拓扑**: 确认节点间的网络连接关系是否正常显示
- **时间序列数据**: 检查各项指标是否有持续的数据更新

如果所有指标都正常显示且有数据更新，说明部署成功，系统运行正常。
