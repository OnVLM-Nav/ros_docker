# ROS 2 + 워크스페이스 오버레이 활성화 (셸 시작 시 자동 소싱)
export ROS_WORKSPACE_DIR="${HOME}/ws"

source "/opt/ros/${ROS_DISTRO}/setup.bash"
# if 문으로 감싼다 — `[[ ]] && source` 는 오버레이가 없을 때 1 을 반환해
# `set -e` 스크립트(start.sh)가 이 파일을 소싱하는 순간 죽는다.
if [[ -r "${ROS_WORKSPACE_DIR}/install/local_setup.bash" ]]; then
  source "${ROS_WORKSPACE_DIR}/install/local_setup.bash"
fi

# 워크스페이스 빌드 (spot_description)
cbuild() {
  (cd "${ROS_WORKSPACE_DIR}" && colcon build --symlink-install \
     --cmake-args -DCMAKE_BUILD_TYPE=Release "$@") \
  && source "${ROS_WORKSPACE_DIR}/install/local_setup.bash"
}
