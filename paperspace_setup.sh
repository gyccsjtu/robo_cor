#!/bin/bash
# Paperspace Gazebo + PX4 SITL 初始化脚本
# 用法: bash paperspace_setup.sh

set -e

echo "=========================================="
echo "RoboCup Gazebo 环境初始化"
echo "=========================================="

# 1. 安装 ROS Noetic
echo "[1/6] 安装 ROS Noetic..."
bash -c "$(curl -s https://raw.githubusercontent.com/ROBOTIS-GIT/robotis_tools/master/install_ros_noetic.sh)"

# 2. 安装 MAVROS
echo "[2/6] 安装 MAVROS..."
sudo apt-get update
sudo apt-get install -y ros-noetic-mavros ros-noetic-mavros-extras

# 3. 安装 PX4 依赖
echo "[3/6] 安装 PX4 依赖..."
sudo apt-get install -y \
    python3-pip \
    python3-tk \
    python3-matplotlib \
    python3-serial \
    python3-numpy \
    libeigen3-dev \
    libopencv-dev \
    libconsole-bridge-dev \
    libtinyxml2-dev \
    libxml2-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    build-essential

# 4. 下载 PX4
echo "[4/6] 下载 PX4-Autopilot..."
cd ~
if [ ! -d "PX4-Autopilot" ]; then
    git clone https://github.com/PX4/PX4-Autopilot.git --recursive
fi
cd PX4-Autopilot
git submodule update --init --recursive

# 5. 编译
echo "[5/6] 编译 PX4 (这需要 10-20 分钟)..."
make px4_sitl gazebo

# 6. 同步代码
echo "[6/6] 同步 RoboCup 代码..."
cd ~
mkdir -p robocup/src
cd robocup
# 复制你的代码（需要先从 VM 同步过来）
# 这里假设你已经通过 vm_sync.py 同步了代码

echo ""
echo "=========================================="
echo "初始化完成！"
echo "=========================================="
echo ""
echo "测试 Gazebo:"
echo "  cd ~/PX4-Autopilot"
echo "  make px4_sitl gazebo_iris"
echo ""
echo "运行仿真:"
echo "  source ~/PX4-Autopilot/Tools/sitl_gazebo/setup.sh"
echo "  roslaunch ..."
echo ""
