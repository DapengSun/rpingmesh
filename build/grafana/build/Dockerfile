FROM grafana/grafana:11.1.0

USER root

# 安装必要的工具
RUN apk add --no-cache \
        supervisor \
        net-tools \
        iputils \
        vim \
        bash

# supervisor 日志目录
RUN mkdir -p /var/log/supervisor

# 设置 Grafana 基础路径环境变量
ENV GRAFANA_BASE_PATH=/private/rpingmesh/grafana \
    GF_PATHS_DATA=/private/rpingmesh/grafana/data \
    GF_PATHS_LOGS=/private/rpingmesh/grafana/logs \
    GF_PATHS_PLUGINS=/private/rpingmesh/grafana/plugins \
    GF_PATHS_PROVISIONING=/private/rpingmesh/grafana/provisioning

# 创建基本目录结构
RUN mkdir -p ${GRAFANA_BASE_PATH}/data \
    && mkdir -p ${GRAFANA_BASE_PATH}/logs \
    && mkdir -p ${GRAFANA_BASE_PATH}/plugins \
    && mkdir -p ${GRAFANA_BASE_PATH}/provisioning/datasources \
    && mkdir -p ${GRAFANA_BASE_PATH}/provisioning/dashboards \
    && mkdir -p ${GRAFANA_BASE_PATH}/config \
    && chown -R 472:472 ${GRAFANA_BASE_PATH}

# 复制配置文件到容器内临时位置
COPY grafana.ini /tmp/grafana.ini
COPY datasources/datasources.yml /tmp/datasources.yml
COPY dashboards/dashboards.yml /tmp/dashboards.yml
COPY dashboards/default_dashboard.json /tmp/default_dashboard.json

RUN chown -R 472:472 ${GRAFANA_BASE_PATH}

# supervisor 配置
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 启动脚本
COPY start-grafana-supervised.sh /usr/local/bin/start-grafana-supervised.sh
RUN chmod +x /usr/local/bin/start-grafana-supervised.sh

USER root

EXPOSE 3000

ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf", "-n"]
