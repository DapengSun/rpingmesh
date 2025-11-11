#!/bin/bash

# 分离式构建脚本 - 构建Agent、Controller、RQLite、Analyzer、OpenTelemetry Collector等镜像
set -e

BUILD_ROOT="$(cd "$(dirname "$0")" && pwd)"

BUILD_TARGET="all"
BUILD_UID=${BUILD_UID:-2133}
BUILD_GID=${BUILD_GID:-2015}

while [ $# -gt 0 ]; do
    case "$1" in
        all|agent|controller|rqlite|analyzer|otel-collector|prometheus|simulator|grafana)
            BUILD_TARGET="$1"
            shift
            ;;
        --uid)
            if [ -n "${2:-}" ]; then
                BUILD_UID="$2"
                shift 2
            else
                echo "错误: --uid 需要一个参数" >&2
                exit 1
            fi
            ;;
        --uid=*)
            BUILD_UID="${1#*=}"
            shift
            ;;
        --gid)
            if [ -n "${2:-}" ]; then
                BUILD_GID="$2"
                shift 2
            else
                echo "错误: --gid 需要一个参数" >&2
                exit 1
            fi
            ;;
        --gid=*)
            BUILD_GID="${1#*=}"
            shift
            ;;
        *)
            echo "未知参数: $1" >&2
            echo "用法: $0 [构建目标] [--uid UID] [--gid GID]" >&2
            exit 1
            ;;
    esac
done

export BUILD_UID BUILD_GID

build_agent() {
    echo "构建Agent镜像..."
    bash "$BUILD_ROOT"/agent/build.sh
}

build_controller() {
    echo "构建Controller镜像..."
    bash "$BUILD_ROOT"/controller/build.sh
}

build_rqlite() {
    echo "构建RQLite镜像..."
    bash "$BUILD_ROOT"/rqlite/build.sh
}

build_analyzer() {
    echo "构建Analyzer镜像..."
    bash "$BUILD_ROOT"/analyzer/build.sh
}

build_otel_collector() {
    echo "构建OpenTelemetry Collector镜像..."
    bash "$BUILD_ROOT"/otel-collector/build.sh
}

build_prometheus() {
    echo "构建Prometheus镜像..."
    bash "$BUILD_ROOT"/prometheus/build.sh
}

build_simulator() {
    echo "构建Agent Simulator镜像..."
    bash "$BUILD_ROOT"/simulator/build.sh
}

build_grafana() {
    echo "构建Grafana镜像..."
    bash "$BUILD_ROOT"/grafana/build.sh
}

build_all() {
    build_agent
    echo "=================================================="
    build_controller
    echo "=================================================="
    build_rqlite
    echo "=================================================="
    build_analyzer
    echo "=================================================="
    build_otel_collector
    echo "=================================================="
    build_prometheus
    echo "=================================================="
    build_simulator
    echo "=================================================="
    build_grafana
}

case "$BUILD_TARGET" in
    all)
        echo "开始构建所有R-Pingmesh镜像..."
        build_all
        ;;
    agent)
        build_agent
        ;;
    controller)
        build_controller
        ;;
    rqlite)
        build_rqlite
        ;;
    analyzer)
        build_analyzer
        ;;
    otel-collector)
        build_otel_collector
        ;;
    prometheus)
        build_prometheus
        ;;
    simulator)
        build_simulator
        ;;
    grafana)
        build_grafana
        ;;
    *)
        echo "未知的构建目标: $BUILD_TARGET"
        echo "可选值: all, agent, controller, rqlite, analyzer, otel-collector, prometheus, simulator, grafana"
        exit 1
        ;;
 esac
 
 echo
 echo "=================================================="
 echo
 echo "当前可用镜像:"
 docker images | grep rpingmesh || true
 
 echo
 echo "=================================================="
 echo
 echo "构建完成！"