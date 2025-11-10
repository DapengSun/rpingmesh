#!/bin/bash

echo "=== 快速RDMA功能测试 ==="
echo

# 1. 测试RDMA设备发现
echo "1. 测试RDMA设备发现:"
if command -v ibv_devices &> /dev/null; then
    echo "   设备列表:"
    ibv_devices
    echo
    echo "   设备数量: $(ibv_devices | wc -l)"
else
    echo "   ❌ ibv_devices 命令不可用"
fi
echo

# 2. 测试设备信息获取
echo "2. 测试设备信息获取:"
if command -v ibv_devinfo &> /dev/null; then
    echo "   设备详细信息:"
    ibv_devinfo
else
    echo "   ❌ ibv_devinfo 命令不可用"
fi
echo

# 3. 测试端口状态
echo "3. 测试端口状态:"
if command -v ibstat &> /dev/null; then
    echo "   端口状态:"
    ibstat
else
    echo "   ❌ ibstat 命令不可用"
fi
echo

# 4. 测试RoCE配置
echo "4. 测试RoCE配置:"
if [ -f /sys/class/infiniband/*/ports/*/gid_attrs/types ]; then
    echo "   GID类型支持:"
    cat /sys/class/infiniband/*/ports/*/gid_attrs/types 2>/dev/null | head -5
else
    echo "   ❌ 无法读取GID类型信息"
fi
echo

# 5. 测试网络连通性
echo "5. 测试网络连通性:"
if command -v ibping &> /dev/null; then
    echo "   尝试本地ping测试..."
    timeout 5 ibping -S 2>/dev/null || echo "   ❌ ibping 测试失败"
else
    echo "   ❌ ibping 命令不可用"
fi
echo

echo "=== 测试完成 ==="
