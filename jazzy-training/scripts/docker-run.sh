#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CYCLONEDDS_SRC="${SCRIPT_DIR}/config/cyclonedds.xml"
CYCLONEDDS_CONTAINER_PATH="/home/aw/cyclonedds.xml"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] IMAGE [COMMAND...]

研修用 CycloneDDS 設定（lo 限定）をマウントして Docker 起動します。

Options:
  --no-host-network   host ネットワークを使わない
  --help              ヘルプ表示

例:
  $(basename "$0") ghcr.io/autowarefoundation/autoware:universe-jazzy
EOF
}

USE_HOST_NETWORK=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --no-host-network) USE_HOST_NETWORK=false; shift ;;
    -*) echo "ERROR: 不明なオプション: $1" >&2; usage >&2; exit 1 ;;
    *) break ;;
  esac
done

[[ $# -ge 1 ]] || { usage >&2; exit 1; }

IMAGE="$1"; shift

[[ -f "${CYCLONEDDS_SRC}" ]] || {
  echo "ERROR: ${CYCLONEDDS_SRC} がありません。先に ./setup.sh を実行してください。" >&2
  exit 1
}

DOCKER_ARGS=(
  --rm -it
  -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
  -e CYCLONEDDS_URI=file://${CYCLONEDDS_CONTAINER_PATH}
  -v "${CYCLONEDDS_SRC}:${CYCLONEDDS_CONTAINER_PATH}:ro"
)
[[ "${USE_HOST_NETWORK}" == "true" ]] && DOCKER_ARGS+=(--network host)

exec docker run "${DOCKER_ARGS[@]}" "${IMAGE}" "$@"
