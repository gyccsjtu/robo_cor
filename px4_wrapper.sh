#!/bin/bash
# PX4 SITL 可执行入口（roslaunch 的 pkg="px4" type="px4" 调用本脚本）。
#
# 用 ROBOCUP_WS 环境变量定位工作空间（云端部署/换用户时无需改此文件）；
# 未设置时回落到本地 VM 的默认路径（向后兼容）。
set -e
WS="${ROBOCUP_WS:-/home/ros/team_ws/robocup}"
PX4_DIR="$WS/third_party/PX4-Autopilot"
BUILD="$PX4_DIR/build/px4_sitl_default"

cd "$BUILD/tmp/rootfs" || { echo "[px4 wrapper] rootfs 不存在: $BUILD/tmp/rootfs" >&2; exit 1; }
exec "$BUILD/bin/px4" "$@"
