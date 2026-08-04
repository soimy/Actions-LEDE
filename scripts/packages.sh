#!/bin/bash
# feeds update 之后、feeds install 之前（或之后再次）做冲突清理。
# 须在 openwrt 根目录执行。
#
# 策略：
#   1) smpackage (kenzok8/small-package)：PassWall / PassWall2 / SSR+ / OpenClash 及代理依赖
#   2) istore  (linkease/istore)：官方 luci-app-store / taskd / luci-lib-*
#   3) 删除 smpackage 里会弄坏 lede 的系统包；代理栈优先 smpackage；商店优先官方 istore
set -euo pipefail

echo "==> packages.sh: 清理第三方 feed 冲突"

if [[ ! -d feeds ]]; then
  echo "feeds/ 不存在，请先 ./scripts/feeds update" >&2
  exit 1
fi

# --- kenzok8 官方提示：删掉 smpackage 中与主线冲突的系统组件 ---
# https://github.com/kenzok8/small-package
if [[ -d feeds/smpackage ]]; then
  echo "==> 清理 feeds/smpackage 系统级冲突包"
  rm -rf feeds/smpackage/base-files \
         feeds/smpackage/dnsmasq \
         feeds/smpackage/firewall \
         feeds/smpackage/firewall4 \
         feeds/smpackage/fullconenat \
         feeds/smpackage/fullconenat-nft \
         feeds/smpackage/libnftnl \
         feeds/smpackage/nftables \
         feeds/smpackage/ppp \
         feeds/smpackage/opkg \
         feeds/smpackage/ucl \
         feeds/smpackage/upx \
         feeds/smpackage/miniupnpd-iptables \
         feeds/smpackage/wireless-regdb
  # vsftpd* 通配
  rm -rf feeds/smpackage/vsftpd feeds/smpackage/vsftpd-alt \
         feeds/smpackage/vsftpd* 2>/dev/null || true

  # 商店走官方 istore，去掉 smpackage 内同步的副本，避免 “package already defined”
  echo "==> 商店使用 linkease/istore，移除 smpackage 中的 store 栈"
  rm -rf feeds/smpackage/luci-app-store \
         feeds/smpackage/taskd \
         feeds/smpackage/luci-lib-taskd \
         feeds/smpackage/luci-lib-xterm
else
  echo "!! feeds/smpackage 不存在（是否未跑 feeds-extra.sh / feeds update？）" >&2
fi

# --- 代理栈优先 smpackage：去掉 luci/packages 里的旧版同名包 ---
echo "==> 代理栈优先 smpackage，移除 luci/packages 冲突"
rm -rf \
  feeds/luci/applications/luci-app-passwall \
  feeds/luci/applications/luci-app-passwall2 \
  feeds/luci/applications/luci-app-ssr-plus \
  feeds/luci/applications/luci-app-openclash \
  package/feeds/luci/luci-app-passwall \
  package/feeds/luci/luci-app-passwall2 \
  package/feeds/luci/luci-app-ssr-plus \
  package/feeds/luci/luci-app-openclash

# 依赖组件：让 smpackage 里的版本生效
for pkg in \
  chinadns-ng sing-box xray-core xray-plugin v2ray-core v2ray-geodata v2ray-plugin \
  naiveproxy microsocks dns2socks ipt2socks simple-obfs tcping \
  shadowsocks-rust shadowsocksr-libev hysteria tuic-client geoview
do
  rm -rf "feeds/packages/net/${pkg}" \
         "package/feeds/packages/${pkg}" 2>/dev/null || true
done

# --- 校验关键包路径 ---
check_pkg() {
  local label="$1"
  shift
  local p
  for p in "$@"; do
    if [[ -f "${p}" ]]; then
      echo "    OK ${label}: ${p}"
      return 0
    fi
  done
  echo "    FAIL ${label}: 未找到 Makefile ($*)" >&2
  return 1
}

echo "==> 校验关键包"
ok=0
check_pkg "passwall" \
  feeds/smpackage/luci-app-passwall/Makefile || ok=1
check_pkg "passwall2" \
  feeds/smpackage/luci-app-passwall2/Makefile || ok=1
check_pkg "openclash" \
  feeds/smpackage/luci-app-openclash/Makefile || ok=1
check_pkg "ssr-plus" \
  feeds/smpackage/luci-app-ssr-plus/Makefile || ok=1
check_pkg "istore" \
  feeds/istore/luci/luci-app-store/Makefile \
  feeds/istore/luci-app-store/Makefile || ok=1
check_pkg "taskd" \
  feeds/istore/luci/taskd/Makefile \
  feeds/istore/taskd/Makefile || ok=1

if [[ "${ok}" -ne 0 ]]; then
  echo "关键包缺失，中止（避免再编出无 PassWall/iStore 的固件）" >&2
  exit 1
fi

echo "==> packages.sh: done"
echo "    proxy : feeds/smpackage (kenzok8/small-package)"
echo "    store : feeds/istore     (linkease/istore)"
