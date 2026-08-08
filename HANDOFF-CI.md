# Actions-LEDE CI Handoff

本文档记录当前 CI 的真实流程、已经验证过的修复和下一次排错入口。当前仓库为 `soimy/Actions-LEDE`，HEAD 为 `ff603bd`。

## 当前结论

- CI 源码：`https://github.com/coolsnowwolf/lede` 的 `master`。
- 所有构建工作流使用 `ubuntu-24.04`。
- x86 工作流使用 `configs/packages-x86.txt`；其他平台还会追加各自的 target 配置。
- PassWall 来自 `kenzok8/small-package`，iStore 来自 `linkease/istore`。
- 可选应用已经移到 iStore；固件只保留 iStore 核心、基础网络、存储、PassWall、ZeroTier、Lucky 和 UPnP 等启动后立即需要的功能。
- 最近一次完整成功构建对应 `d3a13c6`，之后又提交了 Lucky 服务修复和 iStore 应用精简；因此当前 HEAD 仍应通过下一次完整 CI 做回归验证。

## 工作流与触发

| 工作流 | 配置 | 触发 |
| --- | --- | --- |
| `build-x86.yml` | `packages-x86.txt` | `workflow_dispatch`、`repository_dispatch`、cron `0 20 * * 4` |
| `build-rockchip.yml` | `rockchip-L.txt` + `packages.txt` | `workflow_dispatch` |
| `build-r1_plus_LTS.yml` | `r1pluslts-with-docker.txt` | `workflow_dispatch` |
| `build-mtkfilogic.yml` | `filogic.txt` + `packages-L.txt` | `workflow_dispatch` |
| `build-allwinner.yml` | `allwinner.txt` + `packages-L.txt` | `workflow_dispatch` |

x86 的 cron 是每周四 20:00 UTC，即北京时间周五 04:00；workflow 文件中的旧注释和 Release 文案仍有 `192.168.8.1`，不能作为当前地址依据。

## 构建顺序

工作目录假定为 LEDE 源码根目录 `openwrt/`：

```text
checkout 本仓库
  ↓
clone coolsnowwolf/lede@master
  ↓
feeds-extra.sh       # 必须在 feeds update 前注入 feed
  ↓
./scripts/feeds update -a
  ↓
packages.sh          # 删除冲突、修补包、重建 index
  ↓
./scripts/feeds install -a
  ↓
追加 platform config + package config
  ↓
init-settings.sh
  ↓
make defconfig
  ↓
tools → toolchain → target/linux → package → image
```

关键文件：

- [`scripts/feeds-extra.sh`](scripts/feeds-extra.sh)：前置 `smpackage`，追加 `istore`。
- [`scripts/packages.sh`](scripts/packages.sh)：删除 smpackage 的系统级重复包、删除代理栈重复包、重建 `feeds` 索引，并修补 Lucky、netdata、easy-rsa、vlmcsd。
- [`scripts/init-settings.sh`](scripts/init-settings.sh)：当前通用流程实际把 `192.168.1.1` 替换为 `192.168.0.1`。
- `.github/workflows/*.yml`：CI 的最终执行顺序和缓存策略，以工作流为准。

删除 feed 目录后必须执行 `./scripts/feeds update -i`。否则旧的 `packages.index` 仍会指向已删除目录，表现为代理依赖包 “does not exist”。

## 软件包取舍的 CI 约束

### 固件内置

- iStore 核心：`luci-app-store`、`taskd`、`luci-lib-taskd`、`luci-lib-xterm`。
- DNS：系统 `dnsmasq` + `luci-app-smartdns`。
- 代理：`luci-app-passwall`，当前启用 NaiveProxy、Sing-box、Xray、Hysteria。
- VPN：`luci-app-zerotier`。
- 存储：exFAT、Samba4、NFS；不启用 RAID。
- 专用功能：Lucky、`luci-app-upnp`。

### iStore 安装

Alist、阿里云盘 WebDAV、`luci-app-nlbwmon`、Tailscale、全能推送、udpxy、KMS/vlmcsd、diskman、hd-idle 不进入默认镜像，刷机后从 iStore 按需安装。`luci-app-aliyundrive-fuse` 已明确移除。

FRP 客户端/服务端、OpenClash、SSR-Plus、5G modem 软件栈和 x86 可选 Wi-Fi 驱动不属于当前固件方案。`filogic.txt` 中的 `fzs_5gcpe-p3` 是硬件 target profile，不是 5G 软件包。

## 已验证的 CI 问题与修复

### 1. Ubuntu 24.04 + binutils 2.42

失败运行：[31183120275](https://github.com/soimy/Actions-LEDE/actions/runs/31183120275)。工具链链接阶段出现以下类型错误：

```text
undefined reference to '__snprintf_chk'
undefined reference to '__sprintf_chk'
undefined reference to '__fprintf_chk'
undefined reference to '__isoc23_strtol'
```

修复在 `d3a13c6`：

- `configs/packages-x86.txt` 使用当前 LEDE master 的 `CONFIG_BINUTILS_USE_VERSION_2_43=y`，并在编译前校验解析结果为 `2.43.1`；
- x86 runner 保持 `ubuntu-24.04`；
- x86 的 `HOST_CFLAGS` 使用 `-O2 -U_FORTIFY_SOURCE`；
- cache mix key 改为 `x86-smpackage-istore-binutils243-kconfig43`，避免复用旧 Kconfig 符号生成的工具链缓存。

当前 LEDE master 已从旧的 `CONFIG_BINUTILS_VERSION_2_43_1` 选择符切换为 `CONFIG_BINUTILS_USE_VERSION_2_43`。如果不更新选择符，`make defconfig` 会静默回退到默认 binutils 2.42；工作流现在会在真正编译前直接报出解析版本，避免浪费几十分钟后才失败。

成功运行：[31185744904](https://github.com/soimy/Actions-LEDE/actions/runs/31185744904)，工具链、内核、插件和固件阶段均通过。

不要把旧 handoff 中的 “切回 Ubuntu 22.04” 当作当前方案；那是旧记录，现行修复是 Ubuntu 24.04 + binutils 2.43.1。

### 2. feed 冲突

`packages.sh` 让 `smpackage` 优先于 `packages/luci`，让 iStore 使用官方 `istore` feed：

- 删除 smpackage 的 `base-files`、`dnsmasq`、firewall 等系统重复包；
- 删除 smpackage 内重复的 iStore 包；
- 删除旧版 PassWall、PassWall2、SSR-Plus、OpenClash 及其重复依赖；
- 删除会冲突的 `luci-app-frps`、`luci-app-frpc`、旧版 ZeroTier/OpenVPN LuCI 包；
- 删除目录后执行 `./scripts/feeds update -i`，再 `feeds install -a`。

如果出现 `package already defined`、`does not exist` 或安装到了错误 feed，先检查上述顺序和索引，不要直接改 `.config` 规避。

### 3. Lucky LuCI 页面可见但服务不可用

kenzok8 的 Lucky 包可能只有二进制，没有 `/etc/init.d/lucky` 和 `/etc/config/lucky`。`packages.sh` 会在 feed 更新后把 [`scripts/lucky/lucky.init`](scripts/lucky/lucky.init) 和 [`scripts/lucky/lucky.config`](scripts/lucky/lucky.config) 注入 Makefile。

在设备上检查：

```sh
ls -l /etc/init.d/lucky /etc/config/lucky
/etc/init.d/lucky enabled
/etc/init.d/lucky status
logread | grep -i lucky
```

缺少文件说明实际安装的包没有经过当前 `packages.sh` 修补；不要只在 LuCI 中重复点击启用。

### 4. 其他已知构建冲突

- `ksmbd` 与当前 6.12 内核接口不兼容，使用 Samba4。
- `vsftpd` 与 `vsftpd-alt` 有文件冲突，当前两者都不选。
- netdata 的版本检测可能误读 LEDE 上层 Git，`packages.sh` 强制使用打包版本。
- openvpn-easy-rsa 的静态路径补丁与当前源码版本不匹配时，由 `packages.sh` 覆盖为兼容补丁。
- vlmcsd 在启用 ccache 时可能把 `ccache gcc` 作为多文件编译器，脚本强制使用 `TARGET_CC_NOCACHE`。
- `make defconfig` 偶尔出现第三方 feed 的 recursive dependency 警告；先确认是否真正退出非零，不要把最后一行级联错误当作首个根因。

## 手动触发与 10 分钟监控

```bash
gh workflow run build-x86.yml --ref main
gh run list --workflow build-x86.yml --branch main --limit 5
gh run watch <run-id> --compact --interval 600 --exit-status
```

失败后先看第一处真实错误：

```bash
gh run view <run-id> --log-failed
```

由于工作流会先并行编译、失败后再以 `-j1 V=s` 重试，日志末尾通常是级联错误；排错应从最早一个失败步骤和第一个编译/链接错误开始。

## 本地复现

原生 macOS 不是受支持的 LEDE 构建环境。Mac M4 应使用 Linux VM、UTM 或 Docker；`vm/` 目录主要用于启动和验证 x86 Release 固件，详细步骤见 [`vm/README.md`](vm/README.md)。在 Linux 中可按以下最小流程复现 x86 配置：

```bash
git clone https://github.com/coolsnowwolf/lede -b master openwrt
cd openwrt
chmod +x ../Actions-LEDE/scripts/feeds-extra.sh ../Actions-LEDE/scripts/packages.sh
../Actions-LEDE/scripts/feeds-extra.sh
./scripts/feeds update -a
../Actions-LEDE/scripts/packages.sh
./scripts/feeds install -a
cat ../Actions-LEDE/configs/packages-x86.txt >> .config
make defconfig
make tools/compile -j"$(nproc)"
make toolchain/compile -j"$(nproc)"
make target/linux/compile -j"$(nproc)"
make package/compile -j"$(nproc)"
make package/index
make package/install -j"$(nproc)"
make target/install -j"$(nproc)"
```

这段命令用于定位 feed、配置和工具链问题；完整 Release 流程还包括工作流中的空间清理、缓存、镜像生成和上传步骤。

## 下一次 CI 验证清单

1. 触发 `build-x86.yml`，确认当前 `ff603bd` 之后的配置仍能完整编译。
2. 确认 PassWall 的 Hysteria 后端和 iStore 核心都进入包索引。
3. 刷入 UTM/测试设备后检查 Lucky init/config、SmartDNS、Samba4、NFS、ZeroTier、UPnP。
4. 从 iStore 安装 Alist、阿里云盘 WebDAV、nlbwmon 和 Tailscale，确认“内置基础功能 + 按需应用”的分工。
5. 若通过，再更新 Release 文案中的旧 IP，避免与 `init-settings.sh` 和 `vm/README.md` 冲突。
