#!/bin/bash

sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
bzip2 ccache clang cmake cpio curl device-tree-compiler flex gawk gcc-multilib g++-multilib gettext \
genisoimage git gperf haveged help2man intltool libc6-dev-i386 libelf-dev libfuse-dev libglib2.0-dev \
libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libpython3-dev \
libreadline-dev libssl-dev libtool llvm lrzsz msmtp ninja-build p7zip p7zip-full patch pkgconf \
python3 python3-pyelftools python3-setuptools qemu-utils rsync scons squashfs-tools subversion \
swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev bash coreutils

# 确认 clang 版本 - gn (naiveproxy 依赖, helloworld feed) 需 clang>=12 支持 C++20 <=>
# ubuntu-22.04 默认 clang 为 14, 足够; xiaorouji 仓库的 naiveproxy 是预编译包, 不编译 gn, 不触发此问题
echo "clang version: $(clang --version 2>/dev/null | head -1)"

# 注意: node 20 的安装在 build-x86.yml 中用 actions/setup-node 完成(不在此处用 NodeSource 脚本)
# 原因: NodeSource 的 setup_20.x 脚本会装新版 coreutils/findutils, 破坏 ubuntu-22.04 的 glibc 兼容
# (find/sed/xargs 报 GLIBC_2.38 not found), 导致 feeds install 和 make defconfig 失败


