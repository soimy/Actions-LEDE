# LEDE x86 本地 VM 验证

在宿主机用 QEMU/KVM 跑本仓库 CI 产出的 x86-64 固件，双网卡拓扑：

| 角色 | 虚拟接口 | 用途 |
|------|----------|------|
| LAN (eth0 → br-lan) | `tap-lede-lan` → `br-lede` | 宿主机访问 LuCI `http://192.168.0.1` |
| WAN (eth1) | `macvtap-lede` → 物理网卡 | 从家庭局域网 DHCP 上联 |

> **LAN 地址**：本仓库 `scripts/init-settings.sh` 将 OpenWrt 默认 `192.168.1.1` 替换为 **`192.168.0.1`**（注释里的 192.168.8.1 与 sed 实际不一致）。可用环境变量 `LAN_LEDE_IP` / `LAN_HOST_IP` 覆盖。

## 依赖

- `gh`（已登录）、`qemu-system-x86_64`、`qemu-img`、`nmcli`、`ip`
- KVM：`/dev/kvm`（本机 Bazzite 已可用）
- OVMF：`/usr/share/edk2/ovmf/OVMF_*.fd`（EFI 镜像）
- 创建 bridge / macvtap 需要 sudo

## 一键部署

```bash
cd vm
./deploy.sh          # 拉最新 X86-64 release → qcow2 → 建网
./run.sh             # 前台串口控制台（Ctrl-A X 退出 QEMU）
# 或
./deploy.sh --run-bg # 部署并后台启动
```

固件来源：GitHub Release 标签匹配 `X86-64`（如 `2026.08.04_X86-64`），资产  
`openwrt-x86-64-generic-squashfs-combined-efi.img.gz`。

## 常用命令

```bash
./fetch.sh                 # 仅下载最新固件
./fetch.sh 2026.08.04_X86-64   # 指定 tag
./prepare.sh               # 转 qcow2 + OVMF_VARS
./net-up.sh                # 建 br-lede + tap + macvtap
./net-down.sh              # 删 tap/macvtap（保留桥）
./net-down.sh --bridge     # 连 NM 桥一起删
./run.sh                   # 启动
RUN_BG=1 ./run.sh          # 后台
./stop.sh                  # 停 QEMU
./stop.sh --net            # 停 QEMU + 虚拟网卡
./stop.sh --all            # 停 QEMU + 网卡 + 删桥
```

## 验证

```bash
ping -c2 192.168.0.1
curl -I http://192.168.0.1
# 浏览器打开 http://192.168.0.1
```

在 LEDE 串口或 `ssh root@192.168.0.1` 中检查 WAN 是否拿到局域网地址：

```sh
ip addr show
ping -c2 192.168.1.1
```

## 环境变量（可选）

| 变量 | 默认 | 说明 |
|------|------|------|
| `PHY` | 默认路由网卡 | WAN 所用物理口 |
| `LAN_BR` | `br-lede` | LAN 桥名 |
| `LAN_HOST_IP` | `192.168.0.2/24` | 宿主机在 LAN 上的地址 |
| `LAN_LEDE_IP` | `192.168.0.1` | LEDE br-lan 地址（仅提示用） |
| `MEM_MB` / `SMP` | `1024` / `2` | 内存 / vCPU |
| `DISK_SIZE` | `2G` | qcow2 扩容目标 |
| `GH_REPO` | 当前仓库 | `owner/name` |
| `RUN_BG` | `0` | `1` 后台启动 |

## 目录（均被 gitignore）

```
vm/firmware/   # 下载的 .img.gz / sha256sums
vm/images/     # lede-x86.qcow2
vm/state/      # OVMF_VARS、pid、日志、net.env、release.txt
```

## 注意

- **macvtap**：宿主机与 WAN 侧客户机通常不能经同一物理口互通；访问 LuCI 请走 `br-lede`。
- 不要把本机默认路由长期指到 `192.168.0.1`，除非刻意测双 NAT。
- Atomic（Bazzite）上 bridge/macvtap 需 sudo；脚本会自动 `sudo`。
- 后台启动后串口在 `state/qemu.log`；前台 `./run.sh` 用 `Ctrl-a x` 退出 QEMU。
