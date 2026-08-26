#!/bin/bash
# 컨테이너를 띄우고 tmux 세션(rviz2 / rsp / teleop_twist_keyboard / joystick / 셸)에 붙는다.
set -e
cd "$(dirname "$0")"

export GID=$(id -g)
export INPUT_GID=$(getent group input | cut -d: -f3)   # 조이스틱 장치 그룹

xhost +local:docker

docker compose build --provenance=false --sbom=false
docker compose up -d
exec docker compose exec ros bash -lc './start.sh'
