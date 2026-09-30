#!/bin/bash
# -*- coding: utf-8 -*-
"""快速同步代码到新服务器

用法:
  ./sync_to_server.sh <服务器IP> [用户名]

示例:
  ./sync_to_server.sh 192.168.1.100
  ./sync_to_server.sh 192.168.1.100 ros
"""

SERVER=$1
USER=${2:-ros}

if [ -z "$SERVER" ]; then
    echo "用法: $0 <服务器IP> [用户名]"
    echo "示例: $0 192.168.1.100 ros"
    exit 1
fi

echo "同步代码到 $USER@$SERVER ..."

# 核心 Python 文件
rsync -avz --progress \
    --exclude='*.pyc' \
    --exclude='__pycache__' \
    --exclude='*.log' \
    --exclude='*.txt' \
    *.py \
    $USER@$SERVER:~/team_ws/robocup/

echo "同步完成!"
echo ""
echo "下一步: 登录服务器"
echo "  ssh $USER@$SERVER"
echo ""
echo "然后运行:"
echo "  cd ~/team_ws/robocup"
echo "  export ROBOCUP_WS=~/team_ws/robocup"
echo "  python mission_time.py --runs 5"
