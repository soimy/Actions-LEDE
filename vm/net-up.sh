#!/usr/bin/env bash
# Create LAN bridge (host ↔ LuCI) and WAN macvtap (DHCP uplink).
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_cmd ip nmcli

info "物理上联网卡: ${PHY}"
if ! ip link show "${PHY}" &>/dev/null; then
  echo "物理网卡不存在: ${PHY}" >&2
  exit 1
fi

# --- LAN bridge via NetworkManager (persistent) ---
if ! nmcli -t -f NAME connection show | grep -qx "${LAN_BR}"; then
  info "创建 NetworkManager 桥接连接 ${LAN_BR} (${LAN_HOST_IP})..."
  run_root nmcli connection add type bridge ifname "${LAN_BR}" con-name "${LAN_BR}" \
    ipv4.method manual ipv4.addresses "${LAN_HOST_IP}" \
    ipv4.gateway "" ipv4.dns "" \
    ipv6.method disabled \
    bridge.stp no \
    connection.autoconnect yes
else
  info "连接 ${LAN_BR} 已存在"
fi

# Ensure NM connection has the intended address before up
run_root nmcli connection modify "${LAN_BR}" \
  ipv4.method manual ipv4.addresses "${LAN_HOST_IP}" \
  ipv4.gateway "" ipv4.dns "" ipv6.method disabled \
  bridge.stp no connection.autoconnect yes 2>/dev/null || true

run_root nmcli connection up "${LAN_BR}" || true

# --- LAN tap for QEMU (recreated each boot; owned by invoking user) ---
# Must run AFTER nmcli connection up — NM resets bridge ports on activate.
OWNER="${SUDO_USER:-${USER}}"
if ip link show "${LAN_TAP}" &>/dev/null; then
  info "已存在 ${LAN_TAP}，重置..."
  run_root ip link set "${LAN_TAP}" nomaster 2>/dev/null || true
  run_root ip link delete "${LAN_TAP}" 2>/dev/null || true
fi

info "创建 ${LAN_TAP} → ${LAN_BR}"
run_root ip tuntap add dev "${LAN_TAP}" mode tap user "${OWNER}"
run_root ip link set "${LAN_TAP}" master "${LAN_BR}"
run_root ip link set "${LAN_TAP}" up
run_root ip link set "${LAN_BR}" up

# Ensure bridge address after enslave (NM may have left NO-CARRIER/DOWN)
if ! ip -4 addr show dev "${LAN_BR}" 2>/dev/null | grep -q "${LAN_HOST_IP%/*}"; then
  info "为 ${LAN_BR} 配置地址 ${LAN_HOST_IP}..."
  run_root ip addr replace "${LAN_HOST_IP}" dev "${LAN_BR}"
fi
run_root ip link set "${LAN_BR}" up

# --- WAN macvtap on physical NIC ---
if ip link show "${WAN_MACVTAP}" &>/dev/null; then
  info "已存在 ${WAN_MACVTAP}，重建..."
  run_root ip link delete "${WAN_MACVTAP}" 2>/dev/null || true
fi

info "创建 ${WAN_MACVTAP} (macvtap bridge on ${PHY})"
run_root ip link add link "${PHY}" name "${WAN_MACVTAP}" type macvtap mode bridge
run_root ip link set "${WAN_MACVTAP}" up

TAP_INDEX="$(cat /sys/class/net/"${WAN_MACVTAP}"/ifindex)"
MACVTAP_DEV="/dev/tap${TAP_INDEX}"
# Let the invoking user open macvtap from QEMU without root
if [[ -e "${MACVTAP_DEV}" ]]; then
  run_root chown "${OWNER}:" "${MACVTAP_DEV}" 2>/dev/null \
    || run_root chmod 666 "${MACVTAP_DEV}" 2>/dev/null || true
fi

# Persist runtime net info for run.sh
{
  echo "PHY=${PHY}"
  echo "LAN_BR=${LAN_BR}"
  echo "LAN_TAP=${LAN_TAP}"
  echo "WAN_MACVTAP=${WAN_MACVTAP}"
  echo "LAN_HOST_IP=${LAN_HOST_IP}"
  echo "LAN_LEDE_IP=${LAN_LEDE_IP}"
  echo "TAP_INDEX=${TAP_INDEX}"
  echo "WAN_MAC=$(cat /sys/class/net/"${WAN_MACVTAP}"/address)"
} >"${STATE_DIR}/net.env"

info "网络就绪"
info "  宿主机访问 LuCI: http://${LAN_LEDE_IP}  (本机 ${LAN_HOST_IP})"
info "  WAN macvtap: ${WAN_MACVTAP} on ${PHY}"
cat "${STATE_DIR}/net.env"
