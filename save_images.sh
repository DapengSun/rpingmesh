#!/bin/bash

# 保存已构建的镜像到指定目录（tar.gz）
set -e

# 支持保存单个镜像：
# 用法:
#   ./save_images.sh <输出目录> [agent|controller|rqlite|analyzer|otel-collector|prometheus|simulator|grafana|all]

# 镜像名称与标签（与各 build.sh 保持一致）
AGENT_IMAGE="rpingmesh-agent:latest"
CONTROLLER_IMAGE="rpingmesh-controller:latest"
RQLITE_IMAGE="rpingmesh-rqlite:latest"
ANALYZER_IMAGE="rpingmesh-analyzer:latest"
OTEL_COLLECTOR_IMAGE="rpingmesh-otel-collector:latest"
PROMETHEUS_IMAGE="rpingmesh-prometheus:latest"
SIMULATOR_IMAGE="rpingmesh-agent-simulator:latest"
GRAFANA_IMAGE="rpingmesh-grafana:latest"

usage() {
	echo "用法: $0 <输出目录> [all|agent|controller|rqlite|analyzer|otel-collector|prometheus|simulator|grafana]"
	echo "示例: $0 /tmp/rpingmesh-images"
	echo "     $0 /tmp/rpingmesh-images prometheus"
}

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
	echo "错误: 参数数量不正确。"
	usage
	exit 1
fi

OUT_DIR="$1"
TARGET="${2:-all}"

mkdir -p "$OUT_DIR"

echo "保存镜像到目录: $OUT_DIR"

save_one() {
	local image="$1"
	local outfile="$2"
	if docker image inspect "$image" > /dev/null 2>&1; then
		echo "- 保存 $image -> $outfile"
		local tmpfile="$outfile.tmp"
		docker save "$image" | gzip > "$tmpfile"
		mv "$tmpfile" "$outfile"
	else
		echo "! 跳过: 镜像不存在 -> $image"
	fi
}

save_all() {
	save_one "$AGENT_IMAGE"          "$OUT_DIR/agent.tar.gz"
	save_one "$CONTROLLER_IMAGE"     "$OUT_DIR/controller.tar.gz"
	save_one "$RQLITE_IMAGE"         "$OUT_DIR/rqlite.tar.gz"
	save_one "$ANALYZER_IMAGE"       "$OUT_DIR/analyzer.tar.gz"
	save_one "$OTEL_COLLECTOR_IMAGE" "$OUT_DIR/otel-collector.tar.gz"
	save_one "$PROMETHEUS_IMAGE"     "$OUT_DIR/prometheus.tar.gz"
	save_one "$SIMULATOR_IMAGE"      "$OUT_DIR/agent-simulator.tar.gz"
	save_one "$GRAFANA_IMAGE"        "$OUT_DIR/grafana.tar.gz"
}

case "$TARGET" in
	all)
		save_all
		;;
	agent)
		save_one "$AGENT_IMAGE" "$OUT_DIR/agent.tar.gz"
		;;
	controller)
		save_one "$CONTROLLER_IMAGE" "$OUT_DIR/controller.tar.gz"
		;;
	rqlite)
		save_one "$RQLITE_IMAGE" "$OUT_DIR/rqlite.tar.gz"
		;;
	analyzer)
		save_one "$ANALYZER_IMAGE" "$OUT_DIR/analyzer.tar.gz"
		;;
	otel-collector)
		save_one "$OTEL_COLLECTOR_IMAGE" "$OUT_DIR/otel-collector.tar.gz"
		;;
	prometheus)
		save_one "$PROMETHEUS_IMAGE" "$OUT_DIR/prometheus.tar.gz"
		;;
	simulator)
		save_one "$SIMULATOR_IMAGE" "$OUT_DIR/agent-simulator.tar.gz"
		;;
	grafana)
		save_one "$GRAFANA_IMAGE" "$OUT_DIR/grafana.tar.gz"
		;;
	*)
		echo "未知的保存目标: $TARGET"
		usage
		exit 1
		;;
 esac
 
 echo "镜像保存完成。"
