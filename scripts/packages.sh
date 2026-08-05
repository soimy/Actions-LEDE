#!/bin/bash
# feeds update 之后、feeds install 之前（或之后再次）做冲突清理。
# 须在 openwrt 根目录执行。
#
# 策略：
#   1) smpackage (kenzok8/small-package)：PassWall / PassWall2 / SSR+ / OpenClash 及代理依赖
#   2) istore  (linkease/istore)：官方 luci-app-store / taskd / luci-lib-*
#   3) 删除 smpackage 里会弄坏 lede 的系统包；代理栈优先 smpackage；商店优先官方 istore
#   4) 删除 packages/luci 冲突后必须 feeds update -i 重建索引，否则 install 仍指向已删路径
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

  # lean 旧版 luci-app 自带 /etc/init.d 或 /etc/config，与 packages 二进制包冲突：
  #   luci-app-frps        vs frps          → /etc/init.d/frps
  #   luci-app-zerotier    vs zerotier      → /etc/init.d/zerotier
  #   luci-app-openvpn-server vs openvpn    → /etc/config/openvpn
  # coolsnowwolf/luci (openwrt-25.12) 的同名包为 JS/无冲突版，删 smpackage 副本以让 luci feed 生效。
  echo "==> 移除 smpackage 中与 packages/luci 文件冲突的 lean luci-app"
  rm -rf feeds/smpackage/other/lean/luci-app-frps \
         feeds/smpackage/other/lean/luci-app-frpc \
         feeds/smpackage/other/lean/luci-app-zerotier \
         feeds/smpackage/luci-app-openvpn-server \
         feeds/smpackage/luci-app-openvpn-client \
         package/feeds/smpackage/luci-app-frps \
         package/feeds/smpackage/luci-app-frpc \
         package/feeds/smpackage/luci-app-zerotier \
         package/feeds/smpackage/luci-app-openvpn-server \
         package/feeds/smpackage/luci-app-openvpn-client

  # netdata 2.x (cmake): NetdataVersion.cmake 若找到 host git，会在 build_dir
  # 向上找到 openwrt 仓库并 git describe，输出不匹配 vX.Y.Z →
  # "Wrong version regex match count 0"。强制走 packaging/version。
  if [[ -d feeds/smpackage/netdata ]]; then
    echo "==> 修复 feeds/smpackage/netdata 版本检测 (禁用 git describe)"
    mkdir -p feeds/smpackage/netdata/patches
    cat > feeds/smpackage/netdata/patches/999-openwrt-force-packaging-version.patch << 'PATCH_EOF'
--- a/packaging/cmake/Modules/NetdataVersion.cmake
+++ b/packaging/cmake/Modules/NetdataVersion.cmake
@@ -5,7 +5,10 @@
 # packaging/version. This version field are used for cmake's project,
 # cpack's packaging, and the agent's functionality.
 function(netdata_version)
-        find_package(Git)
+        # OpenWrt: host Git discovers parent openwrt/.git; describe output is
+        # not a netdata version and fails CMAKE_MATCH_COUNT (need 3/4/5).
+        # Force fallback to packaging/version from the release tarball.
+        set(GIT_EXECUTABLE "")
 
         if(GIT_EXECUTABLE)
                 execute_process(COMMAND ${GIT_EXECUTABLE} describe
PATCH_EOF
  fi

  # openvpn-easy-rsa-whisky: 上游 101-static_EASYRSA.patch 行号/空白与 easy-rsa
  # 3.0.9 (150e96e) 不匹配 → Hunk #1 FAILED。luci-app-openvpn-server 依赖此包，
  # 且 openvpncert.sh 需要 EASYRSA_PKI=/tmp/easyrsa3/pki。
  # 补丁经 git apply 对 150e96e 校验通过（base64 避免 TAB 丢失）。
  if [[ -d feeds/smpackage/openvpn-easy-rsa-whisky ]]; then
    echo "==> 修复 feeds/smpackage/openvpn-easy-rsa-whisky 静态路径补丁"
    mkdir -p feeds/smpackage/openvpn-easy-rsa-whisky/patches
    base64 -d > feeds/smpackage/openvpn-easy-rsa-whisky/patches/101-static_EASYRSA.patch << 'B64'
LS0tIGEvZWFzeXJzYTMvZWFzeXJzYQorKysgYi9lYXN5cnNhMy9lYXN5cnNhCkBAIC0yNTYyLDEwICsyNTYyLDEwIEBACiAJIyBSZW1vdmVkIGZvciBiYXNpYyBzYW5pdHkgLSBUbyByZS1lbmFibGUgcHJvdmlkZSBhIFJFQVNPTgogCSNwcm9nX2ZpbGUyPSIkKHdoaWNoIC0tICIkcHJvZ19maWxlIiAyPi9kZXYvbnVsbCkiICYmIHByb2dfZmlsZT0iJHByb2dfZmlsZTIiCiAJI3Byb2dfZmlsZTI9IiQocmVhZGxpbmsgLWYgIiRwcm9nX2ZpbGUiIDI+L2Rldi9udWxsKSIgJiYgcHJvZ19maWxlPSIkcHJvZ19maWxlMiIKLQlwcm9nX2Rpcj0iJHtwcm9nX2ZpbGUlLyp9IgorCXByb2dfZGlyPSIvZXRjL2Vhc3ktcnNhIgogCiAJIyBQcm9ncmFtIGRpciB2YXJzIC0gVGhpcyBsb2NhdGlvbiBpcyBsZWFzdCB3YW50ZWQuCi0JcHJvZ192YXJzPSIke3Byb2dfZGlyfS92YXJzIgorCXByb2dfdmFycz0iL2V0Yy9lYXN5LXJzYS92YXJzIgogCiAJIyBzZXQgdXAgUEtJIHBhdGggdmFycyAtIFRvcCBwcmVmZXJlbmNlCiAJcGtpX3ZhcnM9IiR7RUFTWVJTQV9QS0k6LSRQV0QvcGtpfS92YXJzIgpAQCAtMjY4OSw3ICsyNjg5LDcgQEAKIAkjIFNldCBkZWZhdWx0cywgcHJlZmVycmluZyBleGlzdGluZyBlbnYtdmFycyBpZiBwcmVzZW50CiAJc2V0X3ZhciBFQVNZUlNBCQkJCQkiJFBXRCIKIAlzZXRfdmFyIEVBU1lSU0FfT1BFTlNTTAkJCW9wZW5zc2wKLQlzZXRfdmFyIEVBU1lSU0FfUEtJCQkJCSIkRUFTWVJTQS9wa2kiCisJc2V0X3ZhciBFQVNZUlNBX1BLSQkJCQkiL3RtcC9lYXN5cnNhMy9wa2kiCiAJc2V0X3ZhciBFQVNZUlNBX0ROCQkJCWNuX29ubHkKIAlzZXRfdmFyIEVBU1lSU0FfUkVRX0NPVU5UUlkJCSJVUyIKIAlzZXRfdmFyIEVBU1lSU0FfUkVRX1BST1ZJTkNFCSJDYWxpZm9ybmlhIgo=
B64
  fi

  # vlmcsd + CONFIG_CCACHE: 上游 GNUmakefile 在 CC="ccache gcc" 时失败
  #   fatal error: cannot specify '-o' with '-c' ... with multiple files
  # ImmortalWrt 同款：强制 TARGET_CC_NOCACHE，跳过 ccache 包装。
  VLMCSD_MK=""
  for cand in feeds/smpackage/other/lean/vlmcsd/Makefile feeds/smpackage/vlmcsd/Makefile; do
    if [[ -f "${cand}" ]]; then
      VLMCSD_MK="${cand}"
      break
    fi
  done
  if [[ -n "${VLMCSD_MK}" ]]; then
    if grep -q 'TARGET_CC_NOCACHE' "${VLMCSD_MK}"; then
      echo "==> ${VLMCSD_MK} 已含 TARGET_CC_NOCACHE，跳过"
    else
      echo "==> 修复 ${VLMCSD_MK} (CC=TARGET_CC_NOCACHE，兼容 ccache)"
      python3 - "${VLMCSD_MK}" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text()
if "TARGET_CC_NOCACHE" in text:
    sys.exit(0)
old = "MAKE_FLAGS += \\\n\t-C $(PKG_BUILD_DIR)\n"
new = "MAKE_FLAGS += \\\n\t-C $(PKG_BUILD_DIR) \\\n\tCC=\"$(TARGET_CC_NOCACHE)\"\n"
if old in text:
    text = text.replace(old, new, 1)
else:
    # 宽松：在 BuildPackage 前追加
    marker = "$(eval $(call BuildPackage,vlmcsd))"
    if marker not in text:
        raise SystemExit(f"cannot patch {p}: no MAKE_FLAGS or BuildPackage marker")
    text = text.replace(
        marker,
        'MAKE_FLAGS += CC="$(TARGET_CC_NOCACHE)"\n\n' + marker,
        1,
    )
p.write_text(text)
print(f"patched {p}")
PY
    fi
  else
    echo "!! 未找到 smpackage vlmcsd Makefile（若未选 luci-app-vlmcsd 可忽略）"
  fi
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

# 依赖组件：删 packages feed 副本，让 smpackage 生效
# 注意：v2ray-geoip / v2ray-geosite 是 v2ray-geodata Makefile 里的子包
PROXY_PKGS=(
  chinadns-ng sing-box xray-core xray-plugin v2ray-core v2ray-geodata v2ray-plugin
  naiveproxy microsocks dns2socks ipt2socks simple-obfs tcping
  shadowsocks-rust shadowsocksr-libev hysteria tuic-client geoview
)
for pkg in "${PROXY_PKGS[@]}"; do
  rm -rf "feeds/packages/net/${pkg}" \
         "package/feeds/packages/${pkg}" 2>/dev/null || true
done

# --- 关键：删目录后必须重建 index ---
# 否则 feeds install 仍按旧 packages.index 从 packages feed 安装（路径已空），
# 结果 chinadns-ng / microsocks / tcping / geoview / v2ray-geoip|geosite 全部 “does not exist”
if [[ -x ./scripts/feeds ]]; then
  echo "==> 重建 feeds 索引 (./scripts/feeds update -i)"
  ./scripts/feeds update -i
else
  echo "!! ./scripts/feeds 不可用，跳过 reindex（install 可能仍指向已删包）" >&2
fi

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
# 代理依赖（package/install 缺它们会 Error 255）
check_pkg "chinadns-ng" feeds/smpackage/chinadns-ng/Makefile || ok=1
check_pkg "microsocks"  feeds/smpackage/microsocks/Makefile || ok=1
check_pkg "tcping"      feeds/smpackage/tcping/Makefile || ok=1
check_pkg "geoview"     feeds/smpackage/geoview/Makefile || ok=1
check_pkg "v2ray-geodata" feeds/smpackage/v2ray-geodata/Makefile || ok=1

if [[ "${ok}" -ne 0 ]]; then
  echo "关键包缺失，中止（避免再编出无 PassWall/iStore 的固件）" >&2
  exit 1
fi

echo "==> packages.sh: done"
echo "    proxy : feeds/smpackage (kenzok8/small-package)"
echo "    store : feeds/istore     (linkease/istore)"
echo "    next  : ./scripts/feeds install -a  # 依赖应来自 smpackage，而非 packages"
