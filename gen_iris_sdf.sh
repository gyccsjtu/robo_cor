#!/bin/bash
# 生成参数化的 iris_2d_lidar SDF（多机专用）：改 mavlink_interface 插件的 4 个端口，
# 结果输出到 stdout，供 roslaunch 的 <param command=...> 捕获后 spawn_model -param 使用。
#
# 用法: gen_iris_sdf.sh <input.sdf> <ID>
#   ID = PX4 实例号（0 基）。端口公式集中在此处（单一事实来源）：
#     mavlink_tcp_port = 4560+ID   （PX4 simulator 连它，必须每机不同，否则抢端口）
#     mavlink_udp_port = 14560+ID  （mavlink UDP 访问端口）
#     qgc_udp_port     = 14550+ID  （QGC 地面站，本队不跑 QGC，仍偏移保持隔离）
#     sdk_udp_port     = 14540+ID  （SDK 端口，偏移保持隔离）
#
# 设计约束：不复制 Crazyswarm2 / XTDrone 的 launch 与脚本，只复用团队已跑通的
# 单机 iris_2d_lidar.sdf 模型与 xmlstarlet 工具，自建端口偏移脚本。
set -euo pipefail

SDF="${1:?缺少 input.sdf 路径}"
ID="${2:?缺少实例号 ID（0 基）}"

TCP=$((4560 + ID))
UDP=$((14560 + ID))
QGC=$((14550 + ID))
SDK=$((14540 + ID))

xmlstarlet ed \
  -u "//plugin[@name='mavlink_interface']/mavlink_tcp_port" -v "$TCP" \
  -u "//plugin[@name='mavlink_interface']/mavlink_udp_port" -v "$UDP" \
  -u "//plugin[@name='mavlink_interface']/qgc_udp_port"       -v "$QGC" \
  -u "//plugin[@name='mavlink_interface']/sdk_udp_port"       -v "$SDK" \
  "$SDF"
