# Actions-LEDE

基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) 的多平台定制固件仓库，使用 GitHub Actions 编译并发布 LEDE 固件。

当前文档以 `ff603bd` 为准。x86/UTM 只是验证环境，本仓库同时面向 Rockchip、MediaTek Filogic、Allwinner 等硬件平台。

## 精简策略

本仓库的目标不是制作“所有软件都预装”的大而全固件，而是提供一个开机即可使用、体积适中、便于维护的基础系统：

- 只把网络接入、DNS、代理、基础管理、存储和救援所需的软件编译进固件。
- 大体积、低频使用、硬件相关或可以独立升级的软件，改为通过 iStore 按需安装。
- 不因为某个软件“可能会用到”就默认编译，减少启动服务、依赖冲突和升级负担。
- 每个平台保留必要的硬件配置；应用层的软件取舍尽量保持一致。

因此，刷机后的固件是“最常用功能 + iStore 扩展”的组合，而不是完整软件集合。首次启动后可以在 LuCI 的 iStore 页面安装下面列出的可选应用。

## 默认内置的软件

| 分组 | 内置内容 | 说明 |
| --- | --- | --- |
| 应用商店 | `luci-app-store`、`taskd`、`luci-lib-taskd`、`luci-lib-xterm` | iStore 核心内置，方便首次启动后继续扩展 |
| DNS | 系统 `dnsmasq`、`luci-app-smartdns` | dnsmasq 负责基础 DHCP/DNS，SmartDNS 提供增强解析 |
| 代理 | `luci-app-passwall` | 代理组只保留 PassWall；当前启用 NaiveProxy、Sing-box、Xray、Hysteria |
| VPN | `luci-app-zerotier` | 保留 ZeroTier 作为基础组网和救援通道 |
| 存储 | exFAT、Samba4、NFS | 包括 `kmod-fs-exfat`、`exfat-fsck`、`exfat-mkfs`、`luci-app-samba4`、`luci-app-nfs`；不启用 RAID |
| 专用功能 | Lucky、UPnP | 保留 `luci-app-lucky` 和 `luci-app-upnp`；Lucky 服务文件由构建脚本补齐 |
| 常用管理 | Argon、ttyd、文件传输、DDNS、访问控制、自动重启、WOL 等 | 具体内容随平台配置略有不同 |

PassWall 只保留这一套代理管理界面；OpenClash、SSR-Plus 不编译。PassWall 配置中未启用的其他后端也保持关闭，后续需要时再单独加入。

部分平台还会保留自身必要的功能，例如 R1 Plus/LTS 的 Docker、Rockchip 的 CPU 频率管理、Filogic 的同步拨号，不代表所有平台都会安装这些软件。

## 推荐通过 iStore 安装的软件

以下软件仍然保留使用需求，但不放进每个固件的默认镜像。这样可以减少镜像体积，也避免不需要的常驻服务。

| 功能 | 推荐的 iStore 软件 | 选择理由 |
| --- | --- | --- |
| 云盘 | Alist、阿里云盘 WebDAV | 体积和运行时依赖较大，按需安装；云盘需求没有删除 |
| 流量统计 | `luci-app-nlbwmon` | 统计功能只保留一个，选择轻量的 nlbwmon |
| VPN | Tailscale | 需要时与 ZeroTier 组合或替换使用，不占用默认固件空间 |
| 消息推送 | `luci-app-pushbot`（全能推送） | 使用场景因人而异，适合按需安装 |
| KMS | `luci-app-vlmcsd` | 低频使用，不作为基础服务启动 |
| 网络工具 | `luci-app-udpxy` | 特定组播/代理场景使用，不并入 PassWall 基础栈 |
| 磁盘管理 | `luci-app-diskman`、`luci-app-hd-idle` | 与具体磁盘和硬件场景相关 |

`luci-app-aliyundrive-fuse` 已明确移除，不再作为默认方案；阿里云盘 WebDAV 通过 iStore 保留。安装时进入 LuCI → iStore 搜索对应软件即可，具体包名以当前 iStore 索引为准。

## 明确不包含的功能

- **FRP**：客户端和服务端都不保留。
- **5G 软件栈**：不加入 5G modem、拨号和相关管理软件。
- **x86 可选 Wi-Fi 驱动**：虚拟机/x86 配置不加入无线驱动族；真实路由器 target 的平台基础无线支持由上游 target 自己决定。
- **RAID**：不编译 RAID 管理和相关扩展。
- **KSMBD**：当前内核兼容性不足，统一使用 Samba4。
- **vsftpd/vsftpd-alt**：存在文件冲突，当前两者都不选。
- **多套统计和代理管理界面**：只保留 nlbwmon 与 PassWall，其他方案按需处理。
- **阿里云盘 FUSE**：`luci-app-aliyundrive-fuse` 删除；保留阿里云盘 WebDAV 的 iStore 安装路径。

`configs/filogic.txt` 中的 `fzs_5gcpe-p3` 只是上游硬件 target profile 名称，不代表启用了 5G 软件包。若连这个硬件 profile 也要从固件目标列表删除，需要另外修改 target 配置。

## 支持的平台与配置

| 工作流 | 平台/配置 | 触发方式 |
| --- | --- | --- |
| [`build-x86.yml`](.github/workflows/build-x86.yml) | x86/64，`configs/packages-x86.txt` | 手动、`repository_dispatch`、定时 |
| [`build-rockchip.yml`](.github/workflows/build-rockchip.yml) | Rockchip ARMv8，`configs/rockchip-L.txt` + `configs/packages.txt` | 手动 |
| [`build-r1_plus_LTS.yml`](.github/workflows/build-r1_plus_LTS.yml) | Orange Pi R1 Plus/LTS + Docker，`configs/r1pluslts-with-docker.txt` | 手动 |
| [`build-mtkfilogic.yml`](.github/workflows/build-mtkfilogic.yml) | MediaTek Filogic，`configs/filogic.txt` + `configs/packages-L.txt` | 手动 |
| [`build-allwinner.yml`](.github/workflows/build-allwinner.yml) | Allwinner Cortex-A53，`configs/allwinner.txt` + `configs/packages-L.txt` | 手动 |

所有构建当前运行在 `ubuntu-24.04`，使用 `coolsnowwolf/lede` 的 `master` 分支。各平台的配置文件不同，修改软件包时不要只检查 x86 配置。

## 发布节奏

- **x86/64**：每周自动发布一次，cron 为 `0 20 * * 4`（UTC），即北京时间每周五 04:00；同时支持手动触发和 `repository_dispatch`。
- **Rockchip、R1 Plus/LTS、MediaTek Filogic、Allwinner**：没有固定定时任务，需要手动触发对应工作流。
- **发布条件**：构建成功后自动上传 GitHub Release，标签格式为日期加平台名称，例如 `2026.08.04_X86-64`。
- **清理策略**：成功发布后按整个仓库的 Release 列表保留最近 15 个；旧的工作流运行记录会定期清理，仅保留短期排错所需记录。

发布页面：[GitHub Releases](https://github.com/soimy/Actions-LEDE/releases)；构建状态：[GitHub Actions](https://github.com/soimy/Actions-LEDE/actions)。

## 构建流程

第三方 feed 必须在更新前注入，冲突清理必须在安装前完成：

1. 克隆 LEDE 源码。
2. [`scripts/feeds-extra.sh`](scripts/feeds-extra.sh) 加入 `smpackage` 和 `istore` feed。
3. 执行 `./scripts/feeds update -a`。
4. [`scripts/packages.sh`](scripts/packages.sh) 清理重复包、修复冲突、重建 feed 索引，并补齐 Lucky 服务文件。
5. 执行 `./scripts/feeds install -a`，追加平台配置和软件包配置。
6. 运行 [`scripts/init-settings.sh`](scripts/init-settings.sh)，分阶段编译工具链、内核、插件和固件。

删除 feed 目录后必须执行 `./scripts/feeds update -i`，否则旧索引可能导致代理依赖包找不到或安装到错误来源。

## macOS M4 本地编译与 UTM 验证

macOS 原生环境不是当前 CI 的编译环境。Mac mini M4 可以通过 UTM、Docker 或 Linux 虚拟机提供 Linux 构建环境，但 GitHub Actions 的 Ubuntu 24.04 是最接近发布环境的复现方式。

仓库中的 [`vm/README.md`](vm/README.md) 用于启动和验证 x86/64 Release 固件，不是 macOS 原生编译器。当前通用构建脚本实际将默认 LAN 地址改为 `192.168.0.1`；旧 Release 文案中的 `192.168.8.1` 不能作为地址依据，不同 target 请以刷入后的串口或 `ip addr` 输出为准。

## 常用操作

```bash
# 手动触发 x86 构建
gh workflow run build-x86.yml --ref main

# 查看最近运行
gh run list --workflow build-x86.yml --branch main --limit 5

# 以 10 分钟间隔监控，并在失败时返回非零状态
gh run watch <run-id> --compact --interval 600 --exit-status
```

## 上游与配置入口

- 上游源码：[coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)
- PassWall/代理 feed：[kenzok8/small-package](https://github.com/kenzok8/small-package)
- iStore feed：[linkease/istore](https://github.com/linkease/istore)
- 平台和软件包配置：[`configs/`](configs/)
- Feed 注入：[`scripts/feeds-extra.sh`](scripts/feeds-extra.sh)
- 冲突清理：[`scripts/packages.sh`](scripts/packages.sh)
- 本地 VM 验证：[`vm/README.md`](vm/README.md)
- 许可证：[`LICENSE`](LICENSE)
