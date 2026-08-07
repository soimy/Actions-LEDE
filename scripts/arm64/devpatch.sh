#!/bin/bash

#删除feeds中的插件
rm -rf ./feeds/packages/net/smartdns

#克隆插件
rm -rf feeds/ssrp/ipt2socks

git clone https://github.com/xiaorouji/openwrt-passwall-packages.git package/pwpage

mkdir package/small
pushd package/small
#lucky
git clone -b main  https://github.com/sirpdboy/luci-app-lucky.git
#smartdns
git clone -b lede --depth 1 https://github.com/pymumu/luci-app-smartdns.git
git clone -b master https://github.com/pymumu/smartdns.git
#passwall
git clone -b luci --depth 1 https://github.com/xiaorouji/openwrt-passwall.git

popd
