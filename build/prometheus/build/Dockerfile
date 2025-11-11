FROM ubuntu/prometheus:3-24.04_stable

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

# 内网 apt 源配置
RUN if [ "$USE_INTRANET" = "true" ]; then \
        echo "Configuring intranet apt sources..." && \
        cp /etc/apt/sources.list /etc/apt/sources.list.bak && \
        echo "deb [trusted=yes] http://10.68.64.1/ubuntu2204/ jammy main" > /etc/apt/sources.list && \
        echo 'Acquire::https::Verify-Peer "false";' > /etc/apt/apt.conf.d/99disable-ssl-check && \
        echo 'Acquire::https::Verify-Host "false";' >> /etc/apt/apt.conf.d/99disable-ssl-check; \
    else \
        echo "Configuring fast apt sources for external network..." && \
        find /etc/apt -name "sources.list*" -exec sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' {} \; && \
        find /etc/apt -name "sources.list*" -exec sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' {} \; && \
        echo "deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse" > /etc/apt/sources.list && \
        echo "deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
        echo "deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list; \
    fi

# 验证源配置并安装常用工具
RUN echo "=== Current apt sources ===" && \
    cat /etc/apt/sources.list && \
    echo "=== Updating package list ===" && \
    apt-get update && \
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
RUN mkdir -p ${PROMETHEUS_BASE_PATH}/config \
    && mkdir -p ${PROMETHEUS_BASE_PATH}/data \
    && mkdir -p ${PROMETHEUS_BASE_PATH}/rules \
    && mkdir -p ${PROMETHEUS_BASE_PATH}/targets \
    && chown -R ${BUILD_UID}:${BUILD_GID} ${PROMETHEUS_BASE_PATH} \
    && rm -rf /prometheus \
    && ln -s ${PROMETHEUS_BASE_PATH}/data /prometheus

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
