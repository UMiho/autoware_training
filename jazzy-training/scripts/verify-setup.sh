#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${HOME}/.config/ros-jazzy-training"
CYCLONEDDS_DEST="${CONFIG_DIR}/cyclonedds.xml"
ENV_SH="${SCRIPT_DIR}/env.sh"

PASS=0
FAIL=0
WARN=0

ok()   { echo "  [OK]   $*"; PASS=$((PASS + 1)); }
ng()   { echo "  [NG]   $*"; FAIL=$((FAIL + 1)); }
warn() { echo "  [WARN] $*"; WARN=$((WARN + 1)); }

echo "=== jazzy-training 検証 ==="
echo

echo "[1] CycloneDDS 設定ファイル"
if [[ -f "${CYCLONEDDS_DEST}" ]]; then
  ok "設定ファイルが存在: ${CYCLONEDDS_DEST}"
else
  ng "設定ファイルがありません。先に ./setup.sh を実行してください"
fi

if [[ -f "${CYCLONEDDS_DEST}" ]]; then
  grep -q '<ParticipantIndex>none</ParticipantIndex>' "${CYCLONEDDS_DEST}" \
    && ok "ParticipantIndex=none" \
    || ng "ParticipantIndex=none が未設定"
  grep -q 'name="lo"' "${CYCLONEDDS_DEST}" \
    && ok "NetworkInterface=lo" \
    || warn "lo インターフェースが未設定"
fi

echo
echo "[2] 環境変数"
[[ -f "${ENV_SH}" ]] && source "${ENV_SH}"

[[ "${RMW_IMPLEMENTATION:-}" == "rmw_cyclonedds_cpp" ]] \
  && ok "RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" \
  || ng "RMW_IMPLEMENTATION が未設定"

[[ -n "${CYCLONEDDS_URI:-}" && -f "${CYCLONEDDS_URI#file://}" ]] \
  && ok "CYCLONEDDS_URI" \
  || ng "CYCLONEDDS_URI が未設定"

[[ -z "${ROS_LOCALHOST_ONLY:-}" ]] \
  && ok "ROS_LOCALHOST_ONLY 未設定" \
  || warn "ROS_LOCALHOST_ONLY=${ROS_LOCALHOST_ONLY}（非推奨）"

echo
echo "[3] ネットワーク"
ip link show lo 2>/dev/null | grep -q MULTICAST \
  && ok "lo マルチキャスト有効" \
  || warn "lo マルチキャスト無効 → sudo ip link set lo multicast on"

for key in net.core.rmem_max:2147483647 net.ipv4.ipfrag_time:3 net.ipv4.ipfrag_high_thresh:134217728; do
  name="${key%%:*}"
  expected="${key##*:}"
  val="$(sysctl -n "${name}" 2>/dev/null || echo "")"
  [[ "${val}" == "${expected}" ]] \
    && ok "${name}=${val}" \
    || warn "${name}=${val:-未設定}（推奨: ${expected}）"
done

echo
echo "=== 結果: OK=${PASS}  NG=${FAIL}  WARN=${WARN} ==="
[[ "${FAIL}" -gt 0 ]] && exit 1
exit 0
