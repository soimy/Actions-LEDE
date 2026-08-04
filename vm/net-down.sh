#!/usr/bin/env bash
# Tear down LAN tap and WAN macvtap. Optionally remove the NM bridge.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

REMOVE_BRIDGE="${1:-}"

if [[ -f "${STATE_DIR}/net.env" ]]; then
  # shellcheck disable=SC1091
  source "${STATE_DIR}/net.env"
fi

info "清理虚拟网卡..."
if ip link show "${LAN_TAP}" &>/dev/null; then
  run_root ip link set "${LAN_TAP}" nomaster 2>/dev/null || true
  run_root ip link delete "${LAN_TAP}" 2>/dev/null || true
  info "已删除 ${LAN_TAP}"
fi

if ip link show "${WAN_MACVTAP}" &>/dev/null; then
  run_root ip link delete "${WAN_MACVTAP}" 2>/dev/null || true
  info "已删除 ${WAN_MACVTAP}"
fi

if [[ "${REMOVE_BRIDGE}" == "--bridge" || "${REMOVE_BRIDGE}" == "all" ]]; then
  if nmcli -t -f NAME connection show 2>/dev/null | grep -qx "${LAN_BR}"; then
    run_root nmcli connection down "${LAN_BR}" 2>/dev/null || true
    run_root nmcli connection delete "${LAN_BR}" 2>/dev/null || true
    info "已删除 NM 连接 ${LAN_BR}"
  fi
  if ip link show "${LAN_BR}" &>/dev/null; then
    run_root ip link delete "${LAN_BR}" 2>/dev/null || true
  fi
fi

rm -f "${STATE_DIR}/net.env"
info "网络清理完成"
