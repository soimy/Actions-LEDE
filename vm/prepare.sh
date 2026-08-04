#!/usr/bin/env bash
# Convert downloaded firmware to a writable qcow2 disk for QEMU.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_cmd qemu-img gunzip

SRC_GZ="${FIRMWARE_DIR}/${ASSET_PATTERN}"
SRC_RAW="${FIRMWARE_DIR}/${ASSET_PATTERN%.gz}"

if [[ ! -f "${SRC_GZ}" && ! -f "${SRC_RAW}" ]]; then
  echo "未找到固件，请先运行: ${VM_DIR}/fetch.sh" >&2
  exit 1
fi

if [[ -f "${SRC_GZ}" ]]; then
  info "解压 ${SRC_GZ}..."
  # Keep .gz; write raw beside it.
  # OpenWrt combined images often have trailing padding → gunzip exits 2
  # ("decompression OK, trailing garbage ignored"); treat 0/1/2 as success.
  set +e
  gunzip -kf "${SRC_GZ}"
  gz_rc=$?
  set -e
  if [[ "${gz_rc}" -gt 2 ]]; then
    echo "gunzip 失败 (exit ${gz_rc})" >&2
    exit 1
  fi
  if [[ "${gz_rc}" -eq 2 ]]; then
    warn "gunzip: trailing garbage ignored（OpenWrt 镜像常见，可忽略）"
  fi
fi

if [[ ! -f "${SRC_RAW}" ]]; then
  echo "解压后未找到: ${SRC_RAW}" >&2
  exit 1
fi

info "转换为 qcow2 → ${IMG_QCOW2}"
qemu-img convert -f raw -O qcow2 "${SRC_RAW}" "${IMG_QCOW2}"

info "扩容磁盘到 ${DISK_SIZE}（便于安装插件；系统内分区需自行扩展）"
qemu-img resize "${IMG_QCOW2}" "${DISK_SIZE}"

# Fresh OVMF NVRAM for EFI boot
if [[ -f "${OVMF_VARS_TEMPLATE}" ]]; then
  cp -f "${OVMF_VARS_TEMPLATE}" "${OVMF_VARS}"
  info "已准备 OVMF_VARS: ${OVMF_VARS}"
else
  warn "未找到 ${OVMF_VARS_TEMPLATE}，run.sh 将尝试无 EFI 启动"
fi

# Drop large raw to save space (keep .gz)
rm -f "${SRC_RAW}"

info "镜像就绪:"
qemu-img info "${IMG_QCOW2}"
