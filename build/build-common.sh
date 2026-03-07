#!/bin/bash
# 架构检测和配置脚本

# 支持的架构
SUPPORTED_ARCHES="amd64 arm64"

# 检测当前系统架构
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "amd64" ;;  # 默认
    esac
}

# 架构到 Go 架构名称映射
go_arch() {
    case "$1" in
        amd64) echo "amd64" ;;
        arm64) echo "arm64" ;;
        *) echo "amd64" ;;
    esac
}

# 架构到下载包架构名称映射
pkg_arch() {
    case "$1" in
        amd64) echo "amd64" ;;
        arm64) echo "arm64" ;;
        *) echo "amd64" ;;
    esac
}

# grpcurl 架构名称映射
grpcurl_arch() {
    case "$1" in
        amd64) echo "linux_x86_64" ;;
        arm64) echo "linux_arm64" ;;
        *) echo "linux_x86_64" ;;
    esac
}

# rqlite 架构名称映射
rqlite_arch() {
    case "$1" in
        amd64) echo "linux-amd64" ;;
        arm64) echo "linux-arm64" ;;
        *) echo "linux-amd64" ;;
    esac
}

# 导出架构变量
export TARGET_ARCH=${TARGET_ARCH:-$(detect_arch)}
export GO_ARCH=$(go_arch "$TARGET_ARCH")
export PKG_ARCH=$(pkg_arch "$TARGET_ARCH")
export GRPCURL_ARCH=$(grpcurl_arch "$TARGET_ARCH")
export RQLITE_ARCH=$(rqlite_arch "$TARGET_ARCH")
export OTELCOL_ARCH=$PKG_ARCH

# Docker 平台参数
export DOCKER_PLATFORM="linux/${TARGET_ARCH}"

