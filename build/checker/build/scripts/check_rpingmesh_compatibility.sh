#!/bin/bash

echo "=== R-Pingmesh兼容性检测 ==="
echo

# 1. 检查Go环境
echo "1. 检查Go环境:"
if command -v go &> /dev/null; then
    go version
    echo "   Go环境: [OK] 已安装"
else
    echo "   Go环境: [FAIL] 未安装"
fi
echo

# 2. 检查RDMA库
echo "2. 检查RDMA库:"
if ldconfig -p | grep -q libibverbs; then
    echo "   libibverbs: [OK] 已安装"
else
    echo "   libibverbs: [FAIL] 未安装"
fi

if ldconfig -p | grep -q librdmacm; then
    echo "   librdmacm: [OK] 已安装"
else
    echo "   librdmacm: [FAIL] 未安装"
fi
echo

# 3. 检查eBPF支持
echo "3. 检查eBPF支持:"
if [ -d /sys/fs/bpf ]; then
    echo "   eBPF文件系统: [OK] 已挂载"
else
    echo "   eBPF文件系统: [FAIL] 未挂载"
fi

if [ -d /sys/kernel/debug/tracing ]; then
    echo "   debugfs: [OK] 已挂载"
else
    echo "   debugfs: [FAIL] 未挂载"
fi
echo

# 4. 检查Docker环境
echo "4. 检查Docker环境:"
if command -v docker &> /dev/null; then
    docker --version
    echo "   Docker: [OK] 已安装"
    
    # 检查特权模式支持
    if docker run --rm --privileged hello-world &> /dev/null; then
        echo "   特权模式: [OK] 支持"
    else
        echo "   特权模式: [FAIL] 不支持"
    fi
else
    echo "   Docker: [FAIL] 未安装"
fi
echo

# 5. 检查网络配置
echo "5. 检查网络配置:"
if command -v ip &> /dev/null; then
    echo "   网络工具: [OK] 已安装"
    ip link show | head -5
else
    echo "   网络工具: [FAIL] 未安装"
fi
echo

# 6. 检查权限
echo "6. 检查权限:"
if [ "$EUID" -eq 0 ]; then
    echo "   运行权限: [OK] root用户"
else
    echo "   运行权限: [WARN] 非root用户"
    echo "   建议: 使用sudo运行或确保用户有足够权限"
fi
echo

echo "=== 兼容性检测完成 ==="
