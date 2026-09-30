#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""RoboCup 多机协同搜索仿真评估脚本。

功能：
1. 支持读取仿真日志或直接运行仿真
2. 批量运行多个 seed 结果统计
3. 输出详细指标到 summary.csv 和 detail.csv

指标：
- 15s success rate: 15s 连续确认完成率（全有全无）
- target completion rate: 目标级完成率
- first detection time: 首次发现时间
- detect-to-assign delay: 发现到分配的延迟
- longest continuous covered duration: 最长连续 covered 时间
- covered interruption count: covered 中断次数
- teleport count: 瞬移次数
- actual handover count: 实际交接次数（仅在 observer 集合真正变化时统计）
- UAV-UAV collision: 无人机碰撞次数
- UAV-building collision: 无人机撞建筑次数
- minimum UAV distance: 无人机间最小距离

使用方法：
    python evaluation/evaluate.py --seeds 0,1,2,3,4 --output results/
    python evaluation/evaluate.py --log-dir logs/ --output results/
"""

import os
import sys
import math
import argparse
import csv
import random
from collections import defaultdict
from datetime import datetime

# 添加父目录到路径
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import mission_time as MT
import task_allocator as TA
from strategy_compare import MapGrid


# ============================ 参数 ============================
UAV_RADIUS = 0.45
COLLISION_DIST = 2.0 * UAV_RADIUS  # 0.90 m
NEAR_MISS_DIST = 1.20
CONFIRM_TIME = 15.0  # 15s 连续确认
DETECT_RADIUS = 20.0  # 感知半径


class EvaluationMetrics:
    """评估指标收集器。"""

    def __init__(self):
        # 基础指标
        self.targets_completed = 0
        self.total_targets = 0

        # 时间相关
        self.first_detect_times = []  # 每个目标的首次发现时间
        self.detect_to_assign_delays = []  # 发现到分配的延迟

        # Covered 连续性指标（用户最关心）
        self.longest_continuous_covered = 0.0  # 最长连续 covered 时间
        self.covered_interruption_count = 0    # covered 中断次数

        # 目标行为
        self.teleport_count = 0  # 瞬移次数
        self.handover_count = 0  # 实际交接次数

        # 碰撞与安全
        self.uav_uav_collision_count = 0
        self.uav_building_collision_count = 0
        self.min_uav_distance = float('inf')

        # 内部状态
        self._prev_covered_status = {}  # target_id -> (is_covered, start_time)
        self._prev_observers = {}  # target_id -> set of observer uav IDs
        self._prev_free = None
        self._prev_uav_positions = {}
        self._prev_colliding_pairs = set()
        self._prev_near_pairs = set()

    def reset_per_target(self, target_id):
        """重置单个目标的跟踪状态。"""
        self._prev_covered_status[target_id] = (False, None)
        self._prev_observers[target_id] = set()

    def update_covered_metrics(self, target_id, is_covered, current_time):
        """更新 covered 连续性指标。

        covered: 任一观察员在 OBS_TTL 内报告且 LOS 通
        中断: covered 从 True 变为 False
        """
        prev_covered, prev_start = self._prev_covered_status.get((target_id, False), (False, None))

        if is_covered:
            if not prev_covered:
                # 开始新的 covered 期间
                self._prev_covered_status[target_id] = (True, current_time)
        else:
            if prev_covered and prev_start is not None:
                # covered 中断，计算连续时长
                duration = current_time - prev_start
                if duration > self.longest_continuous_covered:
                    self.longest_continuous_covered = duration
                self.covered_interruption_count += 1
            self._prev_covered_status[target_id] = (False, None)

    def update_handover_metrics(self, target_id, current_observers):
        """更新交接指标。

        交接只在 observer 集合真正变化时统计（不是按帧累计）。
        """
        prev_observers = self._prev_observers.get(target_id, set())

        # 检测集合是否真正变化
        if current_observers != prev_observers:
            # 有变化才计入交接
            if prev_observers:  # 非空才开始记录交接
                self.handover_count += 1
            self._prev_observers[target_id] = set(current_observers)

    def update_collision_metrics(self, uav_positions, is_free):
        """更新碰撞指标。"""
        # UAV-UAV 碰撞
        uav_ids = sorted(uav_positions.keys())
        current_colliding = set()
        current_near = set()

        for i, ui in enumerate(uav_ids):
            for uj in uav_ids[i+1:]:
                ux, uy = uav_positions[ui]
                vx, vy = uav_positions[uj]
                d = math.hypot(ux - vx, uy - vy)

                if d < self.min_uav_distance:
                    self.min_uav_distance = d

                if d < COLLISION_DIST:
                    current_colliding.add((ui, uj))
                if d < NEAR_MISS_DIST:
                    current_near.add((ui, uj))

        # 新增碰撞事件
        new_collisions = current_colliding - self._prev_colliding_pairs
        new_nears = current_near - self._prev_near_pairs

        self.uav_uav_collision_count += len(new_collisions)

        self._prev_colliding_pairs = current_colliding
        self._prev_near_pairs = current_near

        # UAV-建筑碰撞
        if self._prev_free is not None and self._prev_free and not is_free:
            self.uav_building_collision_count += 1
        self._prev_free = is_free


def run_single_simulation(seed, targets=6, max_t=300.0, config=None):
    """运行单次仿真并收集指标。

    Args:
        seed: 随机种子
        targets: 目标数量
        max_t: 最大仿真时间
        config: 配置字典

    Returns:
        dict: 包含所有指标的字典
    """
    if config is None:
        config = {}

    # 应用配置
    MT.SEP_TARGET_M = config.get('sep', 3.0)
    MT.SEP_PUSH_MAX_DEG = config.get('push_deg', 30)
    MT.SEARCH_PHASE = config.get('search_phase', 0)
    MT.FRIEND_SAFE = config.get('friend_safe', 0)
    MT.FRIEND_K = config.get('friend_k', 3)
    MT.FRIEND_MAX = config.get('friend_max', 2)
    MT.SLOT_MODE = config.get('slot_mode', 'los_plan')

    # 创建仿真
    g = MapGrid(TA.METADATA)
    sim = TA.AllocSim(g, strategy="dynamic", targets=targets, seed=seed)

    # 创建指标收集器
    metrics = EvaluationMetrics()

    # 初始化目标跟踪状态
    for tid in sim.tgt:
        metrics.reset_per_target(tid)

    # 跟踪瞬移
    teleport_count = 0
    prev_target_positions = {}

    # 跟踪首次发现和分配时间
    first_detect_time = {}
    first_assign_time = {}

    # 观察员分配历史（用于检测真正的交接）
    observer_history = defaultdict(list)  # target_id -> [(time, observer_set), ...]

    def hook(s):
        nonlocal teleport_count

        # 1. 检测瞬移
        for tid, tg in s.tgt.items():
            prev_pos = prev_target_positions.get(tid)
            if prev_pos is not None:
                d = math.hypot(tg['x'] - prev_pos[0], tg['y'] - prev_pos[1])
                # 如果目标在短时间内移动超过 50m，认为是瞬移
                if d > 50.0:
                    teleport_count += 1
            prev_target_positions[tid] = (tg['x'], tg['y'])

        # 2. 检测首次发现
        for tid, tg in s.tgt.items():
            if tid not in first_detect_time:
                for uav_id, (ux, uy) in s.uavs.items():
                    d = math.hypot(tg['x'] - ux, tg['y'] - uy)
                    if d < DETECT_RADIUS:
                        first_detect_time[tid] = s.t
                        break

            # 3. 检测首次分配观察员
            if tid not in first_assign_time:
                obs = s.tr.targets.get(tid)
                if obs and obs.observers:
                    first_assign_time[tid] = s.t

        # 4. 更新 covered 指标
        for tid in s.tgt:
            ct = s.tr.targets.get(tid)
            if ct:
                is_covered = ct.covered(s.t)
                metrics.update_covered_metrics(tid, is_covered, s.t)

                # 5. 更新交接指标
                current_observers = set(ct.observers)
                metrics.update_handover_metrics(tid, current_observers)

                # 记录观察员历史
                if current_observers:
                    observer_history[tid].append((s.t, frozenset(current_observers)))

        # 6. 更新碰撞指标
        pos = {u: tuple(p) for u, p in s.uavs.items()}
        free_all = all(g.free(px, py) for px, py in pos.values())
        metrics.update_collision_metrics(pos, free_all)

    # 运行仿真
    sim.run(max_t, on_step=lambda s: (s._observe_metrics(), hook(s)))

    # 仿真结束后的处理
    # 计算最终的 covered 时长（如果还在 covered 状态）
    for tid in sim.tgt:
        ct = sim.tr.targets.get(tid)
        if ct:
            is_covered = ct.covered(sim.t)
            prev_covered, prev_start = metrics._prev_covered_status.get((tid, False), (False, None))
            if is_covered and prev_start is not None:
                duration = sim.t - prev_start
                if duration > metrics.longest_continuous_covered:
                    metrics.longest_continuous_covered = duration

    # 整理结果
    result = {
        'seed': seed,
        'targets_completed': len(sim.done),
        'total_targets': targets,

        # 15s 成功率（全有全无）
        '15s_success_rate': 1.0 if len(sim.done) == targets else 0.0,

        # 目标级完成率
        'target_completion_rate': len(sim.done) / targets,

        # 首次发现时间
        'first_detect_time': min(first_detect_time.values()) if first_detect_time else None,
        'avg_first_detect_time': sum(first_detect_time.values()) / len(first_detect_time) if first_detect_time else None,

        # 发现到分配的延迟
        'detect_to_assign_delay': [],
    }

    # 计算发现到分配的延迟
    for tid, det_t in first_detect_time.items():
        if tid in first_assign_time:
            result['detect_to_assign_delay'].append(first_assign_time[tid] - det_t)

    if result['detect_to_assign_delay']:
        result['avg_detect_to_assign_delay'] = sum(result['detect_to_assign_delay']) / len(result['detect_to_assign_delay'])
    else:
        result['avg_detect_to_assign_delay'] = None

    # Covered 指标
    result['longest_continuous_covered'] = metrics.longest_continuous_covered
    result['covered_interruption_count'] = metrics.covered_interruption_count

    # 其他指标
    result['teleport_count'] = teleport_count
    result['handover_count'] = metrics.handover_count
    result['uav_uav_collision_count'] = metrics.uav_uav_collision_count
    result['uav_building_collision_count'] = metrics.uav_building_collision_count
    result['min_uav_distance'] = metrics.min_uav_distance if metrics.min_uav_distance != float('inf') else None

    return result


def run_batch_simulation(seeds, targets=6, max_t=300.0, config=None):
    """批量运行仿真并收集所有结果。"""
    results = []

    for i, seed in enumerate(seeds):
        print(f"  Running seed {seed} ({i+1}/{len(seeds)})...", flush=True)
        result = run_single_simulation(seed, targets, max_t, config)
        results.append(result)

    return results


def compute_summary(results):
    """从详细结果计算汇总统计。"""
    if not results:
        return {}

    n = len(results)

    # 基础统计
    total_completed = sum(r['targets_completed'] for r in results)
    total_targets = sum(r['total_targets'] for r in results)

    # 15s 成功率
    success_count = sum(1 for r in results if r['15s_success_rate'] == 1.0)

    # 首次发现时间
    first_detect_times = [r['first_detect_time'] for r in results if r['first_detect_time'] is not None]
    avg_first_detect = sum(first_detect_times) / len(first_detect_times) if first_detect_times else None

    # 发现到分配延迟
    detect_delays = [d for r in results for d in r['detect_to_assign_delay']]
    avg_detect_to_assign = sum(detect_delays) / len(detect_delays) if detect_delays else None

    # Covered 指标
    longest_covered = [r['longest_continuous_covered'] for r in results]
    avg_longest_covered = sum(longest_covered) / len(longest_covered) if longest_covered else 0
    max_longest_covered = max(longest_covered) if longest_covered else 0
    min_longest_covered = min(longest_covered) if longest_covered else 0

    covered_interrupts = [r['covered_interruption_count'] for r in results]
    avg_covered_interrupts = sum(covered_interrupts) / len(covered_interrupts) if covered_interrupts else 0

    # 其他指标
    teleport_counts = [r['teleport_count'] for r in results]
    avg_teleport = sum(teleport_counts) / len(teleport_counts) if teleport_counts else 0

    handover_counts = [r['handover_count'] for r in results]
    avg_handover = sum(handover_counts) / len(handover_counts) if handover_counts else 0

    uav_uav_collisions = [r['uav_uav_collision_count'] for r in results]
    avg_uav_uav = sum(uav_uav_collisions) / len(uav_uav_collisions) if uav_uav_collisions else 0

    uav_bldg_collisions = [r['uav_building_collision_count'] for r in results]
    avg_uav_bldg = sum(uav_bldg_collisions) / len(uav_bldg_collisions) if uav_bldg_collisions else 0

    min_uav_distances = [r['min_uav_distance'] for r in results if r['min_uav_distance'] is not None]
    avg_min_uav_dist = sum(min_uav_distances) / len(min_uav_distances) if min_uav_distances else None
    min_min_uav_dist = min(min_uav_distances) if min_uav_distances else None

    summary = {
        'n_seeds': n,

        # 15s 成功率
        '15s_success_rate': f"{100.0 * success_count / n:.1f}%",
        '15s_success_count': f"{success_count}/{n}",

        # 目标级完成率
        'target_completion_rate': f"{100.0 * total_completed / total_targets:.1f}%",
        'targets_completed': f"{total_completed}/{total_targets}",

        # 首次发现时间
        'first_detect_time_avg': f"{avg_first_detect:.1f}s" if avg_first_detect else "N/A",
        'first_detect_time_min': f"{min(first_detect_times):.1f}s" if first_detect_times else "N/A",
        'first_detect_time_max': f"{max(first_detect_times):.1f}s" if first_detect_times else "N/A",

        # 发现到分配延迟
        'detect_to_assign_delay_avg': f"{avg_detect_to_assign:.1f}s" if avg_detect_to_assign else "N/A",

        # 最长连续 covered 时间
        'longest_continuous_covered_avg': f"{avg_longest_covered:.1f}s",
        'longest_continuous_covered_max': f"{max_longest_covered:.1f}s",
        'longest_continuous_covered_min': f"{min_longest_covered:.1f}s",

        # Covered 中断次数
        'covered_interruption_count_avg': f"{avg_covered_interrupts:.1f}",

        # 瞬移次数
        'teleport_count_avg': f"{avg_teleport:.1f}",

        # 交接次数
        'handover_count_avg': f"{avg_handover:.1f}",

        # 碰撞
        'uav_uav_collision_count_avg': f"{avg_uav_uav:.1f}",
        'uav_building_collision_count_avg': f"{avg_uav_bldg:.1f}",

        # 最小距离
        'min_uav_distance_avg': f"{avg_min_uav_dist:.2f}m" if avg_min_uav_dist else "N/A",
        'min_uav_distance_min': f"{min_min_uav_dist:.2f}m" if min_min_uav_dist else "N/A",
    }

    return summary


def write_csv(results, output_path, include_detail=True):
    """将结果写入 CSV 文件。"""
    fieldnames = [
        'seed',
        '15s_success_rate',
        'target_completion_rate',
        'targets_completed',
        'total_targets',
        'first_detect_time',
        'avg_first_detect_time',
        'avg_detect_to_assign_delay',
        'longest_continuous_covered',
        'covered_interruption_count',
        'teleport_count',
        'handover_count',
        'uav_uav_collision_count',
        'uav_building_collision_count',
        'min_uav_distance',
    ]

    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for r in results:
            row = {k: r.get(k) for k in fieldnames}
            # 格式化
            if row['first_detect_time'] is not None:
                row['first_detect_time'] = f"{row['first_detect_time']:.1f}"
            if row['avg_first_detect_time'] is not None:
                row['avg_first_detect_time'] = f"{row['avg_first_detect_time']:.1f}"
            if row['avg_detect_to_assign_delay'] is not None:
                row['avg_detect_to_assign_delay'] = f"{row['avg_detect_to_assign_delay']:.1f}"
            if row['longest_continuous_covered'] is not None:
                row['longest_continuous_covered'] = f"{row['longest_continuous_covered']:.1f}"
            if row['min_uav_distance'] is not None:
                row['min_uav_distance'] = f"{row['min_uav_distance']:.2f}"
            writer.writerow(row)


def write_summary(summary, output_path):
    """将汇总写入 CSV 文件。"""
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['Metric', 'Value'])
        for key, value in summary.items():
            writer.writerow([key, value])


def parse_seed_range(s):
    """解析 seed 范围字符串，如 '0,1,2,3,4' 或 '0-10' 或 '0,1-5,10'。"""
    seeds = set()
    parts = s.split(',')
    for part in parts:
        part = part.strip()
        if '-' in part:
            start, end = part.split('-')
            seeds.update(range(int(start), int(end) + 1))
        else:
            seeds.add(int(part))
    return sorted(seeds)


def main():
    parser = argparse.ArgumentParser(
        description='RoboCup 多机协同搜索仿真评估脚本',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 运行种子 0-39 共 40 次仿真
  python evaluation/evaluate.py --seeds 0-39 --output results/

  # 运行特定种子列表
  python evaluation/evaluate.py --seeds 0,5,10,15,20 --output results/

  # 指定配置参数
  python evaluation/evaluate.py --seeds 0-9 --sep 3.0 --search-phase 6 --output results/

  # 从日志目录读取（待实现）
  python evaluation/evaluate.py --log-dir logs/ --output results/
        """
    )

    parser.add_argument('--seeds', type=str, required=True,
                        help='种子范围，如 "0,1,2" 或 "0-39"')
    parser.add_argument('--targets', type=int, default=6,
                        help='目标数量 (默认 6)')
    parser.add_argument('--max-t', type=float, default=300.0,
                        help='最大仿真时间秒 (默认 300)')
    parser.add_argument('--output', type=str, default='results',
                        help='输出目录 (默认 results)')

    # 配置参数
    parser.add_argument('--sep', type=float, default=3.0,
                        help='SEP 分离距离 (默认 3.0)')
    parser.add_argument('--push-deg', type=float, default=30,
                        help='推开最大角度 (默认 30)')
    parser.add_argument('--search-phase', type=int, default=0,
                        help='搜索阶段偏移 (默认 0)')
    parser.add_argument('--friend-safe', type=float, default=0,
                        help='友机安全距离 (默认 0)')
    parser.add_argument('--friend-k', type=float, default=3,
                        help='友机 K 值 (默认 3)')
    parser.add_argument('--friend-max', type=float, default=2,
                        help='友机最大推开距离 (默认 2)')
    parser.add_argument('--slot-mode', type=str, default='los_plan',
                        help='观察位规划模式 (默认 los_plan)')

    args = parser.parse_args()

    # 解析种子
    seeds = parse_seed_range(args.seeds)
    print(f"Running evaluation with {len(seeds)} seeds: {seeds[0]}-{seeds[-1]}")
    print(f"Config: SEP={args.seed}, PUSH={args.push_deg}°, PHASE={args.search_phase}")
    print(f"Targets: {args.targets}, Max time: {args.max_t}s")
    print()

    # 创建输出目录
    os.makedirs(args.output, exist_ok=True)

    # 配置
    config = {
        'sep': args.sep,
        'push_deg': args.push_deg,
        'search_phase': args.search_phase,
        'friend_safe': args.friend_safe,
        'friend_k': args.friend_k,
        'friend_max': args.friend_max,
        'slot_mode': args.slot_mode,
    }

    # 运行仿真
    print("Starting simulations...")
    results = run_batch_simulation(seeds, args.targets, args.max_t, config)
    print(f"\nCompleted {len(results)} simulations")

    # 写入详细结果
    detail_path = os.path.join(args.output, 'detail.csv')
    write_csv(results, detail_path)
    print(f"Written detail results to {detail_path}")

    # 计算并写入汇总
    summary = compute_summary(results)
    summary_path = os.path.join(args.output, 'summary.csv')
    write_summary(summary, summary_path)
    print(f"Written summary to {summary_path}")

    # 打印汇总到控制台
    print()
    print("=" * 64)
    print("SUMMARY")
    print("=" * 64)
    for key, value in summary.items():
        print(f"  {key}: {value}")
    print("=" * 64)


if __name__ == '__main__':
    main()
