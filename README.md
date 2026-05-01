# VPS购买：https://www.vultr.com/?ref=9842421

# xui-vless-oneclick

A simple one-click setup script for deploying an x-ui based VLESS + WebSocket + TLS node on a fresh Debian/Ubuntu VPS.

This script is intended for beginners who already have a VPS, a domain, and a Cloudflare account.

## What You Need

Before running the script, prepare:

1. A VPS
   - Recommended system: Debian 11/12 or Ubuntu 20.04/22.04
   - You need the VPS IPv4 address and root password

2. A domain name
   - The domain should already be added to Cloudflare
   - The domain nameservers should already point to Cloudflare

3. A Cloudflare API Token
   - Required permissions:
     - Zone: Read
     - DNS: Edit
   - Scope: only the domain you will use

## Quick Start

SSH into your VPS:

```bash
ssh root@YOUR_VPS_IP
```

Then run:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/wtasainof/xui-vless-oneclick/main/oneclick-xui-vless.sh)
```

Follow the prompts in the terminal.

For most users, the default values are enough:

```text
x-ui username: admin
x-ui panel port: 2053
VLESS inbound port: 8443
WebSocket path: /11
```

## What The Script Does

The script will:

- Install required packages
- Detect Debian/Ubuntu system compatibility
- Configure the Cloudflare DNS A record for your domain
- Install x-ui
- Set the x-ui panel username, password, and port
- Issue a TLS certificate with acme.sh and Cloudflare DNS
- Save the certificate to `/root/cert`
- Enable BBR when supported
- Print the x-ui inbound configuration you need to fill in

## After Installation

Open the x-ui panel in your browser:

```text
http://YOUR_VPS_IP:2053
```

Log in with:

```text
Username: admin
Password: the password you set during installation
```

Then add a new inbound in x-ui:

```text
Protocol: vless
Port: 8443
Transport: ws
Path: /11
Security: tls
SNI / serverName: your domain
Certificate file: /root/cert/fullchain.cer
Key file: /root/cert/your-domain.com.key
```

Save the inbound, then import the generated link or QR code into your client.

Common clients:

- Shadowrocket
- V2rayN
- V2rayNG

## Cloudflare Final Settings

After the node works, go to Cloudflare:

1. Open the DNS page for your domain
2. Turn on the orange cloud for the A record
3. Go to SSL/TLS
4. Set SSL mode to `Full (strict)`

If you use a Cloudflare optimized IP, keep SNI / Host as your domain.

## Security Notes

- Do not share your VPS root password
- Do not share your Cloudflare API Token
- Do not share your x-ui panel password
- Use a Cloudflare API Token scoped only to the required domain
- Delete temporary tokens after use
- Make sure your VPS provider firewall allows the panel port and inbound port

## Disclaimer

This script is provided for educational and personal server administration use. You are responsible for following the laws, platform rules, and network policies that apply to your location and services.

---

# 中文说明

这是一个适合新手使用的 x-ui 一键部署脚本，用于在全新的 Debian/Ubuntu VPS 上搭建 VLESS + WebSocket + TLS 节点。

脚本适合已经准备好 VPS、域名和 Cloudflare 账号的用户。

## 运行前需要准备

运行脚本前，请先准备：

1. 一台 VPS
   - 推荐系统：Debian 11/12 或 Ubuntu 20.04/22.04
   - 需要保存 VPS IPv4 地址和 root 密码

2. 一个域名
   - 域名需要已经添加到 Cloudflare
   - 域名的 Nameserver 需要已经改成 Cloudflare 提供的地址

3. 一个 Cloudflare API Token
   - 需要的权限：
     - Zone: Read
     - DNS: Edit
   - 作用范围建议只选择你要使用的域名

## 快速开始

先 SSH 登录你的 VPS：

```bash
ssh root@你的VPS_IP
```

然后运行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/wtasainof/xui-vless-oneclick/main/oneclick-xui-vless.sh)
```

按照终端提示填写信息即可。

大多数用户直接使用默认值就可以：

```text
x-ui 用户名：admin
x-ui 面板端口：2053
VLESS 节点端口：8443
WebSocket 路径：/11
```

## 脚本会做什么

脚本会自动完成：

- 安装基础依赖
- 检查 Debian/Ubuntu 系统兼容性
- 将 Cloudflare DNS A 记录解析到当前 VPS IP
- 安装 x-ui
- 设置 x-ui 面板用户名、密码和端口
- 使用 acme.sh + Cloudflare DNS 申请 TLS 证书
- 将证书保存到 `/root/cert`
- 在系统支持时开启 BBR
- 输出 x-ui 入站配置填写说明

## 安装完成后

在浏览器打开 x-ui 面板：

```text
http://你的VPS_IP:2053
```

登录信息：

```text
用户名：admin
密码：你在脚本运行时设置的面板密码
```

然后在 x-ui 中添加一个新的入站：

```text
协议：vless
端口：8443
传输协议：ws
Path：/11
Security：tls
SNI / serverName：你的域名
公钥路径：/root/cert/fullchain.cer
密钥路径：/root/cert/你的域名.key
```

保存后，复制生成的链接或二维码导入客户端即可。

常见客户端：

- Shadowrocket
- V2rayN
- V2rayNG

## Cloudflare 最后设置

确认节点能正常连接后，进入 Cloudflare：

1. 打开域名的 DNS 页面
2. 将 A 记录的小云朵打开为橙色
3. 进入 SSL/TLS 页面
4. 将 SSL 模式设置为 `Full (strict)`

如果你使用 Cloudflare 优选 IP，客户端里的 SNI / Host 仍然要保持你的域名。

## 安全提醒

- 不要泄露 VPS root 密码
- 不要泄露 Cloudflare API Token
- 不要泄露 x-ui 面板密码
- Cloudflare API Token 建议只授权给需要使用的域名
- 临时 Token 用完后及时删除
- 如果 VPS 服务商后台有防火墙，需要放行面板端口和节点端口

## 免责声明

本脚本仅用于学习和个人服务器管理。请自行遵守你所在地区、相关平台和网络服务的法律法规与使用规则。
