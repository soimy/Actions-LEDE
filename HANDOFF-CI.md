# Actions-LEDE CI 编译踩坑 Handoff

> 仓库 `soimy/Actions-LEDE`，用 GitHub Actions 编译 `coolsnowwolf/lede`（x86_64）。
> 本文档记录 CI 配置要点 + 已知坑 + 与本地编译的差异。

---

## CI 架构

```
.github/workflows/build-x86.yml   # 主流程
configs/packages-x86.txt          # .config 片段(追加到 openwrt/.config)
scripts/environment.sh            # 装 apt 依赖 + node20
scripts/feeds-extra.sh            # feeds update 前注入 smpackage + istore
scripts/packages.sh               # feeds update 后清理冲突（kenzok8 惯例）
scripts/init-settings.sh          # 改默认 IP 为 192.168.0.1
scripts/preset-clash-core-amd64.sh
```

流程：clone lede → feeds-extra.sh 注入源 → feeds update -a → packages.sh 清冲突 → feeds install -a → 追加 packages-x86.txt → make defconfig → 分阶段编译。

第三方源（lede 默认 feeds **已不再**自带这些）：
- `kenzok8/small-package` → feed 名 `smpackage`（PassWall / SSR+ / OpenClash 及依赖）
- `linkease/istore` → feed 名 `istore`（官方应用商店 luci-app-store）

---

## CI 与本地编译的关键差异（避免误判）

| 项目 | 本地(WSL2) | CI(ubuntu-22.04) |
|------|-----------|-------------------|
| naiveproxy | helloworld feed **源码编译**, 依赖 gn → 需 clang≥12 | smpackage 内 **预编译/同步上游**, 一般不编 gn |
| smartdns-ui | 启用, npm build 需 node20 | 默认不启用(无 npm build); 已在 packages-x86.txt 启用 |
| rust PATH | WSL 注入含空格 Windows PATH → find -execdir 失败 | 干净环境, 无此问题 |
| ksmbd | 与内核 6.12 不兼容 | 已用 SAMBA4 避开 |
| binutils | 本地 glibc 兼容 | **22.04 glibc 2.31 兼容(已从 24.04 改过来)** |

**结论**：本地踩的 gn/rust/PATH 坑，CI **都不会命中**（原因见上）。CI 只需关注 binutils + smartdns-ui(node)。

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

### 2. smartdns-ui 的 node 版本（本地踩过，CI 启用 smartdns-ui 后会命中）

**现象**：smartdns-webui 用 Next.js 16 + React 19 + ESLint 9，`npm run build` 需 node≥20。lede 自带 host node 是 v16，ESLint 9 用 ES2025 `with` 语法会报 `SyntaxError: Unexpected token 'with'`。

**修复**：
- `environment.sh` 装 node 20（NodeSource 源）
- `build-x86.yml` 编译插件步骤 `export PATH="/usr/bin:$PATH"`，让系统 node20 优先于 lede staging 的 v16

**注意**：lede 的 smartdns Build/Compile 里 `ifneq ($(CONFIG_PACKAGE_smartdns-ui),)` 才跑 npm build。不启用 smartdns-ui 就不触发，但也就没有 Web 仪表盘。

### 3. vsftpd / vsftpd-alt 文件冲突

两包都装 `/usr/sbin/vsftpd`，opkg 不允许文件冲突，导致 `package/install` Error 255。已在 packages-x86.txt 显式禁用两者。

### 4. ksmbd 与内核 6.12 不兼容

ksmbd 3.5.4 的 `vfs_path_parent_lookup` 签名/`LAST_NORM` 在 6.12 已变。autosamba 默认选 KSMBD 会编译失败。已在 packages-x86.txt 显式选 SAMBA4 + 禁用 KSMBD。

---

## CI 配置补齐项（相对本地）

已加到 `configs/packages-x86.txt`：
- **istore**：`luci-app-store` + `taskd` + `luci-lib-taskd` + `luci-lib-xterm`（**linkease/istore**；smpackage 内副本会删掉以免重名）
- **passwall / ssr+ / openclash**：来自 **kenzok8/small-package**（不再 git clone 已 404 的 xiaorouji 仓库）
- **autosamba**：`autosamba` + `INCLUDE_SAMBA4` + `luci-app-samba4`（避开 ksmbd 坑）
- **smartdns-ui**：`smartdns-ui` + `luci-app-smartdns_INCLUDE_WebUI`（配套 node20）

---

## 仍需注意

- **cachewrtbuild 缓存**：CI 用 `klever1988/cachewrtbuild@main` 缓存 toolchain。改 runner(22.04) 后首次会全量编译（约 2h），之后缓存命中会快很多。缓存 key 含 `mixkey: 'x86'`，改 runner 版本不会污染旧缓存。
- **NaiveProxy**：随 smpackage 同步；若改源码编译需 clang≥12（ubuntu-24.04 足够）。
- **递归依赖噪音**：`make defconfig` 会报 3 个 recursive dependency（fchomo/nikki、easymesh、baresip），是 feed 上游 Kconfig bug，不阻断编译，可忽略。

---

## 本地编译完整经验

见仓库根目录 `HANDOFF.md`（如有）或本地 lede 仓库的 handoff 文档，记录了 WSL2 环境的 6 个坑完整修复。
