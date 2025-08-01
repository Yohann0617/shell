#!/bin/bash

# ====== 美化输出函数 ======
color_green() { echo -e "\033[1;32m$*\033[0m"; }
color_yellow() { echo -e "\033[1;33m$*\033[0m"; }
color_red() { echo -e "\033[1;31m$*\033[0m"; }

# ====== 判断 IPv4 是否是内网地址 ======
function is_private_ipv4() {
    local ip=$1
    [[ $ip =~ ^10\. ]] || [[ $ip =~ ^192\.168\. ]] || [[ $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]
}

# ====== 判断 IPv6 是否是链路本地或本地地址 ======
function is_local_ipv6() {
    local ip=$1
    [[ $ip =~ ^fe80: ]] || [[ $ip =~ ^fc00: ]] || [[ $ip =~ ^fd00: ]]
}

echo "📡 获取本机所有 IPv4 和 IPv6 地址..."

# ====== 获取所有有效接口名 ======
interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|docker|veth|br-|tun|tap')

has_ip=0

for iface in $interfaces; do
    ipv4=$(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    ipv6=$(ip -6 addr show "$iface" | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/)' | grep -v '^fe80')

    if [ -n "$ipv4" ]; then
        echo "✅ 接口 $iface 的 IPv4 地址: $ipv4"
        if is_private_ipv4 "$ipv4"; then
            pub4=$(curl --interface "$iface" -s4 https://speed.cloudflare.com/meta | grep -oP '"clientIp":"\K[^"]+')
            echo "✅ 接口 $iface 检测到内网 IPv4，公网 IPv4 为: $pub4"
        fi
    fi

    if [ -n "$ipv6" ]; then
        echo "✅ 接口 $iface 的 IPv6 地址: $ipv6"
        if is_local_ipv6 "$ipv6"; then
            pub6=$(curl --interface "$iface" -s6 https://speed.cloudflare.com/meta | grep -oP '"clientIp":"\K[^"]+')
            echo "✅ 接口 $iface 检测到内网 IPv6，公网 IPv6 为: $pub6"
        fi
    fi
done

# ====== 默认出口 IPv4 ======
default_ipv4=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+')
if [ -n "$default_ipv4" ]; then
    if is_private_ipv4 "$default_ipv4"; then
        pub4=$(curl --interface "$iface" -s4 https://speed.cloudflare.com/meta | grep -oP '"clientIp":"\K[^"]+')
        color_yellow "🌐 默认出口 IPv4: $pub4"
    else
        color_yellow "🌍 默认出口 IPv4: $default_ipv4"
    fi
    has_ip=1
fi

# ====== 默认出口 IPv6 ======
default_ipv6=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | grep -oP 'src \K[0-9a-f:]+')
if [ -n "$default_ipv6" ]; then
    if is_local_ipv6 "$default_ipv6"; then
        pub6=$(curl --interface "$iface" -s6 https://speed.cloudflare.com/meta | grep -oP '"clientIp":"\K[^"]+')
        color_yellow "🌐 默认出口 IPv6: $pub6"
    else
        color_yellow "🌍 默认出口 IPv6: $default_ipv6"
    fi
    has_ip=1
fi

# ====== 通过 Cloudflare 获取公网 IP（视条件请求） ======
if command -v curl >/dev/null 2>&1; then
    color_green "\n🔍 正在通过 Cloudflare 获取公网 IP 信息..."

    # 如果默认 IPv4 是公网，则尝试 curl -4
    if [ -n "$default_ipv4" ]; then
    # if [ -n "$default_ipv4" ] && ! is_private_ipv4 "$default_ipv4"; then
        pub_ipv4=$(curl -s4 https://speed.cloudflare.com/meta | grep -oP '"clientIp":"\K[^"]+')
        if [ -n "$pub_ipv4" ]; then
            color_yellow "☁️ 默认公网 IPv4: $pub_ipv4"
        else
            color_red "❌ 无法通过 IPv4 获取公网地址"
        fi
    fi

    # 只有当默认 IPv6 是局域网地址时才请求 Cloudflare
    if [ -n "$default_ipv6" ]; then
    # if [ -n "$default_ipv6" ] && is_local_ipv6 "$default_ipv6"; then
        pub_ipv6=$(curl -s6 https://speed.cloudflare.com/meta | grep -oP '"clientIp":"\K[^"]+')
        if [ -n "$pub_ipv6" ]; then
            color_yellow "☁️ 默认公网 IPv6: $pub_ipv6"
        else
            color_red "❌ 无法通过 IPv6 获取公网地址"
        fi
    fi
else
    color_red "❌ curl 未安装，无法从 Cloudflare 获取公网 IP"
fi

# ====== 如果未获取任何 IP，使用 Cloudflare fallback ======
# ====== Cloudflare 公网 IP 显示（总是执行） ======
if command -v curl >/dev/null 2>&1; then
    meta=$(curl -s https://speed.cloudflare.com/meta)
    pub_ip=$(echo "$meta" | grep -oP '"clientIp":"\K[^"]+')

    if [ -n "$pub_ip" ]; then
        color_yellow "☁️ 默认出口公网IP地址: $pub_ip"
    fi
    if [ -z "$pub_ip" ]; then
        color_red "❌ 无法从 Cloudflare 获取公网 IP"
    fi
else
    color_red "❌ curl 未安装，无法从 Cloudflare 获取公网 IP"
fi
