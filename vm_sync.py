#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""VM 同步助手：用 paramiko 走密码认证，避免 sshpass 缺失。

用法：
  python vm_sync.py check                # 列两处副本的 md5，对比本地
  python vm_sync.py push <本地文件> <远端路径>
  python vm_sync.py cmd "<shell 命令>"

远端基址：~/team_ws/robocup/。**两份副本都要同步** ——
  scripts/vm/                     （旧路径，sys.path 里先插入）
  src/robocup_swarm/scripts/      （后插入 → 优先级更高，实际 import 的是它）
"""
import hashlib
import os
import sys

import paramiko

HOST = "192.168.42.129"
USER = "ros"  # VM 真实用户名是 ros（密码 gycsjtu985 对 ros 有效；gycsjtu 认证失败）
PWD = "gycsjtu985"
WS = "/home/ros/team_ws/robocup"

COPIES = [
    WS + "/scripts/vm",
    WS + "/src/robocup_swarm/scripts",
]


def connect():
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username=USER, password=PWD, timeout=15,
              look_for_keys=False, allow_agent=False)
    return c


def run(c, cmd):
    _in, out, err = c.exec_command(cmd)
    o = out.read().decode("utf-8", "replace")
    e = err.read().decode("utf-8", "replace")
    rc = out.channel.recv_exit_status()
    return rc, o, e


def md5_local(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for blk in iter(lambda: fh.read(65536), b""):
            h.update(blk)
    return h.hexdigest()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    op = sys.argv[1]
    c = connect()
    try:
        if op == "cmd":
            rc, o, e = run(c, sys.argv[2])
            print(o, end="")
            if e.strip():
                print("[stderr]", e, end="")
            return rc

        if op == "check":
            names = sys.argv[2:] or ["strategy_compare.py", "mission_time.py",
                                     "task_allocator.py"]
            print("本地：")
            for n in names:
                if os.path.exists(n):
                    print("  %-24s %s" % (n, md5_local(n)))
                else:
                    print("  %-24s (本地无)" % n)
            print("远端：")
            for d in COPIES:
                for n in names:
                    rc, o, e = run(c, "md5sum %s/%s 2>/dev/null" % (d, n))
                    o = o.strip()
                    tag = "OK " if o else "缺失"
                    print("  [%s] %s" % (tag, o or ("%s/%s" % (d, n))))
            return 0

        if op == "push":
            local, remote = sys.argv[2], sys.argv[3]
            sftp = c.open_sftp()
            sftp.put(local, remote)
            sftp.close()
            rc, o, e = run(c, "md5sum %s" % remote)
            print("已推送 %s -> %s" % (local, remote))
            print("  远端 md5 %s" % o.strip())
            print("  本地 md5 %s" % md5_local(local))
            return 0

        if op == "pushall":
            # 一次把本地文件推到两处副本
            local = sys.argv[2]
            base = os.path.basename(local)
            sftp = c.open_sftp()
            for d in COPIES:
                rp = "%s/%s" % (d, base)
                try:
                    sftp.put(local, rp)
                    rc, o, e = run(c, "md5sum %s" % rp)
                    print("  %-46s %s" % (rp, o.strip().split()[0]))
                except Exception as ex:
                    print("  %-46s 失败: %s" % (rp, ex))
            sftp.close()
            print("本地 %s md5 %s" % (base, md5_local(local)))
            return 0

        print("未知操作 %s" % op)
        return 2
    finally:
        c.close()


if __name__ == "__main__":
    sys.exit(main())
