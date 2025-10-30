FROM ubuntu:22.04

# 运行时依赖、supervisor与SSH
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --fix-missing \
    ca-certificates \
    supervisor \
    openssh-server \
    libibverbs1 \
    librdmacm1 \
    bash vim net-tools iputils-ping curl wget htop \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/supervisor /etc/supervisor/conf.d /var/run/sshd /app

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


