#!/bin/bash
# -*- coding: utf-8 -*-
"""快速验证脚本 - 只验证 SITL 基础功能

在服务器上依次运行以下命令来验证环境:
"""

echo "========================================"
echo "  快速验证步骤"
echo "========================================"

echo ""
echo "=== 1. 检查 ROS ==="
echo "运行: roscore"
echo "预期: 看到 /rosout 等话题"

echo ""
echo "=== 2. 检查 Gazebo ==="
echo "运行: gazebo"
echo "预期: 弹出 Gazebo 窗口"

echo ""
echo "=== 3. 检查 PX4 ==="
echo "运行: cd ~/XTDrone/simulation && make px4_sitl_default gazebo"
echo "预期: 看到 Iris 无人机在 Gazebo 中"

echo ""
echo "=== 4. 检查 MAVROS ==="
echo "运行: rostopic list | grep mavros"
echo "预期: 看到 /uav_1/mavros/* 话题"

echo ""
echo "=== 5. 快速测试: 启动 2 架机 ==="
echo "运行: roslaunch xtdrone_offboard multirotor.launch n_uav:=2"
echo "预期: 看到两架 Iris 无人机"

echo ""
echo "=== 6. 测试代码 ==="
echo "运行: cd ~/team_ws/robocup && python -c 'from swarm_manager import SwarmManager; print(\"OK\")'"
echo "预期: 输出 OK"

echo ""
echo "========================================"
echo "  如有问题，检查:"
echo "  1. 环境变量: echo \$ROBOCUP_WS"
echo "  2. ROS 状态: rostopic list"
echo "  3. Gazebo 进程: ps aux | grep gz"
echo "========================================"
