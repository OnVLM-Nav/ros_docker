# syntax=docker/dockerfile:1
# ROS 2 Jazzy 최소 환경: rviz2 + teleop(keyboard/joy) + robot_description(spot)
FROM osrf/ros:jazzy-desktop-full
ARG ROS_DISTRO=jazzy
ENV ROS_DISTRO=${ROS_DISTRO}
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# ── 툴링 + teleop 패키지 ─────────────────────────────────────────────────────
# joy: 호스트에서 넘어온 /dev/input/js* 를 /joy 로 발행 (teleop_twist_joy 입력)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    sudo tmux vim bash-completion python3-colcon-common-extensions \
    ros-${ROS_DISTRO}-teleop-twist-keyboard \
    ros-${ROS_DISTRO}-teleop-twist-joy \
    ros-${ROS_DISTRO}-joy

# ── 호스트와 동일한 UID/GID 사용자 (bind-mount 파일 권한) ────────────────────
ARG USER_UID=1000
ARG USER_GID=1000
ARG INPUT_GID=995
RUN if getent group $USER_GID >/dev/null; then \
      groupmod -n ros $(getent group $USER_GID | cut -d: -f1); \
    else groupadd -g $USER_GID ros; fi \
  && if getent passwd $USER_UID >/dev/null; then \
      usermod -l ros -d /home/ros -m -s /bin/bash $(getent passwd $USER_UID | cut -d: -f1); \
    else useradd -m -u $USER_UID -g $USER_GID -s /bin/bash ros; fi \
  && echo "ros ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
  && (getent group $INPUT_GID >/dev/null || groupadd -g $INPUT_GID input) \
  && usermod -aG $(getent group $INPUT_GID | cut -d: -f1) ros

USER ros

# ── 워크스페이스 의존성 (package.xml 만 선복사 → 소스 변경 시 캐시 유지) ────
COPY --chown=ros:ros workspace/src/spot_description/package.xml /tmp/ws/src/spot_description/
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/tmp/rosdep-cache,sharing=locked \
    sudo chown ros:ros /tmp/rosdep-cache && sudo apt-get update && \
    ROS_HOME=/tmp/rosdep-cache rosdep update --rosdistro ${ROS_DISTRO} && \
    ROS_HOME=/tmp/rosdep-cache rosdep install --from-paths /tmp/ws/src --ignore-src -r -y \
      --rosdistro ${ROS_DISTRO} && \
    rm -rf /tmp/ws

# ── 셸 환경 (색상 프롬프트 + rosenv.sh 자동 소싱) ────────────────────────────
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /home/ros/.bashrc \
  && echo '[[ -f "${HOME}/ws/rosenv.sh" ]] && source "${HOME}/ws/rosenv.sh"' \
     | tee -a /home/ros/.bashrc >> /home/ros/.bash_profile
