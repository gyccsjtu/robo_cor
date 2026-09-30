#!/bin/bash
# -*- coding: utf-8 -*-
"""新服务器环境配置脚本

用法:
  1. 把本脚本上传到新服务器
  2. chmod +x setup_new_server.sh
  3. ./setup_new_server.sh

或者分步执行:
  ./setup_new_server.sh basic      # 只装基础依赖
  ./setup_new_server.sh xtdrone    # 只装 XTDrone
  ./setup_new_server.sh codesync   # 只同步代码
"""

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    log_warn "建议用 root 运行: sudo ./setup_new_server.sh"
fi

# ============================================================
# 第一步：基础环境
# ============================================================
install_basic() {
    log_info "=== 安装基础依赖 ==="

    # 更新
    apt update && apt upgrade -y

    # 基础工具
    apt install -y git curl wget vim build-essential

    # Python
    apt install -y python3 python3-pip python3-venv

    # ROS Noetic
    sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list'
    apt update
    apt install -y ros-noetic-desktop-full

    # Gazebo 11
    apt install -y gazebo11 libgazebo11-dev

    # MAVROS
    apt install -y ros-noetic-mavros ros-noetic-mavros-extras

    # GeographicLib datasets
    wget https://raw.githubusercontent.com/mavlink/mavros/master/mavros/scripts/install_geographiclib_datasets.sh
    chmod +x install_geographiclib_datasets.sh
    ./install_geographiclib_datasets.sh
    rm install_geographiclib_datasets.sh

    log_info "基础依赖安装完成"
}

# ============================================================
# 第二步：Miniconda + Python 3.8
# ============================================================
install_conda() {
    log_info "=== 安装 Miniconda ==="

    cd /tmp
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p /opt/miniconda3
    rm miniconda.sh

    # 添加到 PATH
    echo 'export PATH="/opt/miniconda3/bin:$PATH"' >> ~/.bashrc

    # 创建 conda 环境
    export PATH="/opt/miniconda3/bin:$PATH"
    conda create -n robocup python=3.8 -y

    log_info "Miniconda 安装完成"
    log_info "激活环境: conda activate robocup"
}

# ============================================================
# 第三步：XTDrone
# ============================================================
install_xtdrone() {
    log_info "=== 安装 XTDrone ==="

    cd ~
    git clone https://github.com/robin-shaun/XTDrone.git
    cd XTDrone
    git submodule update --init --recursive

    # 安装依赖
    cd simulation
    ./install.sh

    log_info "XTDrone 安装完成"
}

# ============================================================
# 第四步：同步代码
# ============================================================
sync_codes() {
    log_info "=== 同步代码 ==="

    # 创建工作目录
    mkdir -p ~/team_ws/robocup
    cd ~/team_ws/robocup

    # 如果有 git 仓库
    if [ -d ".git" ]; then
        git pull
    else
        # 从本地上传代码
        log_warn "请从本地上传代码: scp -r *.py *.sh user@server:~/team_ws/robocup/"
    fi

    # 设置环境变量
    echo 'export ROBOCUP_WS=~/team_ws/robocup' >> ~/.bashrc
    echo 'export GAZEBO_MODEL_PATH=$GAZEBO_MODEL_PATH:~/XTDrone/Models' >> ~/.bashrc
    echo 'export PYTHONPATH=$PYTHONPATH:~/team_ws/robocup:~/team_ws/robocup/scripts/vm' >> ~/.bashrc

    log_info "代码同步完成"
}

# ============================================================
# 第五步：验证安装
# ============================================================
verify() {
    log_info "=== 验证安装 ==="

    # ROS
    if command -v roscore &> /dev/null; then
        log_info "✓ ROS 已安装"
    else
        log_error "✗ ROS 未安装"
    fi

    # Gazebo
    if command -v gzserver &> /dev/null; then
        log_info "✓ Gazebo 已安装"
    else
        log_error "✗ Gazebo 未安装"
    fi

    # Python
    if command -v python3 &> /dev/null; then
        log_info "✓ Python3 已安装"
    else
        log_error "✗ Python3 未安装"
    fi

    # Miniconda
    if [ -d "/opt/miniconda3" ]; then
        log_info "✓ Miniconda 已安装"
    else
        log_warn "✗ Miniconda 未安装 (可选)"
    fi
}

# ============================================================
# 启动多机仿真的快捷脚本
# ============================================================
create_launch_scripts() {
    log_info "=== 创建启动脚本 ==="

    # 启动多机 SITL
    cat > ~/start_multi.sh << 'EOF'
#!/bin/bash
# 启动多机 SITL

export ROBOCUP_WS=~/team_ws/robocup
export GAZEBO_MODEL_PATH=$GAZEBO_MODEL_PATH:~/XTDrone/Models
export PYTHONPATH=$PYTHONPATH:~/team_ws/robocup:~/team_ws/robocup/scripts/vm

# 默认 2 架
N=${1:-2}

cd ~/XTDrone/simulation
roslaunch xtdrone_offboard multirotor.launch n_uav:=$N
EOF
    chmod +x ~/start_multi.sh

    # 启动协同追踪
    cat > ~/start_tracking.sh << 'EOF'
#!/bin/bash
# 启动协同追踪

export ROBOCUP_WS=~/team_ws/robocup
export GAZEBO_MODEL_PATH=$GAZEBO_MODEL_PATH:~/XTDrone/Models
export PYTHONPATH=$PYTHONPATH:~/team_ws/robocup:~/team_ws/robocup/scripts/vm

# 启动 manager
rosrun robocup_swarm swarm_manager.py &

# 启动各机 agent
for i in $(seq 1 $1); do
    rosrun robocup_swarm swarm_agent.py _uav_id:=uav_$i &
done

echo "已启动 manager + $1 架 agent"
EOF
    chmod +x ~/start_tracking.sh

    log_info "启动脚本已创建: ~/start_multi.sh, ~/start_tracking.sh"
}

# ============================================================
# 主函数
# ============================================================
main() {
    echo "========================================"
    echo "  服务器环境配置脚本"
    echo "========================================"

    MODE=${1:-all}

    case $MODE in
        basic)
            install_basic
            ;;
        conda)
            install_conda
            ;;
        xtdrone)
            install_xtdrone
            ;;
        codesync)
            sync_codes
            ;;
        verify)
            verify
            ;;
        all)
            install_basic
            install_conda
            install_xtdrone
            sync_codes
            verify
            create_launch_scripts
            ;;
        *)
            echo "用法: $0 [basic|conda|xtdrone|codesync|verify|all]"
            echo ""
            echo "  basic    - 安装基础依赖 (ROS, Gazebo)"
            echo "  conda    - 安装 Miniconda + Python 3.8"
            echo "  xtdrone  - 安装 XTDrone"
            echo "  codesync - 同步代码"
            echo "  verify   - 验证安装"
            echo "  all      - 全部 (默认)"
            exit 1
            ;;
    esac
}

main "$@"
