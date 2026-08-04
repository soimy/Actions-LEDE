#!/usr/bin/env bash
# Download the latest X86-64 firmware from GitHub Releases via gh.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_cmd gh

TAG="${1:-}"

if [[ -z "$TAG" ]]; then
  info "查找最新含 ${RELEASE_TAG_FILTER} 的 release (${GH_REPO})..."
  TAG="$(
    gh release list --repo "${GH_REPO}" --limit 50 \
      --json tagName,createdAt \
      -q "[.[] | select(.tagName | contains(\"${RELEASE_TAG_FILTER}\"))] | sort_by(.createdAt) | reverse | .[0].tagName" \
      2>/dev/null || true
  )"
  if [[ -z "$TAG" || "$TAG" == "null" ]]; then
    TAG="$(
      gh release list --repo "${GH_REPO}" --limit 50 \
        | awk -v f="${RELEASE_TAG_FILTER}" 'index($0, f) {print $1; exit}'
    )"
  fi
fi

if [[ -z "$TAG" || "$TAG" == "null" ]]; then
  echo "未找到匹配 ${RELEASE_TAG_FILTER} 的 release" >&2
  exit 1
fi

info "Release: ${TAG}"
ASSET_LIST="$(gh release view "${TAG}" --repo "${GH_REPO}" --json assets -q '.assets[].name')"
if ! grep -qxF "${ASSET_PATTERN}" <<<"${ASSET_LIST}"; then
  echo "Release ${TAG} 中未找到资产: ${ASSET_PATTERN}" >&2
  echo "可用资产:" >&2
  echo "${ASSET_LIST}" >&2
  exit 1
fi

DEST="${FIRMWARE_DIR}/${ASSET_PATTERN}"
info "下载 ${ASSET_PATTERN} → ${DEST}"
gh release download "${TAG}" --repo "${GH_REPO}" \
  --pattern "${ASSET_PATTERN}" \
  --pattern "sha256sums" \
  --dir "${FIRMWARE_DIR}" \
  --clobber

# Optional checksum verify
if [[ -f "${FIRMWARE_DIR}/sha256sums" ]]; then
  info "校验 sha256..."
  (
    cd "${FIRMWARE_DIR}"
    if grep -q " ${ASSET_PATTERN}\$" sha256sums 2>/dev/null || grep -q "\*.*${ASSET_PATTERN}" sha256sums 2>/dev/null; then
      # OpenWrt sha256sums format: <hash> *filename or <hash>  filename
      grep -E "[ *]${ASSET_PATTERN}\$" sha256sums | sha256sum -c - || {
        warn "sha256 校验失败，继续使用已下载文件"
      }
    else
      warn "sha256sums 中无 ${ASSET_PATTERN}，跳过校验"
    fi
  )
fi

{
  echo "tag=${TAG}"
  echo "asset=${ASSET_PATTERN}"
  echo "repo=${GH_REPO}"
  echo "fetched_at=$(date -Iseconds)"
} >"${RELEASE_META}"

info "完成: ${DEST}"
echo "${TAG}"
