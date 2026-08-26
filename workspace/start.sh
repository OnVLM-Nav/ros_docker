#!/bin/bash
# tmux 창 하나에 pane 5개 (위→아래, 아래 셸이 50% · 나머지 12.5% 씩):
#   0 rviz2  1 robot_state_publisher(/robot_description)  2 teleop_twist_keyboard
#   3 joystick-run  4 빈 셸
# 각 pane 은 '<명령>; exec bash' 라 Ctrl-c 로 명령만 죽이고 셸이 남는다 (pane 유지·재실행 가능).
set -e
S=ros
cd "${ROS_WORKSPACE_DIR:-$HOME/ws}"

# 최초 실행 — 오버레이가 없으면 여기서 빌드한다. 안 하면 pane 1 의
# robot_state_publisher 가 `ros2 pkg prefix spot_description` 실패로 죽는다.
# 빌드 플래그 정본은 rosenv.sh 의 cbuild 하나 — 셸 함수라 상속되지 않으므로 재소싱한다.
if [[ ! -r install/local_setup.bash ]]; then
    echo "[start] 최초 실행 — 워크스페이스 빌드 중 (1~2분)…"
    source rosenv.sh
    cbuild
fi

# 프레임 접두어는 rsp 의 frame_prefix 로 준다 (xacro tf_prefix 가 아니다):
#   xacro tf_prefix 는 *조인트 이름까지* 바꿔 sim 의 /joint_states (front_left_hip_x …)
#   와 매칭이 깨지고, 다리 TF 가 발행되지 않아 rviz RobotModel 이 Error 를 낸다.
#   frame_prefix 는 발행되는 TF 프레임 이름만 spot/* 으로 바꾼다 —
#   sim 의 static TF base_link → spot/body 와 이어지고, URDF 안 base_link 와도 안 겹친다.
#   (rviz RobotModel 은 map.rviz 의 "TF Prefix: spot" 으로 같은 규약을 본다)
RSP='xacro "$(ros2 pkg prefix spot_description)/share/spot_description/urdf/spot.urdf.xacro"'
RSP+=' > /tmp/spot.urdf &&'
RSP+=' ros2 run robot_state_publisher robot_state_publisher /tmp/spot.urdf'
RSP+=' --ros-args -p use_sim_time:=true -p frame_prefix:=spot/; exec bash'

if ! tmux has-session -t "$S" 2>/dev/null; then
    tmux new-session -d -s "$S" -n main \
        'rviz2 -d rviz/map.rviz --ros-args -p use_sim_time:=true; exec bash'
    # -l 은 "새로 만들 pane" 의 크기 → 위쪽 pane 이 나머지를 갖는다
    tmux split-window -v -l 87% -t "$S:main.0" "$RSP"
    tmux split-window -v -l 86% -t "$S:main.1" \
        'ros2 run teleop_twist_keyboard teleop_twist_keyboard; exec bash'
    tmux split-window -v -l 83% -t "$S:main.2" './joystick-run; exec bash'
    tmux split-window -v -l 80% -t "$S:main.3"

    # pane 이름을 경계선에 표시
    tmux set -t "$S" pane-border-status top
    tmux set -t "$S" pane-border-format ' #{pane_index}: #{pane_title} '
    i=0
    for t in rviz2 robot_state_publisher teleop_keyboard joystick shell; do
        tmux select-pane -T "$t" -t "$S:main.$i"; i=$((i+1))
    done

    # 맨 아래 셸엔 종료 명령을 미리 타이핑해 둔다 (엔터만 치면 세션 종료)
    tmux send-keys -t "$S:main.4" "tmux kill-session -t $S"
    tmux select-pane -t "$S:main.4"
fi
tmux set -g mouse on   # 클릭으로 pane 선택·경계 드래그로 크기 조절
exec tmux attach -t "$S"
