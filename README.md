# ros_docker

ROS 2 Jazzy 최소 환경 — **rviz2 · teleop_twist_keyboard · teleop_twist_joy ·
robot_description(spot)** 뿐이다. GPU 시뮬레이터도, 무거운 인식 스택도 없다.

용도는 하나다: [**quadruped_docker**](https://github.com/GuideDog-ETRI/quadruped_docker)
(Isaac Sim 위의 Spot 사족보행 시뮬레이터) 의 **조작기 + 시각화 창구**.
시뮬레이터는 `/cmd_vel` 을 받아 걷고 센서를 발행하고, 이 컨테이너는 그 `/cmd_vel` 을
키보드·PS5 패드로 만들어 보내고 발행된 센서·TF·로봇 형상을 rviz2 로 본다.
두 컨테이너는 **`ROS_DOMAIN_ID=1`** 로 서로를 찾는다 (아래 [6절](#6-quadruped_docker-와-함께-쓰기)).

```
┌─ ros_docker ────────────┐        ROS 2 DDS         ┌─ quadruped_docker ──────┐
│ teleop_keyboard  ──┐    │   ROS_DOMAIN_ID = 1      │  Isaac Sim 5.1 + Spot   │
│ teleop_twist_joy ──┴──▶ │ ── /cmd_vel ───────────▶ │  보행 정책 (RL)           │
│ robot_state_publisher   │ ◀── /clock /odom /tf ─── │  Ouster · MID360 ·      │
│ rviz2                   │ ◀── /joint_states ────── │  RealSense · LaserScan  │
└─────────────────────────┘ ◀── 센서 토픽 ──────────── └─────────────────────────┘
```

`quadruped_docker` 없이 단독으로 띄워도 컨테이너는 정상 기동한다. 다만 rviz2 가
sim 시간(`/clock`)을 기다리며 멈춘 것처럼 보이는데, 그게 정상이다
([9절 문제 해결](#9-문제-해결) 참조).

---

## 1. 요구 사항

| 항목 | 요구 |
|---|---|
| OS | Ubuntu 24.04 (22.04 도 동일 절차) |
| GPU | NVIDIA (rviz2 GPU 렌더링). 드라이버 + Container Toolkit 필요 |
| 디스크 | 약 15GB (`osrf/ros:jazzy-desktop-full` 이미지가 대부분) |
| 화면 | X11 데스크톱 (Ubuntu 기본 Wayland 도 XWayland 로 동작) |
| 선택 | PS5 DualSense 패드 ([5절](#5-ps5-dualsense-패드-선택)) |

---

## 2. 최초 설치 (Ubuntu 를 처음 설치한 경우)

2-1 ~ 2-5 를 순서대로 한 번만 하면 된다. 이미 설치된 항목은 건너뛴다.
`quadruped_docker` 를 이미 설치했다면 2-1 ~ 2-3 은 끝난 상태이므로 **2-4 로 건너뛴다**.

### 2-1. NVIDIA 그래픽 드라이버

```bash
sudo ubuntu-drivers install       # 권장 드라이버 자동 설치
sudo reboot
```

재부팅 후 확인 — GPU 이름과 드라이버 버전이 표로 나오면 성공:

```bash
nvidia-smi
```

### 2-2. Docker Engine

```bash
# Docker 공식 apt 저장소 등록
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Docker 설치
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# sudo 없이 docker 를 쓰기 위해 내 계정을 docker 그룹에 추가
sudo usermod -aG docker $USER
```

**그룹 추가 후 반드시 로그아웃 → 재로그인** (또는 재부팅) 해야 적용된다. 확인:

```bash
docker run --rm hello-world
```

### 2-3. NVIDIA Container Toolkit (컨테이너에서 GPU 사용)

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

확인 — 컨테이너 안에서 `nvidia-smi` 가 뜨면 성공:

```bash
docker run --rm --gpus all ubuntu nvidia-smi
```

### 2-4. X11 접근 허용

컨테이너의 rviz2 가 호스트 화면을 쓰려면 필요하다. `run.sh` 가 매번 자동으로
실행하므로 보통 따로 할 일은 없다 (수동 확인용):

```bash
xhost +local:docker
```

### 2-5. 이 저장소 받기

```bash
sudo apt-get install -y git
git clone https://github.com/OnVLM-Nav/ros_docker.git ~/ros_docker
cd ~/ros_docker
```

서브모듈은 없다 — `spot_description` (공식 Spot URDF, MIT) 은 저장소에 그대로 들어 있다.

---

## 3. 빠른 시작

```bash
cd ~/ros_docker
./run.sh
```

`run.sh` 가 하는 일은 네 줄이다:

1. `GID` · `INPUT_GID` (호스트 `input` 그룹) 를 export — 컨테이너 사용자를
   호스트 UID/GID 로 맞추고 조이스틱 장치 권한을 붙이기 위한 build arg
2. `xhost +local:docker` — X11 접근 허용
3. `docker compose build` → `up -d` — 이미지 빌드 후 컨테이너 백그라운드 기동
4. `docker compose exec ros bash -lc './start.sh'` — 워크스페이스가 안 빌드돼 있으면
   먼저 빌드하고, tmux 세션 `ros` 에 접속

**최초 실행은 이미지 빌드에 10~20분** 걸린다 (`osrf/ros:jazzy-desktop-full` 내려받기).
두 번째부터는 몇 초다. `Dockerfile`·`compose.yml` 을 안 고쳤으면 `build` 는 캐시로 즉시 끝난다.

### 3-1. 최초 실행 — 워크스페이스 자동 빌드

`build/`·`install/` 은 저장소에 없으므로 처음 클론한 직후에는 `spot_description` 이
빌드돼 있지 않다. **`start.sh` 가 이를 감지해 tmux 를 띄우기 전에 자동으로 빌드한다:**

```
[start] 최초 실행 — 워크스페이스 빌드 중 (1~2분)…
Starting >>> spot_description
Finished <<< spot_description [1.14s]
```

수동으로 `cbuild` 를 칠 필요는 없다. 두 번째 실행부터는 이 단계가 건너뛰어진다
(`install/local_setup.bash` 존재 여부로 판단). 소스를 고쳐 다시 빌드하고 싶으면
pane 4 에서 `cbuild` 를 직접 부른다.

### 3-2. tmux 화면 구성

창 하나에 pane 5개 (위→아래, 맨 아래 셸이 화면의 50% · 나머지 12.5% 씩):

| pane | 이름 | 내용 |
|---|---|---|
| 0 | `rviz2` | `rviz2 -d rviz/map.rviz --ros-args -p use_sim_time:=true` |
| 1 | `robot_state_publisher` | `/robot_description` 발행 (spot URDF, `frame_prefix:=spot/`) |
| 2 | `teleop_keyboard` | `ros2 run teleop_twist_keyboard teleop_twist_keyboard` |
| 3 | `joystick` | `./joystick-run` — PS5 패드 teleop (`teleop_twist_joy` + `joy_node`) |
| 4 | `shell` | 빈 셸 — `tmux kill-session -t ros` 가 미리 타이핑돼 있어 **엔터만 치면 세션 종료** |

pane 이름은 경계선 위에 표시된다 (`pane-border-status`). 각 pane 은 `<명령>; exec bash`
로 띄우므로 `Ctrl-c` 를 누르면 pane 이 사라지지 않고 그 자리에 bash 가 남는다 —
↑ 로 명령을 불러 재실행하면 된다.

마우스가 켜져 있다 — 클릭으로 pane 선택, 경계 드래그로 크기 조절.

### 3-3. tmux 최소 조작법 (처음 쓰는 경우)

`Ctrl-b` 를 누르고 손을 뗀 뒤 다음 키를 누른다 (`Ctrl-b` 를 계속 누르고 있지 않는다):

| 키 | 동작 |
|---|---|
| `Ctrl-b` `↑` / `↓` | 위/아래 pane 으로 이동 |
| `Ctrl-b` `z` | 현재 pane 을 전체 화면으로 확대 / 복귀 |
| `Ctrl-b` `d` | 세션에서 빠져나오기 (**detach** — 노드는 계속 돌아간다) |
| `Ctrl-b` `[` | 스크롤 모드 (`q` 로 나옴). 마우스 휠로도 스크롤된다 |

detach 후 다시 붙기 / 완전히 내리기:

```bash
./run.sh                                            # 같은 세션에 재접속
docker compose exec ros bash -lc 'tmux kill-session -t ros'   # 세션만 종료
docker compose down                                 # 컨테이너 종료
```

### 3-4. 컨테이너 안에서 쓰는 명령

`workspace/rosenv.sh` 가 셸 시작 시 자동 소싱된다.

| 명령 | 설명 |
|---|---|
| `cbuild [pkg]` | 워크스페이스 빌드 (`colcon build --symlink-install`, Release) 후 오버레이 재소싱 |
| `./joystick-run` | PS5 패드 teleop 단독 실행 |
| `ros2 topic list` | 통신 확인 — sim 이 떠 있으면 sim 토픽들이 함께 보인다 |

---

## 4. 구성 요약

- **`ROS_DOMAIN_ID=1`** — `quadruped_docker` 와 같은 값. 바꾸려면 양쪽을 함께 바꾼다
  (`ROS_DOMAIN_ID=7 ./run.sh` 처럼 환경변수로 덮어쓸 수 있다).
- **`RMW_IMPLEMENTATION=rmw_fastrtps_cpp`** — 양쪽 동일. 미들웨어가 다르면 통신되지 않는다.
- **`network_mode: host` · `ipc: host`** — DDS 디스커버리와 공유 메모리 전송.
- 워크스페이스: `ros_docker/workspace` → 컨테이너 `/home/ros/ws` (bind-mount).
  호스트에서 편집한 파일이 즉시 반영된다. 빌드는 컨테이너 안에서 `cbuild`.
- 호스트 조이스틱은 `/dev/input` 을 디렉토리째 넘겨 hot-plug 도 보인다.
- 컨테이너 사용자는 `ros` (호스트 UID/GID 와 동일) — bind-mount 파일 권한이 어긋나지 않는다.

### 프레임 접두어 규약 (`spot/`)

프레임 접두어는 rsp 의 `frame_prefix:=spot/` + rviz RobotModel `TF Prefix: spot`
조합으로 맞춘다. xacro `tf_prefix` 를 쓰면 **조인트 이름까지** `spot/…` 로 바뀌어
sim 의 `/joint_states` (`front_left_hip_x` …) 와 매칭이 깨지고 다리 TF 가 발행되지
않는다 (rviz RobotModel Error).

- 관절 자세는 sim 의 `/joint_states`, 위치는 sim 의 `base_link → spot/body` static TF 에서 온다
- `frame_prefix` 는 발행 TF 이름만 바꾸므로 URDF 안의 `base_link` 와 sim 의 `base_link` 가 충돌하지 않는다

---

## 5. PS5 DualSense 패드 (선택)

컨테이너를 띄우기 **전에** 호스트에 PS5 DualSense 를 연결해 두면 (USB 또는 블루투스
페어링) pane 3 의 `./joystick-run` 이 그대로 잡아 `/cmd_vel` 을 낸다. 없어도 무방하다 —
`joy_node` 가 장치를 못 찾고 재시도할 뿐 나머지 pane 은 정상 동작한다.
컨테이너를 띄운 뒤 연결했다면 pane 3 에서 `Ctrl-c` → `./joystick-run` 재실행.

- 호스트에서 `ls /dev/input/js*` 로 인식 확인 (`/dev/input` 을 통째로 넘기므로 hot-plug 도 보인다)
- 블루투스 페어링은 Ubuntu 설정 → Bluetooth 에서, 패드의 **Create + PS 버튼 동시 길게**
  눌러 페어링 모드(라이트바 점멸)로 진입시킨 뒤 목록에서 선택한다
- 장치 권한은 `run.sh` 가 호스트 `input` 그룹 GID 를 build arg 로 넘겨 컨테이너 사용자에 붙인다
- `joystick-run` = `ros2 launch teleop_twist_joy teleop-launch.py config_filepath:=ps5_custom.config.yaml`
  (런치가 `joy_node` 도 함께 띄운다)

`workspace/ps5_custom.config.yaml` 내용 요약:

| 항목 | 값 |
|---|---|
| enable (일반) | **L1** (버튼 4) — 누르는 동안에만 명령 전송 (`require_enable_button: true`) |
| enable (터보) | **R1** (버튼 5) |
| 전후 · 좌우 | 왼쪽 스틱 (축 1 · 축 0) → `linear.x` · `linear.y` |
| 회전 | 오른쪽 스틱 좌우 (축 3) → `angular.z` |
| 속도 (일반) | linear 0.7, yaw 0.5 |
| 속도 (터보) | linear 1.5, yaw 1.0 |

`teleop_twist_joy` 의 ps5 프리셋은 enable 이 R2(버튼 7)지만 여기서는 **L1/R1** 로
바꿔 놨다. **enable 버튼을 누르지 않으면 스틱을 움직여도 `/cmd_vel` 이 나가지 않는다** —
패드를 놓쳤을 때 로봇이 계속 걷는 것을 막는 안전 장치다.
버튼·축·스케일은 그 yaml 만 고치고 pane 3 을 재실행하면 된다 (빌드 불필요).

---

## 6. quadruped_docker 와 함께 쓰기

두 컨테이너는 **같은 호스트에서** `network_mode: host` · `ROS_DOMAIN_ID=1` ·
`rmw_fastrtps_cpp` 로 붙는다. 별도 브리지나 설정 파일은 없다 — 그냥 둘 다 띄우면 된다.

```bash
# 터미널 A — 시뮬레이터 (Isaac Sim GUI 가 뜬다)
cd ~/quadruped_docker && ./run_spot_indoor_sim.sh

# 터미널 B — 조작 + 시각화
cd ~/ros_docker && ./run.sh
```

순서는 상관없지만 **sim 을 먼저 띄우는 쪽이 편하다** — rviz2 가 `use_sim_time:=true`
라 `/clock` 이 오기 시작해야 화면을 그린다.

### 주고받는 것

| 방향 | 토픽 / 타입 | 비고 |
|---|---|---|
| ros_docker → sim | `/cmd_vel` (`geometry_msgs/Twist`) | 키보드 pane 2 또는 PS5 pane 3. vx·vy·wz |
| sim → ros_docker | `/clock` (`rosgraph_msgs/Clock`) | 모든 노드가 `use_sim_time:=true` 로 이 시간을 쓴다 |
| sim → ros_docker | `/tf`, `/tf_static` | `map → odom → base_link` + 센서 extrinsic, `base_link → spot/body` |
| sim → ros_docker | `/joint_states` (`sensor_msgs/JointState`) | rviz RobotModel 의 다리 자세 |
| sim → ros_docker | `/odom` (`nav_msgs/Odometry`) | rviz Odometry 화살표 |
| sim → ros_docker | `/ouster/points`, `/livox/lidar` (`PointCloud2`) | Ouster OS1 · Livox MID-360 |
| sim → ros_docker | `/ouster/scan` (`LaserScan`) | 2D 스캔 (lidar 0° ring) |
| sim → ros_docker | `/camera/camera/color/image_raw`, `.../aligned_depth_to_color/image_raw` | RealSense D455 호환 |
| ros_docker → (rviz) | `/robot_description` | pane 1 의 `robot_state_publisher` 가 발행 |

`rviz/map.rviz` 는 Fixed Frame 이 `map` 이고 위 토픽들의 Display 가 미리 켜져 있다
(Grid · Axes · TF · RobotModel · PointCloud2 ×2 · Image ×2 · Odometry, 뷰는
ThirdPersonFollower). `map` 프레임은 sim 이 발행하므로 **sim 이 떠야 rviz 가 정상 표시된다.**

### 걷게 하기

1. pane 3 (joystick): 패드 **L1 을 누른 채** 왼쪽 스틱을 밀면 전진, 오른쪽 스틱 좌우로 제자리 회전.
   R1 은 터보.
2. 패드가 없으면 pane 2 (teleop_keyboard) 를 클릭해 포커스를 준 뒤 `i`(전진) ·
   `j`/`l`(회전) · `k`(정지), `q`/`z` 로 속도 배율 조절. **그 pane 이 포커스를 가진
   동안에만** 키가 먹는다.
3. 두 pane 이 같은 `/cmd_vel` 에 발행한다 — 동시에 조작하면 서로 덮어쓴다. 한 번에 하나만 쓴다.

> 보행 정책·씬 선택·센서 on/off 등 sim 쪽 설정은 `quadruped_docker/run.sh` 상단
> 설정 절에서 바꾼다 (해당 저장소 README 4절).

---

## 7. 파일 구조

```
ros_docker/
├── Dockerfile          osrf/ros:jazzy-desktop-full + teleop/joy + 호스트 UID 사용자
├── compose.yml         host network·ipc, GPU, /dev/input, X11, ROS_DOMAIN_ID=1
├── run.sh              build → up -d → tmux 세션 접속 (호스트에서 실행)
└── workspace/                       (컨테이너 /home/ros/ws 로 bind-mount)
    ├── start.sh        최초 빌드 + tmux pane 5개 구성 (컨테이너 안에서 run.sh 가 실행)
    ├── rosenv.sh       ROS 환경 + 오버레이 소싱, cbuild 함수 (셸 시작 시 자동)
    ├── joystick-run    teleop_twist_joy + joy_node 런치
    ├── ps5_custom.config.yaml   PS5 버튼/축 매핑
    ├── rviz/map.rviz   rviz2 설정 (Fixed Frame: map)
    └── src/spot_description/    공식 Spot URDF·메시 (MIT, bdaiinstitute)
```

`build/`·`install/`·`log/`·`core` 는 `.gitignore` 대상이다.

---

## 8. 이미지 레이어 캐시

`Dockerfile` 은 변경 빈도 순으로 레이어를 쌓는다:

1. apt: 툴링 + teleop 패키지 (`tmux`, `teleop_twist_keyboard/joy`, `joy`) — 거의 변경 없음
2. 호스트 UID/GID/`input` GID 사용자 생성 — UID/GID 변경 시만 무효화
3. `package.xml` **만** 선복사 → `rosdep install` — 소스 코드 변경은 이 레이어를 안 건드린다
4. 셸 환경 (`.bashrc`, `.bash_profile`)

apt · rosdep 캐시는 BuildKit `--mount=type=cache` 로 빌드 간 재사용된다.

> `src/` 에 ROS 패키지를 추가하면 Dockerfile 의 3번 레이어에
> `COPY .../<pkg>/package.xml ...` 한 줄을 추가한다. 깜빡하면 그 패키지 의존성이
> 설치되지 않는다.

---

## 9. 문제 해결

| 증상 | 원인 / 해결 |
|---|---|
| rviz2 창이 뜨는데 아무것도 안 보이고 좌하단 시간이 0 | 정상 — `use_sim_time:=true` 라 `/clock` 을 기다린다. `quadruped_docker` 를 띄우면 그려진다 |
| rviz2 `Fixed frame [map] does not exist` | 같은 이유. `map → odom` TF 는 sim 이 발행한다 |
| pane 1 이 `Package 'spot_description' not found` | 자동 빌드가 실패했다. pane 4 에서 `cbuild` 를 직접 돌려 에러를 확인한다 → [3-1절](#3-1-최초-실행--워크스페이스-자동-빌드) |
| `docker: permission denied ... /var/run/docker.sock` | `docker` 그룹 추가 후 로그아웃/재로그인을 안 했다 → [2-2절](#2-2-docker-engine) |
| `could not select device driver "nvidia"` | NVIDIA Container Toolkit 미설치/미설정 → [2-3절](#2-3-nvidia-container-toolkit-컨테이너에서-gpu-사용) |
| `OCI runtime ... libnvidia-*.so: no such file` | 드라이버 업데이트 후 CDI 스펙이 낡았다: `sudo nvidia-ctk cdi generate --output=/var/run/cdi/nvidia.yaml` |
| `Authorization required, but no authorization protocol specified` (rviz2 실행 실패) | 호스트에서 `xhost +local:docker` |
| sim 토픽이 `ros2 topic list` 에 안 보인다 | 두 컨테이너의 `ROS_DOMAIN_ID` 와 `RMW_IMPLEMENTATION` 이 같은지 확인. 다른 PC 면 같은 서브넷이어야 한다 |
| 패드 스틱을 움직여도 로봇이 안 움직인다 | **L1 (enable) 을 누른 채** 움직여야 한다 → [5절](#5-ps5-dualsense-패드-선택) |
| 키보드 teleop 이 안 먹는다 | pane 2 를 클릭해 포커스를 준다 (그 pane 이 활성일 때만 키 입력을 받는다) |
| 조이스틱 장치가 컨테이너에 안 보인다 | 호스트에서 `ls /dev/input/js*` 확인. 컨테이너 기동 전 연결이면 확실하다 |
| tmux 세션이 이상해졌다 | `docker compose exec ros bash -lc 'tmux kill-session -t ros'` 후 `./run.sh` |

---

## 라이선스

`workspace/src/spot_description` 은 [bdaiinstitute/spot_description](https://github.com/bdaiinstitute/spot_description)
(MIT) 의 사본이다. 그 외 파일은 이 저장소의 라이선스를 따른다.
