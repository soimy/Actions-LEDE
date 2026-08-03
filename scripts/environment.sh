#!/bin/bash

sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
bzip2 ccache clang cmake cpio curl device-tree-compiler flex gawk gcc-multilib g++-multilib gettext \
genisoimage git gperf haveged help2man intltool libc6-dev-i386 libelf-dev libfuse-dev libglib2.0-dev \
libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libpython3-dev \
libreadline-dev libssl-dev libtool llvm lrzsz msmtp ninja-build p7zip p7zip-full patch pkgconf \
python3 python3-pyelftools python3-setuptools qemu-utils rsync scons squashfs-tools subversion \
swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev bash coreutils

# 安装 Node.js 20 - smartdns-ui 的 webui 用 Next.js 16 + React 19 + ESLint 9, 需要 node>=20
# lede 自带的 host node 包是 v16, 编译 smartdns-webui 的 npm run build 会因 ESLint 9 的 ES2025 语法失败
# 装系统 node 20, 编译 smartdns 时让系统 node 优先于 lede staging 的 v16 (见 build-x86.yml 编译插件步骤)
if ! command -v node >/dev/null 2>&1 || [ "$(node -v 2>/dev/null | cut -d. -f1 | tr -d v)" -lt 20 ]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
echo "node version: $(node -v 2>/dev/null), npm version: $(npm -v 2>/dev/null)"

# 确认 clang 版本 - gn (naiveproxy 依赖, helloworld feed) 需 clang>=12 支持 C++20 <=>
# ubuntu-22.04 默认 clang 为 14, 足够; xiaorouji 仓库的 naiveproxy 是预编译包, 不编译 gn, 不触发此问题
echo "clang version: $(clang --version 2>/dev/null | head -1)"

