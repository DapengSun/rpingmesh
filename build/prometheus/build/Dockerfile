FROM ubuntu/prometheus:2.33-22.04_beta

USER root

ARG BUILD_UID=2133
ARG BUILD_GID=2015
ENV BUILD_UID=${BUILD_UID} \
    BUILD_GID=${BUILD_GID} \
    BUILD_USER=rpingmesh \
    BUILD_GROUP=rpingmesh \
    BUILD_HOME=/home/rpingmesh

RUN groupadd -g ${BUILD_GID} ${BUILD_GROUP} && \
    useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -s /bin/bash -d ${BUILD_HOME} ${BUILD_USER}

ARG USE_INTRANET=false
ARG TARGETARCH=amd64

# 内网 apt 源配置
RUN if [ "$USE_INTRANET" = "true" ]; then \
        echo "Configuring intranet apt sources..." && \
        cp /etc/apt/sources.list /etc/apt/sources.list.bak && \
        echo "deb [trusted=yes] http://10.68.64.1/ubuntu2204/ jammy main" > /etc/apt/sources.list && \
        echo 'Acquire::https::Verify-Peer "false";' > /etc/apt/apt.conf.d/99disable-ssl-check && \
        echo 'Acquire::https::Verify-Host "false";' >> /etc/apt/apt.conf.d/99disable-ssl-check; \
    else \
        echo "Configuring fast apt sources for external network..." && \
        # 根据架构选择合适的镜像源（ARM64 使用清华源，AMD64 使用阿里云源） \
        if [ "$TARGETARCH" = "arm64" ]; then \
            echo "Using Tsinghua mirror for ARM64..." && \
            # 备份原始源列表 \
            cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true && \
            # 替换为清华源 \
            sed -i 's|http://archive.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list 2>/dev/null || true && \
            sed -i 's|http://security.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list 2>/dev/null || true && \
            sed -i 's|https://archive.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list 2>/dev/null || true && \
            sed -i 's|https://security.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list 2>/dev/null || true && \
            # 如果 sources.list 不存在或为空，创建新的源列表 \
            if [ ! -s /etc/apt/sources.list ]; then \
                echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse" > /etc/apt/sources.list && \
                echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
                echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list; \
            fi; \
        else \
            echo "Using Aliyun mirror for AMD64..." && \
            find /etc/apt -name "sources.list*" -exec sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' {} \; 2>/dev/null || true && \
            find /etc/apt -name "sources.list*" -exec sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' {} \; 2>/dev/null || true && \
            echo "deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse" > /etc/apt/sources.list && \
            echo "deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
            echo "deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list; \
        fi; \
    fi

# 验证源配置并安装常用工具
RUN echo "=== Current apt sources ===" && \
    cat /etc/apt/sources.list && \
    echo "=== Updating package list ===" && \
    apt-get update || (echo "apt-get update failed, retrying with default sources..." && \
        rm -f /etc/apt/sources.list.d/* && \
        echo "deb http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse" > /etc/apt/sources.list && \
        echo "deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
        echo "deb http://archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list && \
        apt-get update) && \
    echo "=== Installing packages ===" && \
    apt-get install -y --no-install-recommends \
        supervisor \
        net-tools \
        inetutils-ping \
        vim \
        python3 \
        python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 如果是部署环境替换 apt 源
RUN if [ "$USE_INTRANET" = "true" ]; then \
    echo "deb [trusted=yes] https://10.92.132.52/mirrors/ubuntu2204/ jammy main" > /etc/apt/sources.list; \
    fi

# supervisor 日志目录
RUN mkdir -p /var/log/supervisor

# 设置 Prometheus 基础路径环境变量
ENV PROMETHEUS_BASE_PATH=/private/rpingmesh/prometheus

# 创建目录结构
# 预先创建 /prometheus 目录（作为普通目录），避免基础镜像启动时创建失败
RUN mkdir -p ${PROMETHEUS_BASE_PATH}/config \
    && mkdir -p ${PROMETHEUS_BASE_PATH}/data \
    && mkdir -p ${PROMETHEUS_BASE_PATH}/rules \
    && mkdir -p ${PROMETHEUS_BASE_PATH}/targets \
    && mkdir -p /prometheus \
    && chown -R ${BUILD_UID}:${BUILD_GID} ${PROMETHEUS_BASE_PATH} \
    && chown -R ${BUILD_UID}:${BUILD_GID} /prometheus

# supervisor 配置
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 启动脚本
COPY start-prometheus-supervised.sh /usr/local/bin/start-prometheus-supervised.sh
RUN chmod +x /usr/local/bin/start-prometheus-supervised.sh && \
    chown ${BUILD_UID}:${BUILD_GID} /usr/local/bin/start-prometheus-supervised.sh

COPY prometheus.yml /etc/prometheus/prometheus.yml

USER root

EXPOSE 9090

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf", "-n"]
