#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

PANEL_PORT_DEFAULT="2053"
INBOUND_PORT_DEFAULT="8443"
WS_PATH_DEFAULT="/11"
PANEL_USER_DEFAULT="admin"

log() { echo -e "${GREEN}[OK]${PLAIN} $*"; }
info() { echo -e "${BLUE}[INFO]${PLAIN} $*"; }
warn() { echo -e "${YELLOW}[WARN]${PLAIN} $*"; }
die() { echo -e "${RED}[ERR]${PLAIN} $*" >&2; exit 1; }

on_error() {
  local line="$1"
  echo
  die "脚本在第 ${line} 行失败。请把上方报错截图/复制给 AI 排查。"
}
trap 'on_error $LINENO' ERR

need_root() {
  [[ "${EUID}" -eq 0 ]] || die "请用 root 用户运行。先执行：sudo -i，然后再运行本脚本。"
}

detect_os() {
  [[ -f /etc/os-release ]] || die "无法识别系统。建议使用 Debian 11/12 或 Ubuntu 20.04/22.04。"
  # shellcheck disable=SC1091
  source /etc/os-release
  OS_ID="${ID:-}"
  OS_VERSION="${VERSION_ID:-}"
  case "${OS_ID}" in
    debian|ubuntu) ;;
    *) die "当前系统是 ${PRETTY_NAME:-unknown}。本脚本只支持 Debian/Ubuntu。" ;;
  esac
  log "系统检测通过：${PRETTY_NAME:-${OS_ID} ${OS_VERSION}}"
}

ask_required() {
  local prompt="$1"
  local value=""
  while [[ -z "${value}" ]]; do
    read -r -p "${prompt}: " value
  done
  printf '%s' "${value}"
}

ask_default() {
  local prompt="$1"
  local default="$2"
  local value=""
  read -r -p "${prompt} [默认：${default}]: " value
  printf '%s' "${value:-$default}"
}

ask_secret() {
  local prompt="$1"
  local value=""
  while [[ -z "${value}" ]]; do
    read -r -p "${prompt}: " value
  done
  printf '%s' "${value}"
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local suffix="[Y/n]"
  [[ "${default}" == "n" ]] && suffix="[y/N]"
  local answer=""
  read -r -p "${prompt} ${suffix}: " answer
  answer="${answer:-$default}"
  [[ "${answer}" =~ ^[Yy]$ ]]
}

valid_domain() {
  [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

valid_panel_password() {
  local password="$1"
  [[ ${#password} -ge 8 ]] || return 1
  case "${password}" in
    *[[:space:]]*|*\**|*\?*|*\[*) return 1 ;;
    *) return 0 ;;
  esac
}

normalize_ws_path() {
  local path="$1"
  [[ "${path}" == /* ]] || path="/${path}"
  printf '%s' "${path}"
}

install_packages() {
  info "安装基础依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl wget tar socat ca-certificates cron jq iproute2
  systemctl enable cron >/dev/null 2>&1 || true
  systemctl start cron >/dev/null 2>&1 || true
  log "基础依赖安装完成"
}

collect_inputs() {
  echo
  echo "===================="
  echo "  x-ui 节点一键脚本"
  echo "===================="
  echo
  echo "运行前请确认："
  echo "1. VPS 已购买，并且你已经 SSH 登录到了 VPS"
  echo "2. 域名已经托管到 Cloudflare"
  echo "3. 你有 Cloudflare API Token，权限需要 Zone:Read + DNS:Edit"
  echo

  DOMAIN="$(ask_required "请输入你的域名，例如 example.com")"
  valid_domain "${DOMAIN}" || die "域名格式不正确：${DOMAIN}"

  CF_TOKEN="$(ask_secret "请输入 Cloudflare API Token（会显示，确认没人能看到你的屏幕）")"
  CF_TOKEN="${CF_TOKEN//[[:space:]]/}"

  PANEL_USER="${PANEL_USER_DEFAULT}"
  while true; do
    PANEL_PASS="$(ask_secret "设置 x-ui 面板密码，至少 8 位，不要包含空格、*、?、[（会显示）")"
    valid_panel_password "${PANEL_PASS}" && break
    warn "密码格式不合适。请至少 8 位，并避免空格、*、?、[。"
  done

  PANEL_PORT="${PANEL_PORT_DEFAULT}"
  INBOUND_PORT="${INBOUND_PORT_DEFAULT}"
  WS_PATH="${WS_PATH_DEFAULT}"
  if ask_yes_no "是否自定义端口和路径？不懂就直接回车" "n"; then
    PANEL_PORT="$(ask_default "设置 x-ui 面板端口" "${PANEL_PORT_DEFAULT}")"
    valid_port "${PANEL_PORT}" || die "面板端口不合法：${PANEL_PORT}"

    INBOUND_PORT="$(ask_default "设置节点端口" "${INBOUND_PORT_DEFAULT}")"
    valid_port "${INBOUND_PORT}" || die "节点端口不合法：${INBOUND_PORT}"

    WS_PATH="$(ask_default "设置 WebSocket 路径" "${WS_PATH_DEFAULT}")"
    WS_PATH="$(normalize_ws_path "${WS_PATH}")"
  fi

  SERVER_IP="$(curl -fsSL4 --max-time 8 https://api.ipify.org || true)"
  if [[ -z "${SERVER_IP}" ]]; then
    SERVER_IP="$(ask_required "自动获取 VPS IPv4 失败，请手动输入 VPS IPv4")"
  else
    SERVER_IP="$(ask_default "确认 VPS IPv4" "${SERVER_IP}")"
  fi

  echo
  echo "请确认配置："
  echo "域名：${DOMAIN}"
  echo "VPS IPv4：${SERVER_IP}"
  echo "x-ui 面板用户名：${PANEL_USER}"
  echo "x-ui 面板端口：${PANEL_PORT}"
  echo "节点端口：${INBOUND_PORT}"
  echo "WebSocket 路径：${WS_PATH}"
  echo
  ask_yes_no "确认开始安装吗" "y" || die "已取消"
}

cloudflare_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  if [[ -n "${data}" ]]; then
    curl --http1.1 -sSL -X "${method}" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${CF_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "${data}"
  else
    curl --http1.1 -sSL -X "${method}" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${CF_TOKEN}" \
      -H "Content-Type: application/json"
  fi
}

cloudflare_success() {
  jq -e '.success == true' >/dev/null
}

get_zone_name() {
  local domain="$1"
  local zone=""
  local rest="${domain}"
  while [[ "${rest}" == *.* ]]; do
    local resp
    resp="$(cloudflare_api GET "/zones?name=${rest}&status=active" || true)"
    if [[ "$(echo "${resp}" | jq -r '.success // false')" == "true" ]]; then
      zone="$(echo "${resp}" | jq -r '.result[0].name // empty')"
      [[ -n "${zone}" ]] && break
    fi
    rest="${rest#*.}"
  done
  [[ -n "${zone}" ]] || die "Cloudflare 找不到这个域名的 Zone。请确认域名已添加到 Cloudflare，且 Token 有 Zone:Read 权限。"
  printf '%s' "${zone}"
}

upsert_dns_record() {
  info "检查 Cloudflare Zone..."
  ZONE_NAME="$(get_zone_name "${DOMAIN}")"
  local zone_resp
  zone_resp="$(cloudflare_api GET "/zones?name=${ZONE_NAME}&status=active")"
  echo "${zone_resp}" | cloudflare_success || die "获取 Cloudflare Zone ID 失败：$(echo "${zone_resp}" | jq -r '.errors[0].message // "未知错误"')"
  ZONE_ID="$(echo "${zone_resp}" | jq -r '.result[0].id')"
  [[ -n "${ZONE_ID}" && "${ZONE_ID}" != "null" ]] || die "获取 Cloudflare Zone ID 失败"

  if ! ask_yes_no "是否自动把域名 A 记录解析到当前 VPS IP？建议选 Y" "y"; then
    warn "已跳过 DNS 自动解析。请手动在 Cloudflare 添加 A 记录：${DOMAIN} -> ${SERVER_IP}，先设为 DNS Only。"
    return
  fi

  info "写入 DNS A 记录：${DOMAIN} -> ${SERVER_IP}"
  local existing
  existing="$(cloudflare_api GET "/zones/${ZONE_ID}/dns_records?type=A&name=${DOMAIN}" | jq -r '.result[0].id // empty')"
  local payload
  payload="$(jq -nc --arg type "A" --arg name "${DOMAIN}" --arg content "${SERVER_IP}" \
    '{type:$type,name:$name,content:$content,ttl:1,proxied:false}')"

  if [[ -n "${existing}" ]]; then
    cloudflare_api PUT "/zones/${ZONE_ID}/dns_records/${existing}" "${payload}" | cloudflare_success || die "更新 Cloudflare DNS 记录失败"
  else
    cloudflare_api POST "/zones/${ZONE_ID}/dns_records" "${payload}" | cloudflare_success || die "创建 Cloudflare DNS 记录失败"
  fi
  log "DNS A 记录已设置为 DNS Only。等节点可用后，再去 Cloudflare 打开橙色云朵。"
}

check_ports() {
  if ! command -v ss >/dev/null 2>&1; then
    return
  fi

  if command -v x-ui >/dev/null 2>&1; then
    warn "检测到 x-ui 已安装，跳过端口占用检查，避免影响重复运行。"
    return
  fi

  if ss -ltn "( sport = :${PANEL_PORT} )" | grep -q ":${PANEL_PORT}"; then
    die "端口 ${PANEL_PORT} 已被占用。请重新运行脚本，并在高级参数里换一个面板端口。"
  fi

  if ss -ltn "( sport = :${INBOUND_PORT} )" | grep -q ":${INBOUND_PORT}"; then
    die "端口 ${INBOUND_PORT} 已被占用。请重新运行脚本，并在高级参数里换一个节点端口。"
  fi
}

install_x_ui() {
  if command -v x-ui >/dev/null 2>&1 && [[ -d /usr/local/x-ui ]]; then
    warn "检测到 x-ui 已安装，跳过安装，仅更新面板账号和端口。"
    /usr/local/x-ui/x-ui setting -username "${PANEL_USER}" -password "${PANEL_PASS}"
    /usr/local/x-ui/x-ui setting -port "${PANEL_PORT}"
    systemctl restart x-ui
    log "x-ui 设置已更新"
    return
  fi

  info "下载并安装 x-ui 官方脚本..."
  local installer="/tmp/x-ui-install.sh"
  curl -fsSL https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh -o "${installer}"
  chmod +x "${installer}"

  # 官方安装器会依次询问：是否继续、用户名、密码、面板端口。
  printf 'y\n%s\n%s\n%s\n' "${PANEL_USER}" "${PANEL_PASS}" "${PANEL_PORT}" | bash "${installer}"

  systemctl enable x-ui >/dev/null 2>&1 || true
  systemctl restart x-ui
  log "x-ui 安装完成"
}

issue_certificate() {
  info "安装 acme.sh 并申请 TLS 证书..."
  if [[ ! -x "${HOME}/.acme.sh/acme.sh" ]]; then
    curl https://get.acme.sh | sh
  fi

  export CF_Token="${CF_TOKEN}"
  export CF_Zone_ID="${ZONE_ID}"
  "${HOME}/.acme.sh/acme.sh" --set-default-ca --server letsencrypt

  if ! "${HOME}/.acme.sh/acme.sh" --issue --dns dns_cf -d "${DOMAIN}" --keylength ec-256; then
    warn "ECC 证书申请失败，尝试重新申请 RSA 证书..."
    "${HOME}/.acme.sh/acme.sh" --issue --dns dns_cf -d "${DOMAIN}" --force
    CERT_ECC="0"
  else
    CERT_ECC="1"
  fi

  mkdir -p /root/cert
  if [[ "${CERT_ECC}" == "1" ]]; then
    "${HOME}/.acme.sh/acme.sh" --install-cert -d "${DOMAIN}" --ecc \
      --fullchain-file /root/cert/fullchain.cer \
      --key-file "/root/cert/${DOMAIN}.key" \
      --reloadcmd "systemctl restart x-ui >/dev/null 2>&1 || true"
  else
    "${HOME}/.acme.sh/acme.sh" --install-cert -d "${DOMAIN}" \
      --fullchain-file /root/cert/fullchain.cer \
      --key-file "/root/cert/${DOMAIN}.key" \
      --reloadcmd "systemctl restart x-ui >/dev/null 2>&1 || true"
  fi

  chmod 755 /root/cert
  chmod 644 /root/cert/fullchain.cer
  chmod 600 "/root/cert/${DOMAIN}.key"
  log "证书申请完成"
}

configure_firewall() {
  info "检查防火墙..."
  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -qi "Status: active"; then
      ufw allow 22/tcp
      ufw allow "${PANEL_PORT}/tcp"
      ufw allow "${INBOUND_PORT}/tcp"
      log "UFW 已放行 22、${PANEL_PORT}、${INBOUND_PORT}"
    else
      info "UFW 未开启，跳过防火墙修改"
    fi
  else
    info "未检测到 UFW，跳过防火墙修改"
  fi
}

enable_bbr() {
  info "开启 BBR..."
  cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null || true

  local current
  current="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  if [[ "${current}" == "bbr" ]]; then
    log "BBR 已开启"
  else
    warn "BBR 未成功开启。可能是内核不支持，节点仍可正常使用。"
  fi
}

print_result() {
  local panel_url="http://${SERVER_IP}:${PANEL_PORT}"
  cat <<EOF

${GREEN}============================================================${PLAIN}
安装完成
${GREEN}============================================================${PLAIN}

1. 打开 x-ui 面板：
   ${panel_url}

2. 登录信息：
   用户名：${PANEL_USER}
   密码：你刚才设置的面板密码

3. 在 x-ui 里添加入站：
   入站列表 -> 添加

   备注：随便填，例如 MyVLESS
   协议：vless
   端口：${INBOUND_PORT}
   传输协议：ws
   Path：${WS_PATH}
   Security：tls
   SNI / serverName：${DOMAIN}
   公钥路径：/root/cert/fullchain.cer
   密钥路径：/root/cert/${DOMAIN}.key

4. 保存后复制链接或二维码，导入 Shadowrocket / V2rayN / V2rayNG。

5. 确认能连接后，去 Cloudflare DNS 页面把 ${DOMAIN} 的小云朵打开为橙色。
   然后去 SSL/TLS -> Overview，把模式改成 Full (strict)。

6. 如果你要使用 Cloudflare 优选 IP：
   客户端里的地址可以改成优选 IP，但 SNI / Host 仍然保持 ${DOMAIN}。

${YELLOW}安全提醒：${PLAIN}
- 不要把 Cloudflare Token、VPS root 密码、x-ui 面板密码发给别人。
- x-ui 面板端口 ${PANEL_PORT} 建议只自己使用，不要公开传播。
- 如果 VPS 控制台有防火墙，还需要在 VPS 服务商后台放行 ${PANEL_PORT} 和 ${INBOUND_PORT}。

EOF
}

main() {
  need_root
  detect_os
  collect_inputs
  install_packages
  upsert_dns_record
  check_ports
  install_x_ui
  issue_certificate
  configure_firewall
  enable_bbr
  print_result
}

main "$@"
