#!/bin/bash
# 多机时序控制：等待指定 mavlink TCP 端口就绪后再启动 PX4。
# 与单机 px4_delayed_start.sh 的唯一区别：端口可作第一个参数传入（默认 4560），
# 从而每机等待各自的 4560+N 端口，避免「PX4 先起、对应模型插件还没加载」的握手失败。
#
# 用法（roslaunch 的 launch-prefix 会拼上 px4 可执行路径）:
#   px4_delayed_start_multi.sh <PORT> <px4可执行路径> <px4 args...>
PORT="${1:-4560}"
shift

for i in $(seq 1 90); do
  if ss -tln 2>/dev/null | grep -q ":$PORT "; then
    echo "[px4_delayed_start] mavlink plugin ready on :$PORT after ${i}s"
    break
  fi
  sleep 1
done
if ! ss -tln 2>/dev/null | grep -q ":$PORT "; then
  echo "[px4_delayed_start] WARNING: $PORT not ready after 90s, starting PX4 anyway"
fi
exec "$@"
