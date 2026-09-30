#!/usr/bin/env python3
# -*- coding: utf-8 -*-
p = "run_ablation.py"
s = open(p, encoding="utf-8").read()
print("file length:", len(s))
dup = "                for vi in sorted(pos):\n                for vi in sorted(pos):"
print("dup found:", dup in s)
