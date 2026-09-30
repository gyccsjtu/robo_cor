#!/bin/bash
# WSL2 + RoboCup Gazebo 安装脚本
# 在 WSL2 Ubuntu 20.04 中运行

set -e

echo "=========================================="
echo "WSL2 RoboCup Gazebo 环境初始化"
echo "=========================================="

# 检查是否为 WSL2
if ! grep -qEi "(Microsoft|WSL)" /proc/version; then
    echo "警告：可能不在 WSL2 环境中"
fi

# 1. 更新系统
echo "[1/8] 更新系统..."
sudo apt update
sudo apt upgrade -y

# 2. 安装 ROS Noetic
echo "[2/8] 安装 ROS Noetic..."
bash -c "$(curl -s https://raw.githubusercontent.com/ROBOTIS-GIT/robotis_tools/master/install_ros_noetic.sh)"

# 3. 安装 MAVROS
echo "[3/8] 安装 MAVROS..."
sudo apt-get install -y ros-noetic-mavros ros-noetic-mavros-extras

# 4. 安装 PX4 依赖
echo "[4/8] 安装 PX4 依赖..."
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
    build-essential \
    git

# 5. 安装 Gazebo
echo "[5/8] 安装 Gazebo..."
sudo sh -c 'echo "deb http://packages.osrfoundation.org/gazebo/ubuntu-stable focal main" > /etc/apt/sources.list.d/gazebo-stable.list'
wget https://packages.osrfoundation.org/gazebo.key -O - | sudo apt-key add -
sudo apt update
sudo apt-get install -y gazebo

# 6. 下载 PX4
echo "[6/8] 下载 PX4-Autopilot..."
cd ~
if [ ! -d "PX4-Autopilot" ]; then
    git clone https://github.com/PX4/PX4-Autopilot.git --recursive
fi
cd PX4-Autopilot
git submodule update --init --recursive

# 7. 编译（可选，这步需要很长时间）
echo "[7/8] 编译 PX4（可选，需要 15-30 分钟）..."
echo "如需编译，运行: cd ~/PX4-Autopilot && make px4_sitl gazebo"

# 8. 创建工作区
echo "[8/8] 创建 RoboCup 工作区..."
mkdir -p ~/robocup/src

echo ""
echo "=========================================="
echo "初始化完成！"
echo "=========================================="
echo ""
echo "后续步骤："
echo "  1. 编译 PX4: cd ~/PX4-Autopilot && make px4_sitl gazebo"
echo "  2. 复制你的代码到 ~/robocup/src/"
echo "  3. 设置环境变量: source ~/PX4-Autopilot/Tools/sitl_gazebo/setup.sh"
echo ""
