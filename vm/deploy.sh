#!/usr/bin/env bash
# Full deploy: fetch latest X86-64 release → prepare qcow2 → net-up.
# Usage:
#   ./deploy.sh              # download + image + network
#   ./deploy.sh --run        # then start VM in foreground
#   ./deploy.sh --run-bg     # then start VM in background
#   ./deploy.sh --skip-fetch # reuse existing firmware under firmware/
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

DO_FETCH=1
DO_RUN=0
RUN_BG=0

for a in "$@"; do
  case "$a" in
    --skip-fetch) DO_FETCH=0 ;;
    --run) DO_RUN=1; RUN_BG=0 ;;
    --run-bg) DO_RUN=1; RUN_BG=1 ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
  esac
done

need_cmd gh qemu-img qemu-system-x86_64 nmcli ip

info "=== LEDE x86 VM 部署 (${GH_REPO}) ==="

if [[ "${DO_FETCH}" -eq 1 ]]; then
  "${VM_DIR}/fetch.sh"
else
  info "跳过下载 (--skip-fetch)"
  if [[ ! -f "${FIRMWARE_DIR}/${ASSET_PATTERN}" ]]; then
    echo "本地无 ${ASSET_PATTERN}，请去掉 --skip-fetch" >&2
    exit 1
  fi
fi

"${VM_DIR}/prepare.sh"
"${VM_DIR}/net-up.sh"

info "=== 部署完成 ==="
if [[ -f "${RELEASE_META}" ]]; then
  cat "${RELEASE_META}"
fi
echo
info "启动虚拟机:  ${VM_DIR}/run.sh"
info "后台启动:    RUN_BG=1 ${VM_DIR}/run.sh"
info "访问 LuCI:   http://${LAN_LEDE_IP}  (宿主机 ${LAN_HOST_IP})"
info "停止:        ${VM_DIR}/stop.sh [--net|--all]"

if [[ "${DO_RUN}" -eq 1 ]]; then
  export RUN_BG
  "${VM_DIR}/run.sh"
fi
