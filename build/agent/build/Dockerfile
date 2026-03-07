FROM ubuntu:22.04

RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --fix-missing \
    ca-certificates \
    supervisor \
    openssh-server \
    libibverbs1 \
    librdmacm1 \
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
    unzip \
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

# Install grpcurl for gRPC testing
ARG GRPCURL_VERSION=1.8.9
ARG GRPCURL_ARCH=linux_x86_64
RUN wget -q "https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_${GRPCURL_ARCH}.tar.gz" -O /tmp/grpcurl.tar.gz && \
    tar -xzf /tmp/grpcurl.tar.gz -C /tmp && \
    mv /tmp/grpcurl /usr/local/bin/grpcurl && \
    chmod +x /usr/local/bin/grpcurl && \
    rm -rf /tmp/grpcurl* && \
    grpcurl --version

# Verify critical tools are installed and available
RUN command -v nc >/dev/null && \
    command -v telnet >/dev/null && \
    command -v nslookup >/dev/null && \
    command -v ping >/dev/null && \
    command -v curl >/dev/null && \
    command -v timeout >/dev/null && \
    command -v bash >/dev/null && \
    command -v grpcurl >/dev/null

RUN mkdir -p /var/log/supervisor /etc/supervisor/conf.d /var/run/sshd /app/config /app/data

# SSH配置
RUN echo 'root:rpingmesh' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config && \
    echo 'Port 22' >> /etc/ssh/sshd_config && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

WORKDIR /app

# 二进制放置到不会被覆盖的路径
COPY agent /usr/local/bin/agent

# supervisor配置
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY agent.conf /etc/supervisor/conf.d/agent.conf

# SSH启动脚本
RUN echo '#!/bin/bash' > /etc/init.d/ssh-start && \
    echo 'echo "启动SSH服务..."' >> /etc/init.d/ssh-start && \
    echo '/usr/sbin/sshd -D &' >> /etc/init.d/ssh-start && \
    echo 'echo "SSH服务已启动，端口22"' >> /etc/init.d/ssh-start && \
    echo 'echo "SSH登录: ssh root@<container_ip> -p 22"' >> /etc/init.d/ssh-start && \
    echo 'echo "密码: rpingmesh"' >> /etc/init.d/ssh-start && \
    chmod +x /etc/init.d/ssh-start

# 启动脚本放置到不会被覆盖的路径
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/start.sh"]
