FROM ubuntu:22.04

# 配置清华镜像源并安装运行时依赖、supervisor和SSH
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --fix-missing \
    wget \
    ca-certificates \
    supervisor \
    openssh-server \
    bash \
    vim \
    net-tools \
    iputils-ping \
    curl \
    htop \
    && rm -rf /var/lib/apt/lists/*

# 下载并安装RQLite
RUN wget -O /tmp/rqlite.tar.gz https://github.com/rqlite/rqlite/releases/download/v8.37.0/rqlite-v8.37.0-linux-amd64.tar.gz && \
    tar -xzf /tmp/rqlite.tar.gz -C /tmp && \
    cp /tmp/rqlite-v8.37.0-linux-amd64/rqlited /usr/local/bin/ && \
    cp /tmp/rqlite-v8.37.0-linux-amd64/rqlite /usr/local/bin/ && \
    rm -rf /tmp/rqlite* && \
    chmod +x /usr/local/bin/rqlited /usr/local/bin/rqlite

# 创建必要的目录
RUN mkdir -p /var/log/supervisor /etc/supervisor/conf.d /var/run/sshd /data

# 配置SSH
RUN echo 'root:rpingmesh' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config && \
    echo 'Port 22' >> /etc/ssh/sshd_config && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

WORKDIR /data

# 复制supervisor配置
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY rqlite.conf /etc/supervisor/conf.d/rqlite.conf

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
COPY status.sh /usr/local/bin/status.sh

# 设置执行权限
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/status.sh

# 暴露端口
EXPOSE 4001 4002 22

# 设置环境变量
ENV NODE_ID=rqlite-node

# 设置入口点
ENTRYPOINT ["/usr/local/bin/start.sh"]
