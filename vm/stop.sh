#!/usr/bin/env bash
# Stop QEMU and optionally tear down virtual NICs.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

NET_DOWN=0
REMOVE_BRIDGE=0
for a in "$@"; do
  case "$a" in
    --net) NET_DOWN=1 ;;
    --all) NET_DOWN=1; REMOVE_BRIDGE=1 ;;
  esac
done

kill_pid() {
  local pid="$1"
  [[ -n "${pid}" ]] || return 0
  # Only signal real qemu-system processes (never match this shell via pkill -f)
  local comm exe
  comm="$(ps -p "${pid}" -o comm= 2>/dev/null | tr -d ' ' || true)"
  exe="$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"
  if [[ "${exe}" != *qemu-system-x86_64 && "${comm}" != qemu-system-x8* && "${comm}" != qemu-kvm* ]]; then
    warn "pid ${pid} 不是 qemu (${comm:-gone} ${exe:-})，跳过"
    return 0
  fi
  info "停止 QEMU pid=${pid}"
  if ! kill "${pid}" 2>/dev/null; then
    run_root kill "${pid}" 2>/dev/null || true
  fi
  for _ in $(seq 1 20); do
    kill -0 "${pid}" 2>/dev/null || break
    sleep 0.5
  done
  if kill -0 "${pid}" 2>/dev/null; then
    warn "强制 kill -9 ${pid}"
    kill -9 "${pid}" 2>/dev/null || run_root kill -9 "${pid}" 2>/dev/null || true
  fi
}

stopped=0
if [[ -f "${QEMU_PIDFILE}" ]]; then
  kill_pid "$(tr -d ' \n' <"${QEMU_PIDFILE}" || true)"
  rm -f "${QEMU_PIDFILE}"
  stopped=1
fi

# Fallback: ps -C (comm is truncated to 15 chars on Linux; -C still matches)
mapfile -t _pids < <(ps -C qemu-system-x86_64 -o pid= 2>/dev/null || true)
for pid in ${_pids[@]:-}; do
  pid="$(echo "${pid}" | tr -d ' ')"
  [[ -n "${pid}" ]] || continue
  if tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null | grep -q -- '-name lede-x86'; then
    kill_pid "${pid}"
    stopped=1
  fi
done

if [[ "${stopped}" -eq 0 ]]; then
  info "未发现运行中的 LEDE QEMU"
fi

if [[ "${NET_DOWN}" -eq 1 ]]; then
  if [[ "${REMOVE_BRIDGE}" -eq 1 ]]; then
    "${VM_DIR}/net-down.sh" --bridge
  else
    "${VM_DIR}/net-down.sh"
  fi
fi

info "已停止"
