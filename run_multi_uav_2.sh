#!/bin/bash
# 多机 SITL 启动 + 状态检查（2 机版）
set -o pipefail

echo '>>> 清理残留进程...'
pkill -9 -f 'roslaunch px4 mavros_posix_sitl' 2>/dev/null || true
pkill -9 -f 'px4_sitl_default/bin/px4' 2>/dev/null || true
pkill -9 -f 'gzserver' 2>/dev/null || true
pkill -9 -f 'gzclient' 2>/dev/null || true
pkill -9 -f 'mavros_node' 2>/dev/null || true
pkill -9 -f 'rosmaster' 2>/dev/null || true
sleep 2
rm -rf /tmp/px4-* 2>/dev/null || true
rm -rf ~/team_ws/robocup/third_party/PX4-Autopilot/build/px4_sitl_default/tmp/rootfs/instance* 2>/dev/null || true
rm -rf ~/team_ws/robocup/third_party/PX4-Autopilot/build/px4_sitl_default/tmp/rootfs/sitl_iris_* 2>/dev/null || true
echo '>>> 清理完成'

source /opt/ros/noetic/setup.bash
source ~/catkin_ws/devel/setup.bash
source ~/team_ws/robocup/devel/setup.bash
source /usr/share/gazebo/setup.sh
source ~/team_ws/robocup/third_party/PX4-Autopilot/Tools/setup_gazebo.bash \
       ~/team_ws/robocup/third_party/PX4-Autopilot \
       ~/team_ws/robocup/third_party/PX4-Autopilot/build/px4_sitl_default
export ROS_PACKAGE_PATH=$ROS_PACKAGE_PATH:~/team_ws/robocup/third_party/PX4-Autopilot/Tools/sitl_gazebo
export LD_LIBRARY_PATH=~/team_ws/robocup/third_party/PX4-Autopilot/build/px4_sitl_default/build_gazebo:$LD_LIBRARY_PATH

echo '>>> 启动多机 launch（后台）...'
LOG=$HOME/multi_uav_2.log
roslaunch robocup_swarm multi_uav_sitl.launch gui:=true > "$LOG" 2>&1 &
LAUNCH_PID=$!
echo "$LAUNCH_PID" > ~/multi_uav_2.pid
echo ">>> launch PID=$LAUNCH_PID, 日志 $LOG"

# 等 Gazebo 起来
echo '>>> 等待 Gazebo...'
for i in $(seq 1 60); do
  pgrep -x gzserver >/dev/null 2>&1 && { echo "Gazebo 起来了 (${i}x2s)"; break; }
  sleep 2
done

# 等 PX4 实例（应有两个）
echo '>>> 等待 PX4 实例...'
sleep 10
PX4_COUNT=$(pgrep -fc 'px4_sitl_default/bin/px4' 2>/dev/null || echo 0)
echo ">>> PX4 进程数 = $PX4_COUNT (期望 2)"

# 绑定 CPU 核：多机 SITL 只有 4 核，gzserver(37% CPU) + 2×px4 争抢会让第二架机
# EKF 高度发散（-7~-156m 坏值）。把 gzserver 绑核 2,3、两机 px4 各绑核 0/1，
# 消除争抢，EKF 融合周期稳定。
echo '>>> 绑定 CPU 核（gzserver→2,3 / px4_0→0 / px4_1→1）...'
sleep 3
GZPID=$(pgrep -f 'gzserver -e ode' | head -1)
PX4_0=$(pgrep -f 'px4.*-i 0' | head -1)
PX4_1=$(pgrep -f 'px4.*-i 1' | head -1)
[ -n "$GZPID" ] && taskset -pc 2,3 "$GZPID" 2>/dev/null
[ -n "$PX4_0" ] && taskset -pc 0 "$PX4_0" 2>/dev/null
[ -n "$PX4_1" ] && taskset -pc 1 "$PX4_1" 2>/dev/null
echo ">>> 绑定完成 gzserver=$GZPID px4_0=$PX4_0 px4_1=$PX4_1"

# 等 MAVROS topic
sleep 10
echo '>>> MAVROS topic 检查...'
timeout 10 rostopic list 2>/dev/null | grep -E 'uav_[12]/mavros/state' || echo '(尚未出现)'

echo '>>> 启动完成，日志尾部:'
tail -30 "$LOG"
