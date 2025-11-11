FROM ubuntu:22.04

RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --fix-missing \
    ca-certificates \
    tzdata \
    bash \
    curl \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

ARG BUILD_UID=2133
ARG BUILD_GID=2015
ENV BUILD_UID=${BUILD_UID} \
    BUILD_GID=${BUILD_GID} \
    BUILD_USER=rpingmesh \
    BUILD_GROUP=rpingmesh \
    BUILD_HOME=/home/rpingmesh

RUN groupadd -g ${BUILD_GID} ${BUILD_GROUP} && \
    useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -s /bin/bash -d ${BUILD_HOME} ${BUILD_USER}

WORKDIR /app

COPY simulator /usr/local/bin/simulator
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/simulator /usr/local/bin/start.sh

RUN mkdir -p /app/config

ENTRYPOINT ["/usr/local/bin/start.sh"]

