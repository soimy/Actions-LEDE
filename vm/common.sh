#!/usr/bin/env bash
# Shared paths and defaults for LEDE x86 VM verification.
# shellcheck disable=SC2034

set -euo pipefail

VM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${VM_DIR}/.." && pwd)"

# --- paths ---
FIRMWARE_DIR="${VM_DIR}/firmware"
IMAGES_DIR="${VM_DIR}/images"
STATE_DIR="${VM_DIR}/state"
IMG_QCOW2="${IMAGES_DIR}/lede-x86.qcow2"
OVMF_VARS="${STATE_DIR}/OVMF_VARS.fd"
QEMU_PIDFILE="${STATE_DIR}/qemu.pid"
QEMU_LOG="${STATE_DIR}/qemu.log"
RELEASE_META="${STATE_DIR}/release.txt"

# --- network ---
# LAN: host <-> LEDE br-lan (LuCI).
# scripts/init-settings.sh rewrites default 192.168.1.1 → 192.168.0.1
# (release notes/README still say 192.168.8.1; override with LAN_LEDE_IP if needed).
LAN_BR="${LAN_BR:-br-lede}"
LAN_TAP="${LAN_TAP:-tap-lede-lan}"
LAN_HOST_IP="${LAN_HOST_IP:-192.168.0.2/24}"
LAN_LEDE_IP="${LAN_LEDE_IP:-192.168.0.1}"
LAN_MAC="${LAN_MAC:-52:54:00:1e:de:01}"

# WAN: LEDE uplink via macvtap on physical NIC (DHCP from home LAN)
# Auto-detect default route interface if PHY not set
if [[ -z "${PHY:-}" ]]; then
  PHY="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
  PHY="${PHY:-enp5s0}"
fi
WAN_MACVTAP="${WAN_MACVTAP:-macvtap-lede}"

# --- QEMU ---
MEM_MB="${MEM_MB:-1024}"
SMP="${SMP:-2}"
DISK_SIZE="${DISK_SIZE:-2G}"
OVMF_CODE="${OVMF_CODE:-/usr/share/edk2/ovmf/OVMF_CODE.fd}"
OVMF_VARS_TEMPLATE="${OVMF_VARS_TEMPLATE:-/usr/share/edk2/ovmf/OVMF_VARS.fd}"

# --- release ---
# Match tags like 2026.08.04_X86-64 from build-x86.yml
RELEASE_TAG_FILTER="${RELEASE_TAG_FILTER:-X86-64}"
# Preferred asset for QEMU (raw disk, EFI)
ASSET_PATTERN="${ASSET_PATTERN:-openwrt-x86-64-generic-squashfs-combined-efi.img.gz}"

# GitHub repo (override with GH_REPO=owner/name)
if [[ -z "${GH_REPO:-}" ]]; then
  if command -v gh >/dev/null 2>&1; then
    GH_REPO="$(cd "${REPO_ROOT}" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  fi
  GH_REPO="${GH_REPO:-soimy/Actions-LEDE}"
fi

mkdir -p "${FIRMWARE_DIR}" "${IMAGES_DIR}" "${STATE_DIR}"

need_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      echo "缺少命令: $c" >&2
      exit 1
    }
  done
}

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "需要 root 权限执行: $*" >&2
    exit 1
  fi
}

info() { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
