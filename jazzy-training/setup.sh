#!/usr/bin/env bash
# Autoware 研修用セットアップ（autoware_training / jazzy-training）
#
# 現時点の Jazzy / Autoware 向けワークアラウンド（将来 upstream で解消される可能性あり）:
#   - CycloneDDS ParticipantIndex=none … 32 ノード制限の回避
#   - NetworkInterface=lo … 意図しないインターフェースへの DDS 漏洩防止
#   - lo マルチキャスト / sysctl 等の DDS 向けチューニング
#
# 配置場所: <autoware_training>/jazzy-training/setup.sh
# 使い方  : cd jazzy-training && ./setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="${SCRIPT_DIR}/config/cyclonedds.xml"
CONFIG_DIR="${HOME}/.config/ros-jazzy-training"
CYCLONEDDS_DEST="${CONFIG_DIR}/cyclonedds.xml"
ENV_SH="${SCRIPT_DIR}/env.sh"
BASHRC_MARKER_BEGIN="# >>> ROS 2 Jazzy training env (jazzy-training/setup.sh) >>>"
BASHRC_MARKER_END="# <<< ROS 2 Jazzy training env <<<"

log() { echo "[setup] $*"; }
warn() { echo "[setup] WARNING: $*" >&2; }

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "[setup] ERROR: ファイルが見つかりません: $1" >&2
    exit 1
  fi
}

check_ubuntu_version() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${VERSION_ID:-}" != "24.04" ]]; then
      warn "Ubuntu 24.04 以外 (${PRETTY_NAME:-unknown}) で実行しています。"
      warn "ROS 2 Jazzy は Ubuntu 24.04 向けです。"
    fi
  fi
}

install_cyclonedds_config() {
  require_file "${CONFIG_SRC}"
  mkdir -p "${CONFIG_DIR}"
  cp "${CONFIG_SRC}" "${CYCLONEDDS_DEST}"
  chmod 644 "${CYCLONEDDS_DEST}"
  log "CycloneDDS 設定を配置しました: ${CYCLONEDDS_DEST}"
}

write_env_sh() {
  cat > "${ENV_SH}" <<EOF
#!/usr/bin/env bash
# ROS 2 Jazzy 研修環境変数（jazzy-training/setup.sh が生成）
# 使い方: source ${ENV_SH}

export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file://${CYCLONEDDS_DEST}
unset ROS_LOCALHOST_ONLY
EOF
  chmod 644 "${ENV_SH}"
  log "環境変数ファイルを生成しました: ${ENV_SH}"
}

configure_bashrc() {
  local bashrc="${HOME}/.bashrc"
  touch "${bashrc}"

  if grep -qF "${BASHRC_MARKER_BEGIN}" "${bashrc}"; then
    sed -i "/${BASHRC_MARKER_BEGIN}/,/${BASHRC_MARKER_END}/d" "${bashrc}"
  fi

  cat >> "${bashrc}" <<EOF

${BASHRC_MARKER_BEGIN}
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file://${CYCLONEDDS_DEST}
unset ROS_LOCALHOST_ONLY
${BASHRC_MARKER_END}
EOF
  log "~/.bashrc に環境変数を追記しました"
}

remove_ros_localhost_only() {
  local bashrc="${HOME}/.bashrc"
  if [[ -f "${bashrc}" ]] && grep -qE '^\s*export\s+ROS_LOCALHOST_ONLY=1' "${bashrc}"; then
    sed -i '/^\s*export\s\+ROS_LOCALHOST_ONLY=1/d' "${bashrc}"
    warn "ROS_LOCALHOST_ONLY=1 を ~/.bashrc から削除しました"
  fi
}

enable_lo_multicast() {
  if ip link set lo multicast on 2>/dev/null; then
    log "lo インターフェースのマルチキャストを有効化しました"
  elif command -v sudo >/dev/null 2>&1 && sudo ip link set lo multicast on 2>/dev/null; then
    log "lo インターフェースのマルチキャストを有効化しました（sudo）"
  else
    warn "lo のマルチキャスト有効化に失敗しました"
    warn "手動実行: sudo ip link set lo multicast on"
  fi
}

configure_sysctl() {
  local sysctl_conf="/etc/sysctl.d/99-ros-jazzy-training-cyclonedds.conf"
  local sysctl_content="# ROS 2 / CycloneDDS tuning (jazzy-training/setup.sh)
net.core.rmem_max=2147483647
net.ipv4.ipfrag_time=3
net.ipv4.ipfrag_high_thresh=134217728
"

  if [[ "${EUID}" -eq 0 ]]; then
    echo "${sysctl_content}" > "${sysctl_conf}"
    sysctl --system >/dev/null 2>&1 || sysctl -p "${sysctl_conf}" >/dev/null 2>&1 || true
    log "sysctl 設定を適用しました: ${sysctl_conf}"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    if echo "${sysctl_content}" | sudo tee "${sysctl_conf}" >/dev/null; then
      sudo sysctl --system >/dev/null 2>&1 || sudo sysctl -p "${sysctl_conf}" >/dev/null 2>&1 || true
      log "sysctl 設定を適用しました: ${sysctl_conf}"
      return
    fi
  fi

  warn "sysctl の永続設定をスキップしました（sudo 権限が必要）"
}

print_summary() {
  cat <<EOF

========================================
 jazzy-training セットアップ完了
========================================

このスクリプトが対応する範囲（現時点の Jazzy / Autoware 向けワークアラウンド）:
  [OK] CycloneDDS ParticipantIndex=none（32 ノード制限回避）
  [OK] NetworkInterface=lo（意図しないネットワークへの ROS トピック漏洩防止）
  [OK] Humble/Jazzy 混在ワーニングの抑制
  [OK] DDS 向け sysctl / lo マルチキャスト

このスクリプトの対象外（構築手順の他ステップで実施）:
  [ ] setup-dev-env.sh  → ROS 2 Jazzy / 依存パッケージのインストール
  [ ] vcs import        → ソース取得
  [ ] colcon build      → ビルド

  構築手順全体は jazzy-training/README.md を参照してください。
  このスクリプトは手順 2（setup-dev-env.sh の直後）で 1 回実行します。

設定ファイル:
  CycloneDDS : ${CYCLONEDDS_DEST}
  環境変数   : ${ENV_SH}

任意（確認・Docker 利用時）:
  ./scripts/verify-setup.sh
  ./scripts/docker-run.sh --help

注意（設定では解決できない制約）:
  - Jazzy で記録した LaneletMapBin は Humble では使えません
  - 複数 PC 間で ROS 通信する場合は lo 設定の変更が必要です

詳細: jazzy-training/README.md
EOF
}

main() {
  log "jazzy-training セットアップを開始します..."
  check_ubuntu_version
  install_cyclonedds_config
  write_env_sh
  remove_ros_localhost_only
  configure_bashrc
  enable_lo_multicast
  configure_sysctl

  # 現在のシェルにも即時反映
  # shellcheck source=/dev/null
  source "${ENV_SH}"

  print_summary
}

main "$@"
