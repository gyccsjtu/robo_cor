#!/bin/bash
# 扫 SEP=3 下 s-s 最近值，输出到文件
for sd in $(seq 1 24); do
  SEP_TARGET_M=3 python -c "
import math, os, sys
sys.path.insert(0, '.')
import mission_time as MT
import task_allocator as TA
from strategy_compare import MapGrid
MT.SLOT_MODE = 'chase'
MT.SEP_TARGET_M = 3.0
g = MapGrid(TA.METADATA)
sim = TA.AllocSim(g, strategy='dynamic', targets=6, seed=$sd)
cur = [None]
def hook(s):
    eng = s._engaged()
    pos = {u: tuple(p) for u, p in s.uavs.items()}
    for ui in sorted(pos):
        for vi in sorted(pos):
            if vi <= ui: continue
            dd = math.hypot(pos[ui][0]-pos[vi][0], pos[ui][1]-pos[vi][1])
            if dd >= 1.5: continue
            eu, ev = eng.get(ui), eng.get(vi)
            if not (eu is None and ev is None): continue
            if cur[0] is None or dd < cur[0][0]:
                cur[0] = (dd, s.t, ui, vi)
sim.run(300.0, on_step=lambda s: (s._observe_metrics(), hook(s)))
if cur[0]:
    print('seed=%d s-s最近 %.3f m t=%.1f %s-%s' % ($sd, cur[0][0], cur[0][1], cur[0][2], cur[0][3]), flush=True)
" 2>&1 | grep "s-s"
done
