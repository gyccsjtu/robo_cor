# 协同追踪系统 - 服务器检查清单

## 需要同步的代码文件

### 核心算法 (必须)
| 文件 | 作用 | 状态 |
|------|------|------|
| `swarm_manager.py` | 集中式任务分配 | ✅ |
| `swarm_agent.py` | 单机控制 + ESDF/DWA 避障 | ✅ |
| `cooperative_tracker.py` | 目标追踪逻辑（15s确认、30s逃逸） | ✅ |
| `observer_assign.py` | LOS 观察位规划 + handover 状态机 | ✅ (待调试) |
| `swarm_task.py` | 拍卖算法 + 租约管理 | ✅ |
| `target_sim_node.py` | 目标模拟节点 | ✅ |

### 测试/仿真 (必须)
| 文件 | 作用 |
|------|------|
| `mission_time.py` | 离线任务时间仿真 |
| `strategy_compare.py` | 地图 + LOS 射线检测 |
| `local_esdf.py` | ESDF 地图构建 |
| `persistent_los.py` | LOS 保持逻辑 |

### 启动脚本
| 文件 | 作用 |
|------|------|
| `run_multi_uav_*.sh` | 多机启动脚本 |
| `verify_swarm_avoidance.py` | 验证避障 |

---

## 服务器环境要求

### 系统
- [ ] Ubuntu 20.04 LTS
- [ ] ROS Noetic
- [ ] Gazebo 11.3 (需 cudagl)
- [ ] PX4 1.13.2+

### Python 环境
```bash
# 方式1: conda
conda create -n robocup python=3.8
conda activate robocup

# 方式2: 系统 Python
pip install numpy scipy opencv-python pyyaml
```

### ROS 包
```bash
sudo apt install ros-noetic-mavros ros-noetic-mavros-extras
```

### 环境变量
```bash
export ROBOCUP_WS=~/team_ws/robocup
export GAZEBO_MODEL_PATH=$GAZEBO_MODEL_PATH:~/XTDrone/Models
export PYTHONPATH=$PYTHONPATH:$ROBOCUP_WS:$ROBOCUP_WS/scripts/vm
```

---

## 验证步骤

### 1. 基础仿真 (离线)
```bash
cd ~/team_ws/robocup
python mission_time.py --runs 5
# 预期: 60s 内消除 1-2 个目标
```

### 2. 单机 SITL
```bash
# 终端1: 启动 Gazebo
cd ~/XTDrone/simulation
make px4_sitl_default gazebo

# 终端2: 起飞
rostopic pub /uav_1/mavros/set_mode std_msgs/String "OFFBOARD" -1
rostopic pub /uav_1/mavros/cmd/arm std_msgs/Bool "true" -1
```

### 3. 多机 SITL
```bash
roslaunch xtdrone_offboard multirotor.launch n_uav:=2
```

### 4. 协同追踪
```bash
# 启动 manager
rosrun robocup_swarm swarm_manager.py

# 启动 agent (每架无人机一个终端)
rosrun robocup_swarm swarm_agent.py _uav_id:=uav_1
rosrun robocup_swarm swarm_agent.py _uav_id:=uav_2
```

---

## 已知问题

1. **handover 离线仿真卡死**
   - 原因: `observer_assign.py` 的状态机逻辑问题
   - 解决: 在真实 SITL 上调试

2. **metadata 文件缺失**
   - 位置: `~/team_ws/robocup/src/robocup_training_worlds/worlds/generated/training_city_full_s7.json`
   - 解决: 从 VM 同步或重新生成

3. **多机端口冲突**
   - 解决: 使用默认的 4560+N 端口分配
