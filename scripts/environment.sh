#!/bin/bash

# 非交互安装，避免 debconf 在无 TTY 环境下等待输入。
export DEBIAN_FRONTEND=noninteractive

# --no-install-recommends：构建不需要 texlive/dblatex/docbook 文档链，
# 默认推荐包会额外拉 700MB+，慢镜像下曾导致初始化超时（run 42812521548）。
# xmlto 依赖的 docbook-xml/docbook-xsl/xsltproc 在 Depends 中，仍会安装。
sudo -E apt-get install -y --no-install-recommends \
-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 \
ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
bzip2 ccache clang cmake cpio curl device-tree-compiler flex gawk gcc-multilib g++-multilib gettext \
genisoimage git gperf haveged help2man intltool libc6-dev-i386 libelf-dev libfuse-dev libglib2.0-dev \
libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libpython3-dev \
libreadline-dev libssl-dev libtool llvm lrzsz msmtp ninja-build p7zip p7zip-full patch pkgconf \
python3 python3-pyelftools python3-setuptools qemu-utils rsync scons squashfs-tools subversion \
swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev bash coreutils

# 确认 clang 版本 - gn (naiveproxy 依赖, helloworld feed) 需 clang>=12 支持 C++20 <=>
# ubuntu-24.04 默认 clang 为 16/18, 足够; xiaorouji 仓库的 naiveproxy 是预编译包, 不编译 gn, 不触发此问题
echo "clang version: $(clang --version 2>/dev/null | head -1)"


