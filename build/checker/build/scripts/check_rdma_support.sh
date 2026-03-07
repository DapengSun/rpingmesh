#!/bin/bash

echo "=== RDMA环境检测脚本 ==="
echo

# 1. 检查RDMA设备
echo "1. 检查RDMA设备列表:"
if command -v ibv_devices &> /dev/null; then
    ibv_devices
else
    echo "   ibv_devices 命令未找到，尝试其他方法..."
    ls /dev/infiniband/ 2>/dev/null || echo "   /dev/infiniband/ 目录不存在"
fi
echo

# 2. 检查RDMA驱动
echo "2. 检查RDMA驱动模块:"
lsmod | grep -E "(ib_|rdma|mlx)" || echo "   未找到RDMA相关驱动模块"
echo

# 3. 检查InfiniBand设备
echo "3. 检查InfiniBand设备:"
if command -v ibstat &> /dev/null; then
    ibstat
else
    echo "   ibstat 命令未找到"
    # 尝试检查设备文件
    ls /sys/class/infiniband/ 2>/dev/null || echo "   /sys/class/infiniband/ 目录不存在"
fi
echo

# 4. 检查RoCE支持
echo "4. 检查RoCE支持:"
if command -v ibv_devinfo &> /dev/null; then
    echo "   使用ibv_devinfo检查设备信息:"
    ibv_devinfo
else
    echo "   ibv_devinfo 命令未找到"
fi
echo

# 5. 检查RDMA库
echo "5. 检查RDMA库文件:"
ldconfig -p | grep -E "(libibverbs|libmlx|librdma)" || echo "   未找到RDMA相关库文件"
echo

# 6. 检查网络接口
echo "6. 检查网络接口:"
ip link show | grep -E "(ib|mlx|roce)" || echo "   未找到RDMA相关网络接口"
echo

# 7. 检查内核版本和RDMA支持
echo "7. 检查内核RDMA支持:"
uname -r
ls /lib/modules/$(uname -r)/kernel/drivers/infiniband/ 2>/dev/null || echo "   内核中未找到InfiniBand驱动"
echo

echo "=== 检测完成 ==="
