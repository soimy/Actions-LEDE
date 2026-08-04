#!/bin/bash
# 在 feeds update 之前向 feeds.conf.default 注入第三方源。
# 须在 openwrt 根目录执行。
#
# 参考：
#   - https://github.com/kenzok8/small-package  （插件合集，含 passwall/ssr/openclash 等）
#   - https://github.com/linkease/istore        （官方 iStore 应用商店）
set -euo pipefail

FEEDS_FILE="feeds.conf.default"
if [[ -f feeds.conf ]]; then
  FEEDS_FILE="feeds.conf"
fi

if [[ ! -f "${FEEDS_FILE}" ]]; then
  echo "找不到 ${FEEDS_FILE}，请在 openwrt 根目录执行" >&2
  exit 1
fi

append_feed() {
  local name="$1"
  local url="$2"
  if grep -qE "^src-git[[:space:]]+${name}[[:space:]]" "${FEEDS_FILE}"; then
    echo "==> feed '${name}' 已存在，跳过"
    return 0
  fi
  echo "src-git ${name} ${url}" >> "${FEEDS_FILE}"
  echo "==> 已添加 feed: ${name} -> ${url}"
}

echo "==> feeds-extra.sh: 注入第三方 feeds (${FEEDS_FILE})"

# kenzok8 插件合集（每日同步上游：PassWall / SSR+ / OpenClash / 依赖等）
append_feed smpackage "https://github.com/kenzok8/small-package"

# 官方 iStore（商店本体；与 smpackage 内可能自带的 store 去重见 packages.sh）
append_feed istore "https://github.com/linkease/istore;main"

echo "==> feeds-extra.sh: 当前 feeds 列表"
grep -E '^src-git' "${FEEDS_FILE}" || true
