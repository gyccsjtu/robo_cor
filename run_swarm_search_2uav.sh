#!/bin/bash
# 集群协同搜索 2 机共享状态启动脚本（步骤 1）。
#
# 依赖：multi_uav_sitl.launch 已起（2 机 Gazebo + PX4 + MAVROS）。
# 用法：bash ~/run_swarm_search_2uav.sh [uav_id列表，默认 uav_1,uav_2]
#
# 会启动：
#   1. 每机一个 swarm_agent（各自 namespaced 订阅 /uav_N/mavros/*）
#   2. 一个 swarm_manager（集中式拍卖 + 租约）
# 日志写到 ~/team_ws/robocup/logs/swarm_search/
set -eo pipefail

IDS="${1:-uav_1,uav_2}"
IFS=',' read -ra UAV_ARR <<< "$IDS"

LOG_ROOT="${ROBOCUP_LOG_ROOT:-$HOME/team_ws/robocup/logs/swarm_search}"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="${LOG_ROOT}/${RUN_TS}"
mkdir -p "${LOG_DIR}"

echo ">>> swarm 搜索启动: 机队=${IDS} 日志=${LOG_DIR}"

# 环境
source /opt/ros/noetic/setup.bash
source ~/team_ws/robocup/devel/setup.bash

# 每机 agent（后台，各自日志）
for uid in "${UAV_ARR[@]}"; do
    # 从 uav_N 推导模型名 iris_N（与 fleet.yaml model_name_template 一致）
    model="iris_${uid##*_}"
    echo ">>> 启动 agent: ${uid} (model=${model})"
    ROS_NAMESPACE="${uid}" nohup rosrun robocup_swarm swarm_agent.py \
        _uav_id:="${uid}" _model_name:="${model}" \
        > "${LOG_DIR}/${uid}_agent.log" 2>&1 &
    echo "$!" > "${LOG_DIR}/${uid}_agent.pid"
done

# 管理器（后台）
echo ">>> 启动 manager: ${IDS}"
nohup rosrun robocup_swarm swarm_manager.py _uav_ids:="${IDS}" \
    > "${LOG_DIR}/manager.log" 2>&1 &
echo "$!" > "${LOG_DIR}/manager.pid"

echo ">>> 全部启动完成，日志在 ${LOG_DIR}"
echo ">>> 停止：kill \$(cat ${LOG_DIR}/*.pid)"
