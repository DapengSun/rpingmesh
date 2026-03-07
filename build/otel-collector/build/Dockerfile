FROM ubuntu:22.04

RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --fix-missing \
    ca-certificates \
    supervisor \
    openssh-server \
    bash \
    vim \
    net-tools \
    iputils-ping \
    curl \
    wget \
    htop \
    telnet \
    netcat-openbsd \
    iproute2 \
    dnsutils \
    coreutils \
    procps \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

ARG BUILD_UID=2133
ARG BUILD_GID=2015
ENV BUILD_UID=${BUILD_UID} \
    BUILD_GID=${BUILD_GID} \
    BUILD_USER=rpingmesh \
    BUILD_GROUP=rpingmesh \
    BUILD_HOME=/home/rpingmesh

RUN groupadd -g ${BUILD_GID} ${BUILD_GROUP} && \
    useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -s /bin/bash -d ${BUILD_HOME} ${BUILD_USER}

# 下载并安装 OpenTelemetry Collector Contrib
# 注意：必须使用 otelcol-contrib（不是 otelcol），因为需要 file_storage 等扩展
# otelcol-contrib 包含所有核心功能 + 社区贡献的扩展（如 file_storage）
ARG OTELCOL_VERSION=0.139.0
ARG OTELCOL_ARCH=amd64
RUN curl -L -o /tmp/otelcol-contrib.tar.gz \
    "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTELCOL_VERSION}/otelcol-contrib_${OTELCOL_VERSION}_linux_${OTELCOL_ARCH}.tar.gz" && \
    tar -xzf /tmp/otelcol-contrib.tar.gz -C /tmp && \
    mv /tmp/otelcol-contrib /usr/local/bin/otelcol && \
    chmod +x /usr/local/bin/otelcol && \
    rm -f /tmp/otelcol-contrib.tar.gz && \
    /usr/local/bin/otelcol --version

RUN mkdir -p /var/log/supervisor /etc/supervisor/conf.d /var/run/sshd /app/config /app/data

# 配置SSH
RUN echo 'root:rpingmesh' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config && \
    echo 'Port 22' >> /etc/ssh/sshd_config && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

WORKDIR /app

# 验证 otelcol 已正确安装
RUN /usr/local/bin/otelcol --version || (echo "Error: otelcol binary not found or not executable" && exit 1)

# 复制配置文件到系统目录（用于示例配置）
RUN mkdir -p /usr/local/share
COPY otel-collector-config.yaml.example /usr/local/share/otel-collector-config.yaml.example

COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY otel-collector.conf /etc/supervisor/conf.d/otel-collector.conf

# 创建SSH启动脚本
RUN echo '#!/bin/bash' > /etc/init.d/ssh-start && \
    echo 'echo "启动SSH服务..."' >> /etc/init.d/ssh-start && \
    echo '/usr/sbin/sshd -D &' >> /etc/init.d/ssh-start && \
    echo 'echo "SSH服务已启动，端口22"' >> /etc/init.d/ssh-start && \
    echo 'echo "SSH登录: ssh root@<container_ip> -p 22"' >> /etc/init.d/ssh-start && \
    echo 'echo "密码: rpingmesh"' >> /etc/init.d/ssh-start && \
    chmod +x /etc/init.d/ssh-start

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# 暴露端口
EXPOSE 4317 4318 8889 55679 22

ENTRYPOINT ["/usr/local/bin/start.sh"]

