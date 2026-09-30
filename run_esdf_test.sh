#!/bin/bash
# RoboCup 阶段A ESDF-DWA 实验启动脚本（多组可复现场景）
# 用法：
#   bash ~/run_esdf_test.sh <场景名>
#   场景名: wall(正面墙) ushape(拐角) blocked(无路悬停) city(灯杆绕行)
#           city_full(比赛标准地图200×100m，goal_0001 穿越全城~90m)
# 例：bash ~/run_esdf_test.sh city_full

set -e
SCENE="${1:-wall}"

declare -A WORLD_METADATA
GEN_DIR=~/team_ws/robocup/src/robocup_training_worlds/worlds/generated

case "$SCENE" in
  wall)
    WORLD="$GEN_DIR/training_city_unit_single_wall_s42.world"
    META="$GEN_DIR/training_city_unit_single_wall_s42.json"
    SPAWN_X=-3; SPAWN_Y=-2.5; GOAL_X=3; GOAL_Y=-2.5
    ALT=2.4; SPD=2.0
    ;;
  ushape)
    WORLD="$GEN_DIR/ushape_s11.world"
    META="$GEN_DIR/ushape_s11.json"
    SPAWN_X=-3; SPAWN_Y=0; GOAL_X=3; GOAL_Y=0
    ALT=2.4; SPD=2.0
    ;;
  blocked)
    WORLD="$GEN_DIR/blocked_s13.world"
    META="$GEN_DIR/blocked_s13.json"
    SPAWN_X=-3; SPAWN_Y=0; GOAL_X=3; GOAL_Y=0
    ALT=2.4; SPD=2.0
    ;;
  city)
    WORLD="$GEN_DIR/city_small_s7.world"
    META="$GEN_DIR/city_small_s7.json"
    SPAWN_X=-13.375; SPAWN_Y=1.125; GOAL_X=13.125; GOAL_Y=5.125
    ALT=2.4; SPD=2.0
    ;;
  city_full)
    # 比赛标准地图 200m×100m（x:-100~100 y:-50~50），38 建筑 + 184 灯杆 + 4 边界墙
    # 出生点 (-4.75,7.75) -> goal_0001 (85.25,7.75)，正右方横穿全城 ~90m
    WORLD="$GEN_DIR/training_city_full_s7.world"
    META="$GEN_DIR/training_city_full_s7.json"
    SPAWN_X=-4.75; SPAWN_Y=7.75; GOAL_X=85.25; GOAL_Y=7.75
    ALT=6.0; SPD=3.0
    ;;
  *)
    echo "未知场景: $SCENE (可选 wall/ushape/blocked/city/city_full)" >&2
    exit 2
    ;;
esac

echo ">>> 场景: $SCENE"
echo ">>> world: $WORLD"
echo ">>> spawn: ($SPAWN_X, $SPAWN_Y)  goal: ($GOAL_X, $GOAL_Y)  alt=$ALT spd=$SPD"

# ===== 0. 清理残留 =====
echo ">>> 清理仿真残留..."
pkill -9 -f "roslaunch px4 mavros_posix_sitl" 2>/dev/null || true
pkill -9 -f "px4_sitl_default/bin/px4" 2>/dev/null || true
pkill -9 -f "px4_sitl_default.*rcS" 2>/dev/null || true
pkill -9 -f "gzserver" 2>/dev/null || true
pkill -9 -f "gzclient" 2>/dev/null || true
pkill -9 -f "mavros_node" 2>/dev/null || true
pkill -9 -f "rosmaster" 2>/dev/null || true
sleep 2
rm -rf /tmp/px4-* 2>/dev/null || true
rm -rf ~/team_ws/robocup/third_party/PX4-Autopilot/build/px4_sitl_default/tmp/rootfs/instance* 2>/dev/null || true
echo ">>> 清理完成"

# ===== 1. 环境 =====
source /opt/ros/noetic/setup.bash
source ~/catkin_ws/devel/setup.bash
source ~/team_ws/robocup/devel/setup.bash
source /usr/share/gazebo/setup.sh
source ~/team_ws/robocup/third_party/PX4-Autopilot/Tools/setup_gazebo.bash \
       ~/team_ws/robocup/third_party/PX4-Autopilot \
       ~/team_ws/robocup/third_party/PX4-Autopilot/build/px4_sitl_default

export ROS_PACKAGE_PATH=$ROS_PACKAGE_PATH:~/team_ws/robocup/third_party/PX4-Autopilot/Tools/sitl_gazebo
export LD_LIBRARY_PATH=~/team_ws/robocup/third_party/PX4-Autopilot/build/px4_sitl_default/build_gazebo:$LD_LIBRARY_PATH

# ===== 2. 启动仿真 + MAVROS（后台）=====
roslaunch px4 mavros_posix_sitl.launch \
  interactive:=false \
  x:=$SPAWN_X y:=$SPAWN_Y \
  vehicle:=iris_2d_lidar \
  world:=$WORLD &
SIM_PID=$!
echo ">>> 仿真 PID=$SIM_PID"

# ===== 3. 等待 MAVROS 就绪后启动控制节点 =====
sleep 15
echo ">>> 启动 ESDF-DWA 控制节点"
cd ~/team_ws/robocup/src/robocup_swarm/scripts
python3 dwa_avoidance.py \
  _metadata:=$META \
  _start_x:=$SPAWN_X _start_y:=$SPAWN_Y \
  _goal_x:=$GOAL_X _goal_y:=$GOAL_Y \
  _altitude_m:=$ALT _max_speed_m_s:=$SPD

# 控制节点退出（到达/降落）后收尾
echo ">>> 控制节点退出，停止仿真"
kill $SIM_PID 2>/dev/null || true
