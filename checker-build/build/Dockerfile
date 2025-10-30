FROM ubuntu:22.04

# 基础与镜像源
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --fix-missing \
    ca-certificates \
    supervisor \
    bash \
    curl \
    wget \
    vim \
    net-tools \
    iputils-ping \
    traceroute \
    tcpdump \
    jq \
    tree \
    less \
    rdma-core \
    ibverbs-utils \
    infiniband-diags \
    librdmacm1 \
    libibverbs1 \
    pciutils \
    lshw \
    dmidecode \
    && rm -rf /var/lib/apt/lists/*

# 目录
RUN mkdir -p /var/log/supervisor /etc/supervisor/conf.d /app/scripts /data
WORKDIR /app

# 复制supervisor配置与启动脚本
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY checker.conf /etc/supervisor/conf.d/checker.conf
COPY start.sh /usr/local/bin/start.sh

# 复制检测脚本
COPY scripts/ /app/scripts/

# 权限
RUN chmod +x /usr/local/bin/start.sh && chmod +x /app/scripts/*.sh || true

# 暴露端口（通常不需要对外端口，保留为空）

ENTRYPOINT ["/usr/local/bin/start.sh"]
