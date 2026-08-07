# Actions-LEDE CI 编译踩坑 Handoff

> 仓库 `soimy/Actions-LEDE`，用 GitHub Actions 编译 `coolsnowwolf/lede`（x86_64）。
> 本文档记录 CI 配置要点 + 已知坑 + 与本地编译的差异。

---

## CI 架构

```
.github/workflows/build-x86.yml   # 主流程
configs/packages-x86.txt          # .config 片段(追加到 openwrt/.config)
scripts/environment.sh            # 装 apt 依赖
scripts/feeds-extra.sh            # feeds update 前注入 smpackage + istore
scripts/packages.sh               # feeds update 后清理冲突（kenzok8 惯例）
scripts/init-settings.sh          # 改默认 IP 为 192.168.0.1
```

流程：clone lede → feeds-extra.sh 注入源 → feeds update -a → packages.sh 清冲突 → feeds install -a → 追加 packages-x86.txt → make defconfig → 分阶段编译。

第三方源（lede 默认 feeds **已不再**自带这些）：
- `kenzok8/small-package` → feed 名 `smpackage`（PassWall 及代理后端）
- `linkease/istore` → feed 名 `istore`（官方应用商店 luci-app-store）

---

## CI 与本地编译的关键差异（避免误判）

| 项目 | 本地(WSL2) | CI(ubuntu-22.04) |
|------|-----------|-------------------|
| naiveproxy | helloworld feed **源码编译**, 依赖 gn → 需 clang≥12 | smpackage 内 **预编译/同步上游**, 一般不编 gn |
| rust PATH | WSL 注入含空格 Windows PATH → find -execdir 失败 | 干净环境, 无此问题 |
| ksmbd | 与内核 6.12 不兼容 | 已用 SAMBA4 避开 |
| binutils | 本地 glibc 兼容 | **22.04 glibc 2.31 兼容(已从 24.04 改过来)** |

**结论**：本地踩的 gn/rust/PATH 坑，CI **都不会命中**（原因见上）。CI 只需关注 binutils。

---

## 已修复的坑

### 1. binutils 2.42 在 ubuntu-24.04 编译失败（CI 实际失败原因）

**现象**：`toolchain/binutils failed to build`，链接报：
```
undefined reference to `__snprintf_chk'
undefined reference to `__sprintf_chk'
undefined reference to `__memmove_chk'
collect2: error: ld returned 1 exit status
```

**根因**：ubuntu-24.04 的 glibc 2.39 与 binutils 2.42 host build 的 FORTIFY_SOURCE 不兼容。7-23 成功是 cachewrtbuild 缓存命中跳过了 binutils，7-30 缓存失效重编就挂。

**修复**：`runs-on: ubuntu-22.04`（glibc 2.31，lede 社区主流验证环境）。已改 build-x86.yml。

**备选**：升级 binutils 到 2.43.1（`CONFIG_BINUTILS_VERSION_2_43_1=y`），但 22.04 + 2.42 已足够稳。

### 2. vsftpd / vsftpd-alt 文件冲突

两包都装 `/usr/sbin/vsftpd`，opkg 不允许文件冲突，导致 `package/install` Error 255。已在 packages-x86.txt 显式禁用两者。

### 3. ksmbd 与内核 6.12 不兼容

ksmbd 3.5.4 的 `vfs_path_parent_lookup` 签名/`LAST_NORM` 在 6.12 已变。autosamba 默认选 KSMBD 会编译失败。已在 packages-x86.txt 显式选 SAMBA4 + 禁用 KSMBD。

---

## CI 配置补齐项（相对本地）

已加到 `configs/packages-x86.txt`：
- **istore**：`luci-app-store` + `taskd` + `luci-lib-taskd` + `luci-lib-xterm`（**linkease/istore**；smpackage 内副本会删掉以免重名）
- **passwall**：来自 **kenzok8/small-package**（不再 git clone 已 404 的 xiaorouji 仓库）
- **autosamba**：`autosamba` + `INCLUDE_SAMBA4` + `luci-app-samba4`（避开 ksmbd 坑）

---

## 仍需注意

- **cachewrtbuild 缓存**：CI 用 `klever1988/cachewrtbuild@main` 缓存 toolchain。改 runner(22.04) 后首次会全量编译（约 2h），之后缓存命中会快很多。缓存 key 含 `mixkey: 'x86'`，改 runner 版本不会污染旧缓存。
- **NaiveProxy**：随 smpackage 同步；若改源码编译需 clang≥12（ubuntu-24.04 足够）。
- **递归依赖噪音**：`make defconfig` 会报 3 个 recursive dependency（fchomo/nikki、easymesh、baresip），是 feed 上游 Kconfig bug，不阻断编译，可忽略。

---

## 本地编译完整经验

见仓库根目录 `HANDOFF.md`（如有）或本地 lede 仓库的 handoff 文档，记录了 WSL2 环境的 6 个坑完整修复。
