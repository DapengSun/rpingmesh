#!/bin/bash

# 保存已构建的镜像到指定目录（tar.gz）
set -e

# 镜像名称与标签（与各 build.sh 保持一致）
AGENT_IMAGE="rpingmesh-agent:latest"
CONTROLLER_IMAGE="rpingmesh-controller:latest"
RQLITE_IMAGE="rpingmesh-rqlite:latest"
ANALYZER_IMAGE="rpingmesh-analyzer:latest"

usage() {
	echo "用法: $0 <输出目录>"
	echo "示例: $0 /tmp/rpingmesh-images"
}

if [ $# -ne 1 ]; then
	echo "错误: 需要提供输出目录。"
	usage
	exit 1
fi

OUT_DIR="$1"

mkdir -p "$OUT_DIR"

echo "保存镜像到目录: $OUT_DIR"

save_one() {
	local image="$1"
	local outfile="$2"
	if docker image inspect "$image" > /dev/null 2>&1; then
		echo "- 保存 $image -> $outfile"
		# 使用临时文件确保原子性
		local tmpfile="$outfile.tmp"
		docker save "$image" | gzip > "$tmpfile"
		mv "$tmpfile" "$outfile"
	else
		echo "! 跳过: 镜像不存在 -> $image"
	fi
}

save_one "$AGENT_IMAGE"     "$OUT_DIR/agent.tar.gz"
save_one "$CONTROLLER_IMAGE" "$OUT_DIR/controller.tar.gz"
save_one "$RQLITE_IMAGE"    "$OUT_DIR/rqlite.tar.gz"
save_one "$ANALYZER_IMAGE"  "$OUT_DIR/analyzer.tar.gz"

echo "镜像保存完成。"
