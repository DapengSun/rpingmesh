#!/bin/bash

echo "=== 增强版RDMA功能测试 ==="
echo

# 1. 详细的设备信息
echo "1. 详细设备信息:"
if command -v ibv_devices &> /dev/null; then
    echo "   设备列表:"
    ibv_devices
    echo
    
    # 获取每个设备的详细信息
    for dev in $(ibv_devices | tail -n +2 | awk '{print $1}'); do
        echo "   设备 $dev 详细信息:"
        ibv_devinfo -d $dev 2>/dev/null | head -20
        echo
    done
else
    echo "   [FAIL] ibv_devices 命令不可用"
fi

# 2. 端口状态检查
echo "2. 端口状态检查:"
if command -v ibstat &> /dev/null; then
    ibstat
else
    echo "   [FAIL] ibstat 命令不可用"
fi
echo

# 3. RoCE配置检查
echo "3. RoCE配置检查:"
if [ -d /sys/class/infiniband ]; then
    for dev in /sys/class/infiniband/*; do
        dev_name=$(basename $dev)
        echo "   设备 $dev_name:"
        for port in $dev/ports/*; do
            port_num=$(basename $port)
            echo "     端口 $port_num:"
            if [ -f $port/gid_attrs/types ]; then
                echo "       GID类型: $(cat $port/gid_attrs/types)"
            fi
            if [ -f $port/state ]; then
                echo "       状态: $(cat $port/state)"
            fi
            if [ -f $port/phys_state ]; then
                echo "       物理状态: $(cat $port/phys_state)"
            fi
        done
        echo
    done
else
    echo "   [FAIL] 无法访问InfiniBand设备信息"
fi

# 4. 网络接口检查
echo "4. 网络接口检查:"
echo "   InfiniBand接口:"
ip link show | grep -E "(ib|mlx)" || echo "     未找到InfiniBand接口"
echo
echo "   所有网络接口:"
ip addr show | grep -E "inet|UP" | head -10
echo

# 5. 驱动模块检查
echo "5. 驱动模块检查:"
echo "   RDMA相关模块:"
lsmod | grep -E "(ib_|rdma|mlx)" | head -10
echo
echo "   模块依赖关系:"
for mod in ib_core ib_uverbs mlx5_core; do
    if lsmod | grep -q $mod; then
        echo "     $mod: 已加载"
        modinfo $mod 2>/dev/null | grep -E "(filename|version|description)" | head -3
    else
        echo "     $mod: 未加载"
    fi
done
echo

# 6. 性能测试
echo "6. 性能测试:"
if command -v ibping &> /dev/null; then
    echo "   尝试RDMA ping测试..."
    timeout 10 ibping -S 2>/dev/null && echo "     [OK] RDMA ping 成功" || echo "     [FAIL] RDMA ping 失败"
else
    echo "   [FAIL] ibping 命令不可用"
fi
echo

echo "=== 增强测试完成 ==="
