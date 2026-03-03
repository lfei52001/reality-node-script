#!/bin/bash

# ============================================================
#  VLESS + Reality 一键部署脚本
#  支持系统: Debian 12 / Ubuntu 22.04+
#  Author: Reality Setup Script
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"

# ============================================================
# 工具函数
# ============================================================

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
step()    { echo -e "${CYAN}[*]${NC} $*"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 权限运行此脚本！"
        exit 1
    fi
}

press_any_key() {
    echo ""
    read -rp "按 Enter 键返回主菜单..." _
}

# ============================================================
# 优选伪装网站（根据IP地理位置自动选择）
# ============================================================

get_best_sni() {
    step "正在获取 VPS 地理位置，自动优选伪装网站..."

    local country=""
    # 尝试多个IP查询接口
    country=$(curl -s --max-time 6 "https://ipapi.co/country" 2>/dev/null)
    if [[ -z "$country" ]]; then
        country=$(curl -s --max-time 6 "https://api.country.is" 2>/dev/null | grep -oP '"country":"\K[^"]+')
    fi
    if [[ -z "$country" ]]; then
        country=$(curl -s --max-time 6 "https://ipinfo.io/country" 2>/dev/null)
    fi

    info "检测到 VPS 所在地区: ${BOLD}${country:-未知}${NC}"

    # 根据地区选择候选伪装站点
    # 筛选标准：① 支持 TLS 1.3  ② HTTP/2  ③ 国际知名、流量大、不易被针对
    # ④ 服务器在目标地区有节点、延迟低  ⑤ 证书稳定不频繁更换
    case "$country" in

        # ── 北美 ──────────────────────────────────────────────
        US|CA|MX)
            SNI_LIST=(
                "www.apple.com"           # Apple 全球 CDN，TLS1.3+H2，极佳
                "www.microsoft.com"       # 微软官网，Reality 最经典选择
                "login.microsoftonline.com" # 微软 AAD 登录，企业流量多
                "ajax.googleapis.com"     # Google AJAX CDN
                "dl.google.com"           # Google 下载，高流量伪装
                "www.icloud.com"          # iCloud，苹果体系流量
                "itunes.apple.com"        # Apple 媒体服务
                "swdist.apple.com"        # Apple 软件分发 CDN
                "www.amazon.com"          # 亚马逊，流量极大
                "s3.amazonaws.com"        # AWS S3，企业级流量
                "www.cloudflare.com"      # Cloudflare 官网
                "one.one.one.one"         # Cloudflare DNS（知名IP）
                "www.netflix.com"         # Netflix，娱乐流量
                "fast.com"                # Netflix 测速站
                "www.github.com"          # GitHub，开发者常用
                "github.githubassets.com" # GitHub 静态资源 CDN
                "api.github.com"          # GitHub API
                "www.twitch.tv"           # Twitch 直播，高带宽
                "discord.com"             # Discord，游戏社区
                "www.reddit.com"          # Reddit
            )
            ;;

        # ── 西欧 ──────────────────────────────────────────────
        GB|DE|FR|NL|SE|NO|FI|DK|CH|AT|BE|IE|ES|IT|PT)
            SNI_LIST=(
                "www.microsoft.com"
                "login.microsoftonline.com"
                "www.office.com"          # Office 365 入口，企业流量
                "www.apple.com"
                "www.icloud.com"
                "www.amazon.co.uk"        # 英国亚马逊（欧洲节点更近）
                "www.amazon.de"           # 德国亚马逊
                "s3.amazonaws.com"
                "www.cloudflare.com"
                "cdn.cloudflare.com"
                "www.github.com"
                "github.githubassets.com"
                "dl.google.com"
                "www.gstatic.com"         # Google 静态资源
                "www.netflix.com"
                "www.spotify.com"         # Spotify，欧洲本土流量大
                "open.spotify.com"
                "discord.com"
                "www.twitch.tv"
                "www.reddit.com"
            )
            ;;

        # ── 东亚 ──────────────────────────────────────────────
        JP|KR|TW)
            SNI_LIST=(
                "www.apple.com"
                "swdist.apple.com"
                "www.icloud.com"
                "www.microsoft.com"
                "login.microsoftonline.com"
                "www.office.com"
                "dl.google.com"
                "www.gstatic.com"
                "ajax.googleapis.com"
                "www.cloudflare.com"
                "cdn.cloudflare.com"
                "www.github.com"
                "github.githubassets.com"
                "www.amazon.co.jp"        # 日本亚马逊（JP节点近）
                "www.netflix.com"
                "www.twitch.tv"
                "discord.com"
                "www.dropbox.com"         # Dropbox
                "www.zoom.us"             # Zoom 视频会议
                "assets.zoom.us"
            )
            ;;

        # ── 东南亚 / 香港 ──────────────────────────────────────
        SG|HK|MY|TH|ID|PH|VN)
            SNI_LIST=(
                "www.apple.com"
                "www.icloud.com"
                "swdist.apple.com"
                "www.microsoft.com"
                "login.microsoftonline.com"
                "dl.google.com"
                "www.gstatic.com"
                "www.cloudflare.com"
                "cdn.cloudflare.com"
                "www.github.com"
                "github.githubassets.com"
                "www.amazon.com"
                "s3.amazonaws.com"
                "www.netflix.com"
                "www.zoom.us"
                "assets.zoom.us"
                "discord.com"
                "www.dropbox.com"
                "www.fastly.com"          # Fastly CDN
                "global.alicdn.com"       # 阿里云 CDN 全球节点
            )
            ;;

        # ── 大洋洲 ────────────────────────────────────────────
        AU|NZ)
            SNI_LIST=(
                "www.apple.com"
                "www.icloud.com"
                "www.microsoft.com"
                "www.office.com"
                "dl.google.com"
                "www.gstatic.com"
                "www.cloudflare.com"
                "www.amazon.com.au"       # 澳大利亚亚马逊
                "s3.amazonaws.com"
                "www.github.com"
                "github.githubassets.com"
                "www.netflix.com"
                "www.spotify.com"
                "discord.com"
                "www.twitch.tv"
                "www.dropbox.com"
                "www.zoom.us"
                "www.reddit.com"
                "cdn.cloudflare.com"
                "www.fastly.com"
            )
            ;;

        # ── 中东 / 非洲 ───────────────────────────────────────
        AE|SA|TR|ZA|EG|NG|KE)
            SNI_LIST=(
                "www.microsoft.com"
                "login.microsoftonline.com"
                "www.office.com"
                "www.apple.com"
                "www.icloud.com"
                "www.cloudflare.com"
                "cdn.cloudflare.com"
                "dl.google.com"
                "www.gstatic.com"
                "www.amazon.com"
                "s3.amazonaws.com"
                "www.github.com"
                "github.githubassets.com"
                "www.zoom.us"
                "www.netflix.com"
                "discord.com"
                "www.dropbox.com"
                "www.fastly.com"
                "www.reddit.com"
                "www.twitch.tv"
            )
            ;;

        # ── 默认通用（未识别地区）─────────────────────────────
        *)
            SNI_LIST=(
                "www.microsoft.com"
                "login.microsoftonline.com"
                "www.office.com"
                "www.apple.com"
                "www.icloud.com"
                "swdist.apple.com"
                "dl.google.com"
                "www.gstatic.com"
                "ajax.googleapis.com"
                "www.cloudflare.com"
                "cdn.cloudflare.com"
                "www.github.com"
                "github.githubassets.com"
                "api.github.com"
                "www.amazon.com"
                "s3.amazonaws.com"
                "www.netflix.com"
                "www.zoom.us"
                "discord.com"
                "www.dropbox.com"
            )
            ;;
    esac

    step "正在测试伪装网站连通性，请稍候..."
    local best_sni=""
    local best_time=9999

    for sni in "${SNI_LIST[@]}"; do
        local t
        t=$(curl -o /dev/null -s -w "%{time_connect}" \
            --max-time 5 --tlsv1.3 "https://${sni}" 2>/dev/null)
        # 将浮点秒转毫秒
        t_ms=$(echo "$t" | awk '{printf "%d", $1*1000}')
        if [[ $t_ms -gt 0 && $t_ms -lt $best_time ]]; then
            best_time=$t_ms
            best_sni="$sni"
        fi
        echo -e "   ${sni}  =>  ${t_ms}ms"
    done

    # 若全部失败则用默认值
    if [[ -z "$best_sni" ]]; then
        warn "无法测速，使用默认伪装网站: www.microsoft.com"
        best_sni="www.microsoft.com"
    else
        success "最优伪装网站: ${BOLD}${best_sni}${NC}  (${best_time}ms)"
    fi

    BEST_SNI="$best_sni"
}

# ============================================================
# 安装 / 更新 Xray-core
# ============================================================

install_xray() {
    step "安装/更新 Xray-core..."
    apt-get update -qq
    apt-get install -y -qq curl unzip

    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    if [[ $? -ne 0 ]]; then
        error "Xray 安装失败，请检查网络连接！"
        return 1
    fi
    success "Xray-core 安装/更新完成"
    xray version | head -1
}

# ============================================================
# 生成配置
# ============================================================

generate_config() {
    local port="$1"
    local uuid="$2"
    local private_key="$3"
    local sni="$4"

    mkdir -p /usr/local/etc/xray

    cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${port},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${sni}:443",
          "xver": 0,
          "serverNames": [
            "${sni}"
          ],
          "privateKey": "${private_key}",
          "shortIds": [""]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
}

# ============================================================
# 打印客户端配置信息
# ============================================================

print_client_info() {
    local port="$1"
    local uuid="$2"
    local public_key="$3"
    local sni="$4"
    local server_ip="$5"

    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║         Reality 节点配置信息                  ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}协议${NC}          : VLESS"
    echo -e "  ${CYAN}服务器地址${NC}    : ${BOLD}${server_ip}${NC}"
    echo -e "  ${CYAN}端口${NC}          : ${BOLD}${port}${NC}"
    echo -e "  ${CYAN}UUID${NC}          : ${BOLD}${uuid}${NC}"
    echo -e "  ${CYAN}Flow${NC}          : xtls-rprx-vision"
    echo -e "  ${CYAN}传输协议${NC}      : TCP"
    echo -e "  ${CYAN}TLS${NC}           : Reality"
    echo -e "  ${CYAN}SNI${NC}           : ${BOLD}${sni}${NC}"
    echo -e "  ${CYAN}PublicKey${NC}     : ${BOLD}${public_key}${NC}"
    echo -e "  ${CYAN}ShortId${NC}       : (留空)"
    echo -e "  ${CYAN}Fingerprint${NC}   : chrome"
    echo ""

    # 生成 VLESS 分享链接
    local share_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&type=tcp#Reality-Node"
    echo -e "${BOLD}${GREEN}分享链接:${NC}"
    echo -e "${YELLOW}${share_link}${NC}"
    echo ""

    # 保存到文件
    local save_path="/root/reality_client_info.txt"
    {
        echo "===== Reality 节点配置信息 ====="
        echo "服务器地址 : ${server_ip}"
        echo "端口       : ${port}"
        echo "UUID       : ${uuid}"
        echo "Flow       : xtls-rprx-vision"
        echo "传输协议   : TCP"
        echo "TLS        : Reality"
        echo "SNI        : ${sni}"
        echo "PublicKey  : ${public_key}"
        echo "ShortId    : (留空)"
        echo "Fingerprint: chrome"
        echo ""
        echo "分享链接:"
        echo "${share_link}"
    } > "$save_path"

    success "配置信息已保存至 ${BOLD}${save_path}${NC}"
}

# ============================================================
# 功能 1：一键搭建 Reality 节点
# ============================================================

setup_reality() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════ 一键搭建 Reality 节点 ═══════════${NC}"
    echo ""

    check_root

    # ── 1. 获取服务器公网 IP 并询问是否使用域名 ──
    step "获取服务器公网 IP..."
    SERVER_IP=$(curl -s --max-time 6 https://api4.ipify.org 2>/dev/null)
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(curl -s --max-time 6 https://ifconfig.me 2>/dev/null)
    fi
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(curl -s --max-time 6 https://ipinfo.io/ip 2>/dev/null)
    fi
    info "检测到服务器公网 IP: ${BOLD}${SERVER_IP}${NC}"

    # 询问是否使用域名作为连接地址
    echo ""
    echo -e "${CYAN}客户端连接地址选择：${NC}"
    echo -e "  ${BOLD}1.${NC} 使用公网 IP  (${SERVER_IP})"
    echo -e "  ${BOLD}2.${NC} 使用解析到此 VPS 的域名"
    read -rp "$(echo -e "${CYAN}请选择 [默认 1]:${NC} ")" ADDR_CHOICE
    ADDR_CHOICE="${ADDR_CHOICE:-1}"

    if [[ "$ADDR_CHOICE" == "2" ]]; then
        echo ""
        while true; do
            read -rp "$(echo -e "${CYAN}请输入域名（如 vps.example.com）:${NC} ")" INPUT_DOMAIN
            INPUT_DOMAIN=$(echo "$INPUT_DOMAIN" | tr -d '[:space:]' | sed 's|https*://||g' | sed 's|/.*||g')
            if [[ -z "$INPUT_DOMAIN" ]]; then
                warn "域名不能为空，请重新输入。"
                continue
            fi
            # 格式校验
            if ! echo "$INPUT_DOMAIN" | grep -qP '^[a-zA-Z0-9]([a-zA-Z0-9\-\.]*[a-zA-Z0-9])?$'; then
                warn "域名格式不正确，请重新输入。"
                continue
            fi
            # 解析域名验证是否指向本机
            step "正在解析域名 ${INPUT_DOMAIN}..."
            RESOLVED_IP=$(getent hosts "$INPUT_DOMAIN" 2>/dev/null | awk '{print $1}' | head -1)
            if [[ -z "$RESOLVED_IP" ]]; then
                RESOLVED_IP=$(dig +short "$INPUT_DOMAIN" 2>/dev/null | tail -1)
            fi
            if [[ -n "$RESOLVED_IP" ]]; then
                info "域名解析结果: ${RESOLVED_IP}"
                if [[ "$RESOLVED_IP" == "$SERVER_IP" ]]; then
                    success "域名已正确解析到本机 IP"
                else
                    warn "域名解析到 ${RESOLVED_IP}，与本机 IP ${SERVER_IP} 不一致"
                    read -rp "$(echo -e "${YELLOW}是否仍然使用此域名？(y/N):${NC} ")" FORCE_DOMAIN
                    if [[ "$FORCE_DOMAIN" != "y" && "$FORCE_DOMAIN" != "Y" ]]; then
                        continue
                    fi
                fi
            else
                warn "无法解析域名 ${INPUT_DOMAIN}"
                read -rp "$(echo -e "${YELLOW}是否仍然使用此域名？(y/N):${NC} ")" FORCE_DOMAIN
                if [[ "$FORCE_DOMAIN" != "y" && "$FORCE_DOMAIN" != "Y" ]]; then
                    continue
                fi
            fi
            SERVER_IP="$INPUT_DOMAIN"
            break
        done
    fi
    info "客户端连接地址: ${BOLD}${SERVER_IP}${NC}"

    # ── 2. 输入端口 ──
    echo ""
    read -rp "$(echo -e "${CYAN}请输入监听端口 [默认 443]:${NC} ")" INPUT_PORT
    INPUT_PORT="${INPUT_PORT:-443}"

    # 验证端口合法性
    if ! [[ "$INPUT_PORT" =~ ^[0-9]+$ ]] || [[ "$INPUT_PORT" -lt 1 || "$INPUT_PORT" -gt 65535 ]]; then
        error "端口号无效，请输入 1-65535 之间的数字！"
        press_any_key
        return 1
    fi
    info "使用端口: ${BOLD}${INPUT_PORT}${NC}"

    # ── 3. 自动优选伪装网站 ──
    echo ""
    get_best_sni

    # ── 4. 安装 Xray ──
    echo ""
    install_xray || { press_any_key; return 1; }

    # ── 5. 生成密钥对和 UUID ──
    echo ""
    step "生成密钥对和 UUID..."

    # Xray x25519 各版本输出格式:
    #   旧版 (<v26): "Private key: xxx"  "Public key: xxx"
    #   新版 (v26+): "PrivateKey: xxx"   "Password: xxx"   "Hash32: xxx"
    #   注意: v26+ 中公钥字段名改为 "Password"
    KEYPAIR_OUTPUT=$("$XRAY_BIN" x25519 2>&1)

    # 提取私钥: 匹配 PrivateKey 或 Private key
    PRIVATE_KEY=$(echo "$KEYPAIR_OUTPUT" | grep -iE "^PrivateKey:|^Private key:" | awk -F': ' '{print $2}' | tr -d '[:space:]')

    # 提取公钥: v26+ 字段名为 Password，旧版为 Public key
    PUBLIC_KEY=$(echo "$KEYPAIR_OUTPUT" | grep -iE "^Password:|^Public key:" | awk -F': ' '{print $2}' | tr -d '[:space:]')

    # 兜底: 若仍为空则按行序取（第1行私钥，第2行公钥）
    if [[ -z "$PRIVATE_KEY" ]]; then
        PRIVATE_KEY=$(echo "$KEYPAIR_OUTPUT" | sed -n '1p' | awk -F': ' '{print $2}' | tr -d '[:space:]')
    fi
    if [[ -z "$PUBLIC_KEY" ]]; then
        PUBLIC_KEY=$(echo "$KEYPAIR_OUTPUT"  | sed -n '2p' | awk -F': ' '{print $2}' | tr -d '[:space:]')
    fi

    # 校验非空，失败时打印原始输出辅助排查
    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        error "密钥对生成失败！原始输出如下："
        echo "$KEYPAIR_OUTPUT"
        error "请手动执行 \"${XRAY_BIN} x25519\" 确认输出格式后反馈。"
        press_any_key
        return 1
    fi

    UUID=$("$XRAY_BIN" uuid 2>&1 | tr -d '[:space:]')
    if [[ -z "$UUID" ]]; then
        error "UUID 生成失败！"
        press_any_key
        return 1
    fi

    success "UUID       : ${UUID}"
    success "私钥       : ${PRIVATE_KEY}"
    success "公钥       : ${PUBLIC_KEY}"

    # ── 6. 写入配置 ──
    echo ""
    step "生成 Xray 配置文件..."
    generate_config "$INPUT_PORT" "$UUID" "$PRIVATE_KEY" "$BEST_SNI"
    success "配置文件已写入 ${XRAY_CONFIG}"

    # ── 7. 启动服务 ──
    echo ""
    step "启动 Xray 服务..."
    systemctl enable xray --quiet
    systemctl restart xray

    sleep 2
    if systemctl is-active --quiet xray; then
        success "Xray 服务运行正常！"
    else
        error "Xray 服务启动失败，查看日志："
        journalctl -u xray -n 20 --no-pager
        press_any_key
        return 1
    fi

    # ── 8. 打印客户端信息 ──
    print_client_info "$INPUT_PORT" "$UUID" "$PUBLIC_KEY" "$BEST_SNI" "$SERVER_IP"

    press_any_key
}

# ============================================================
# 功能 2：更新 Xray-core
# ============================================================

update_xray() {
    echo ""
    echo -e "${BOLD}${GREEN}═══════════ 更新 Xray-core ═══════════${NC}"
    echo ""
    check_root

    if [[ ! -f "$XRAY_BIN" ]]; then
        warn "Xray 未安装，将直接安装最新版..."
    else
        local current_ver
        current_ver=$("$XRAY_BIN" version 2>/dev/null | head -1)
        info "当前版本: ${current_ver}"
    fi

    step "正在更新 Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    if [[ $? -eq 0 ]]; then
        systemctl restart xray 2>/dev/null
        local new_ver
        new_ver=$("$XRAY_BIN" version 2>/dev/null | head -1)
        success "更新完成！当前版本: ${new_ver}"
    else
        error "更新失败，请检查网络连接！"
    fi

    press_any_key
}

# ============================================================
# 功能 3：移除 Reality 节点
# ============================================================

remove_reality() {
    echo ""
    echo -e "${BOLD}${RED}═══════════ 移除 Reality 节点 ═══════════${NC}"
    echo ""
    check_root

    read -rp "$(echo -e "${RED}确认移除 Reality 节点及 Xray 服务？(y/N):${NC} ")" CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        info "已取消操作。"
        press_any_key
        return
    fi

    step "停止并禁用 Xray 服务..."
    systemctl stop xray  2>/dev/null
    systemctl disable xray 2>/dev/null

    step "卸载 Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove 2>/dev/null

    step "清理配置文件..."
    rm -rf /usr/local/etc/xray
    rm -f  /root/reality_client_info.txt

    success "Reality 节点已完全移除！"

    press_any_key
}

# ============================================================
# 功能 4：删除脚本自身
# ============================================================

delete_script() {
    echo ""
    echo -e "${BOLD}${RED}═══════════ 删除脚本 ═══════════${NC}"
    echo ""

    SCRIPT_PATH=$(realpath "$0" 2>/dev/null || echo "$0")
    info "脚本路径: ${SCRIPT_PATH}"
    echo ""
    read -rp "$(echo -e "${RED}确认删除此脚本文件？(y/N):${NC} ")" CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        info "已取消操作。"
        press_any_key
        return
    fi

    rm -f "$SCRIPT_PATH"
    success "脚本已删除：${SCRIPT_PATH}"
    echo ""
    info "退出脚本..."
    sleep 1
    exit 0
}

# ============================================================
# 主菜单
# ============================================================

show_menu() {
    clear
    echo ""
    echo -e "${BOLD}${BLUE}  ╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}  ║     VLESS + Reality  节点管理脚本        ║${NC}"
    echo -e "${BOLD}${BLUE}  ║        Debian 12 / Ubuntu 22.04+         ║${NC}"
    echo -e "${BOLD}${BLUE}  ╚══════════════════════════════════════════╝${NC}"
    echo ""

    # 显示 Xray 运行状态
    if systemctl is-active --quiet xray 2>/dev/null; then
        echo -e "  Xray 状态: ${GREEN}● 运行中${NC}"
    elif [[ -f "$XRAY_BIN" ]]; then
        echo -e "  Xray 状态: ${RED}● 已停止${NC}"
    else
        echo -e "  Xray 状态: ${YELLOW}● 未安装${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}1.${NC} 一键搭建 Reality 节点"
    echo -e "  ${BOLD}2.${NC} 更新 Xray-core"
    echo -e "  ${BOLD}3.${NC} 移除 Reality 节点"
    echo -e "  ${BOLD}4.${NC} 退出脚本"
    echo -e "  ${BOLD}5.${NC} 删除脚本"
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
}

main() {
    check_root

    while true; do
        show_menu
        read -rp "$(echo -e "${CYAN}请输入选项 [1-5]:${NC} ")" CHOICE
        case "$CHOICE" in
            1) setup_reality ;;
            2) update_xray   ;;
            3) remove_reality ;;
            4)
                echo ""
                info "已退出脚本，再见！"
                echo ""
                exit 0
                ;;
            5) delete_script ;;
            *)
                warn "无效选项，请输入 1-5"
                sleep 1
                ;;
        esac
    done
}

main
