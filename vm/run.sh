#!/usr/bin/env bash
# Boot LEDE x86 in QEMU with dual NICs (LAN bridge + WAN macvtap).
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_cmd qemu-system-x86_64

if [[ ! -f "${IMG_QCOW2}" ]]; then
  echo "缺少磁盘镜像: ${IMG_QCOW2}" >&2
  echo "请先: ${VM_DIR}/deploy.sh  或  fetch.sh && prepare.sh" >&2
  exit 1
fi

if [[ ! -f "${STATE_DIR}/net.env" ]]; then
  info "网络未就绪，执行 net-up.sh..."
  "${VM_DIR}/net-up.sh"
fi
# shellcheck disable=SC1091
source "${STATE_DIR}/net.env"

if ! ip link show "${LAN_TAP}" &>/dev/null || ! ip link show "${WAN_MACVTAP}" &>/dev/null; then
  info "虚拟网卡缺失，重新 net-up..."
  "${VM_DIR}/net-up.sh"
  # shellcheck disable=SC1091
  source "${STATE_DIR}/net.env"
fi

TAP_INDEX="${TAP_INDEX:-$(cat /sys/class/net/"${WAN_MACVTAP}"/ifindex)}"
WAN_MAC="${WAN_MAC:-$(cat /sys/class/net/"${WAN_MACVTAP}"/address)}"
MACVTAP_DEV="/dev/tap${TAP_INDEX}"

if [[ ! -e "${MACVTAP_DEV}" ]]; then
  echo "找不到 macvtap 设备 ${MACVTAP_DEV}" >&2
  exit 1
fi

# Allow current user to open macvtap (avoids sudo for QEMU itself)
if [[ ! -r "${MACVTAP_DEV}" || ! -w "${MACVTAP_DEV}" ]]; then
  OWNER="${SUDO_USER:-${USER}}"
  run_root chown "${OWNER}:" "${MACVTAP_DEV}" 2>/dev/null \
    || run_root chmod 666 "${MACVTAP_DEV}" 2>/dev/null || true
fi

already=
for pid in $(ps -C qemu-system-x86_64 -o pid= 2>/dev/null || true); do
  pid="$(echo "${pid}" | tr -d ' ')"
  [[ -n "${pid}" ]] || continue
  if tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null | grep -q -- '-name lede-x86'; then
    already="${pid}"
    break
  fi
done
if [[ -n "${already}" ]]; then
  echo "QEMU 已在运行 (pid ${already})，先 stop.sh" >&2
  exit 1
fi

RUN_BG="${RUN_BG:-0}"
QEMU_EXTRA=()

if [[ -f "${OVMF_CODE}" && -f "${OVMF_VARS}" ]]; then
  QEMU_EXTRA+=(
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
    -drive "if=pflash,format=raw,file=${OVMF_VARS}"
  )
else
  warn "无 OVMF，使用 legacy BIOS 启动"
fi

if [[ ! -e /dev/kvm ]]; then
  warn "/dev/kvm 不可用，将使用 TCG（较慢）"
  ACCEL="tcg"
else
  ACCEL="kvm"
fi

info "启动 LEDE VM"
info "  disk: ${IMG_QCOW2}"
info "  LAN:  ${LAN_TAP} → ${LAN_BR}  (LuCI http://${LAN_LEDE_IP})"
info "  WAN:  ${WAN_MACVTAP} (${MACVTAP_DEV}) mac=${WAN_MAC}"
if [[ -f "${RELEASE_META}" ]]; then
  info "  release: $(grep ^tag= "${RELEASE_META}" | cut -d= -f2-)"
fi

qemu_args=(
  -name lede-x86
  -machine "q35,accel=${ACCEL}"
  -cpu host
  -m "${MEM_MB}"
  -smp "${SMP}"
  -drive "file=${IMG_QCOW2},if=virtio,format=qcow2,cache=writeback,discard=unmap"
  "${QEMU_EXTRA[@]}"
  -device "virtio-net-pci,netdev=lan,mac=${LAN_MAC}"
  -netdev "tap,id=lan,ifname=${LAN_TAP},script=no,downscript=no"
  -device "virtio-net-pci,netdev=wan,mac=${WAN_MAC}"
  -netdev "tap,id=wan,fd=3"
  -nographic
  -serial mon:stdio
)

if [[ "${RUN_BG}" == "1" ]]; then
  # state files may have been created as root on a prior run
  if [[ -e "${QEMU_LOG}" && ! -w "${QEMU_LOG}" ]]; then
    run_root chown "${SUDO_USER:-${USER}}:" "${QEMU_LOG}" 2>/dev/null || run_root rm -f "${QEMU_LOG}" || true
  fi
  if [[ -e "${QEMU_PIDFILE}" && ! -w "${QEMU_PIDFILE}" ]]; then
    run_root chown "${SUDO_USER:-${USER}}:" "${QEMU_PIDFILE}" 2>/dev/null || run_root rm -f "${QEMU_PIDFILE}" || true
  fi
  : >"${QEMU_LOG}"
  # Open macvtap on fd 3 in this shell, then background qemu
  exec 3<>"${MACVTAP_DEV}"
  qemu-system-x86_64 "${qemu_args[@]}" >"${QEMU_LOG}" 2>&1 &
  echo $! >"${QEMU_PIDFILE}"
  exec 3>&-

  ok=0
  for _ in $(seq 1 25); do
    if kill -0 "$(tr -d ' \n' <"${QEMU_PIDFILE}")" 2>/dev/null; then
      ok=1
      break
    fi
    sleep 0.2
  done
  if [[ "${ok}" -eq 1 ]]; then
    info "后台运行 pid=$(tr -d ' \n' <"${QEMU_PIDFILE}")，日志 ${QEMU_LOG}"
    info "停止: ${VM_DIR}/stop.sh"
  else
    echo "启动失败，见 ${QEMU_LOG}" >&2
    tail -n 80 "${QEMU_LOG}" 2>/dev/null || true
    exit 1
  fi
else
  exec 3<>"${MACVTAP_DEV}"
  exec qemu-system-x86_64 "${qemu_args[@]}"
fi
