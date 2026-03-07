FROM ubuntu:22.04

# 配置清华镜像源并安装运行时依赖、supervisor和SSH
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
    && rm -rf /var/lib/apt/lists/*

ARG BUILD_UID=2133
ARG BUILD_GID=2015
ENV BUILD_UID=${BUILD_UID} \
    BUILD_GID=${BUILD_GID} \
    BUILD_USER=rpingmesh \
    BUILD_GROUP=rpingmesh \
    BUILD_HOME=/home/rpingmesh

RUN groupadd -g ${BUILD_GID} ${BUILD_GROUP} && \
    useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -s /bin/bash -d ${BUILD_HOME} ${BUILD_USER}

# 创建必要的目录
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

# 复制Controller二进制文件到不会被覆盖的路径
COPY controller /usr/local/bin/controller

# 复制supervisor配置
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY controller.conf /etc/supervisor/conf.d/controller.conf

# 创建SSH启动脚本
RUN echo '#!/bin/bash' > /etc/init.d/ssh-start && \
    echo 'echo "启动SSH服务..."' >> /etc/init.d/ssh-start && \
    echo '/usr/sbin/sshd -D &' >> /etc/init.d/ssh-start && \
    echo 'echo "SSH服务已启动，端口22"' >> /etc/init.d/ssh-start && \
    echo 'echo "SSH登录: ssh root@<container_ip> -p 22"' >> /etc/init.d/ssh-start && \
    echo 'echo "密码: rpingmesh"' >> /etc/init.d/ssh-start && \
    chmod +x /etc/init.d/ssh-start

# 复制启动脚本到不会被覆盖的路径
COPY start.sh /usr/local/bin/start.sh

# 设置执行权限
RUN chmod +x /usr/local/bin/start.sh

# 暴露端口
EXPOSE 50051 22

ENTRYPOINT ["/usr/local/bin/start.sh"]
