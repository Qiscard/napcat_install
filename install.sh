#!/usr/bin/env bash
# NapCat 精简安装脚本 (Shell Rootless)
# 基于 NapCat-Installer，移除 Docker/TUI/多代理测速等功能

set -euo pipefail

MAGENTA='\033[0;1;35;95m'
RED='\033[0;1;31;91m'
YELLOW='\033[0;1;33;93m'
GREEN='\033[0;1;32;92m'
CYAN='\033[0;1;36;96m'
BLUE='\033[0;1;34;94m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${TMPDIR:-/tmp}/napcat_install_$$"
INSTALL_BASE_DIR="${HOME}/Napcat"
QQ_BASE_PATH="${INSTALL_BASE_DIR}/opt/QQ"
TARGET_FOLDER="${QQ_BASE_PATH}/resources/app/app_launcher"
QQ_EXECUTABLE="${QQ_BASE_PATH}/qq"
QQ_PACKAGE_JSON_PATH="${QQ_BASE_PATH}/resources/app/package.json"
NAPCAT_DIR="${TARGET_FOLDER}/napcat"

PROXY_PREFIX="https://ghproxy.net/"
USE_PROXY="n"
DOWNLOAD_DIR=""
SYSTEM_ARCH=""
DISTRO_ID=""
PACKAGE_MANAGER=""
PACKAGE_FORMAT=""
SELECTED_QQ_VERSION=""
SELECTED_QQ_URL=""
SELECTED_QQ_SHA256=""
SELECTED_QQ_FILENAME=""
SELECTED_QQ_MD5=""
FORCE_OVERWRITE="n"
NAPCAT_CMD_PATH=""

QQ_VERSIONS_FILE="${SCRIPT_DIR}/data/qq_versions.json"
# 可通过环境变量覆盖: NAPCAT_INSTALL_REPO=owner/name
NAPCAT_INSTALL_REPO="${NAPCAT_INSTALL_REPO:-Qiscard/napcat_install}"
QQ_VERSIONS_REMOTE_CANDIDATES=(
    "https://raw.githubusercontent.com/${NAPCAT_INSTALL_REPO}/main/data/qq_versions.json"
    "https://cdn.jsdelivr.net/gh/${NAPCAT_INSTALL_REPO}@main/data/qq_versions.json"
)

cleanup() {
    if [[ -n "${WORKDIR:-}" && -d "${WORKDIR}" ]]; then
        rm -rf "${WORKDIR}"
    fi
}
trap cleanup EXIT

log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')]: $1"
    case "$1" in
        *"失败"*|*"错误"*|*"无法"*)
            echo -e "${RED}${message}${NC}" >&2 ;;
        *"成功"*)
            echo -e "${GREEN}${message}${NC}" >&2 ;;
        *"忽略"*|*"跳过"*|*"警告"*|*"默认"*)
            echo -e "${YELLOW}${message}${NC}" >&2 ;;
        *)
            echo -e "${BLUE}${message}${NC}" >&2 ;;
    esac
}

logo() {
    echo -e "${MAGENTA}NapCat Installer (精简版)${NC}"
    echo -e "${CYAN}安装目录: ${INSTALL_BASE_DIR}${NC}"
    echo ""
}

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

prompt_timeout() {
    # usage: prompt_timeout <seconds> <prompt> <default>
    # 仅将选择结果输出到 stdout；提示与日志走 stderr
    local seconds="$1"
    local prompt="$2"
    local default="$3"
    local input=""
    if read -t "${seconds}" -r -p "${prompt}" input </dev/tty; then
        echo "" >&2
        if [[ -z "${input}" ]]; then
            printf '%s' "${default}"
        else
            printf '%s' "${input}"
        fi
    else
        echo "" >&2
        log "超时未输入, 使用默认: ${default}"
        printf '%s' "${default}"
    fi
}

detect_arch() {
    local raw
    raw="$(uname -m)"
    case "${raw}" in
        x86_64|amd64) SYSTEM_ARCH="amd64" ;;
        aarch64|arm64) SYSTEM_ARCH="arm64" ;;
        loongarch64) SYSTEM_ARCH="loongarch64" ;;
        mips64el|mips64) SYSTEM_ARCH="mips64el" ;;
        *)
            log "错误: 不支持的系统架构: ${raw}"
            exit 1
            ;;
    esac
    log "检测到 CPU 架构: ${raw} -> ${SYSTEM_ARCH}"
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        log "检测到系统: ${NAME:-$DISTRO_ID} (${VERSION_ID:-unknown})"
    else
        DISTRO_ID="unknown"
        log "警告: 无法读取 /etc/os-release"
    fi

    if need_cmd apt-get || need_cmd dpkg; then
        PACKAGE_MANAGER="apt"
        PACKAGE_FORMAT="deb"
    elif need_cmd dnf || need_cmd yum || need_cmd rpm; then
        PACKAGE_MANAGER="dnf"
        PACKAGE_FORMAT="rpm"
    else
        PACKAGE_MANAGER="unknown"
        PACKAGE_FORMAT="deb"
        log "警告: 未能识别包管理器, 默认按 deb 处理"
    fi
    log "包格式默认: ${PACKAGE_FORMAT} (包管理: ${PACKAGE_MANAGER})"
}

choose_package_format() {
    echo ""
    log "系统/包格式选择 (10 秒后默认: 识别结果 ${PACKAGE_FORMAT})"
    echo -e "  ${GREEN}1${NC}) 自动 (${PACKAGE_FORMAT}) [默认]"
    echo -e "  ${CYAN}2${NC}) Ubuntu/Debian (.deb)"
    echo -e "  ${CYAN}3${NC}) Fedora/RHEL/CentOS (.rpm)"
    local choice
    choice="$(prompt_timeout 10 "请输入序号 [1]: " "1")"
    case "${choice}" in
        2|deb|DEB|ubuntu|debian|Ubuntu|Debian)
            PACKAGE_FORMAT="deb"
            PACKAGE_MANAGER="apt"
            ;;
        3|rpm|RPM|fedora|centos|rhel|Fedora|CentOS)
            PACKAGE_FORMAT="rpm"
            PACKAGE_MANAGER="dnf"
            ;;
        1|""|*)
            log "使用识别结果: ${PACKAGE_FORMAT}"
            ;;
    esac
    log "最终包格式: ${PACKAGE_FORMAT}"
}

choose_proxy() {
    echo ""
    log "下载方式选择 (10 秒后默认: 直连)"
    echo -e "  ${GREEN}1${NC}) 直连下载 [默认]"
    echo -e "  ${CYAN}2${NC}) 代理下载 (${PROXY_PREFIX})"
    local choice
    choice="$(prompt_timeout 10 "请输入序号 [1]: " "1")"
    case "${choice}" in
        2|proxy|PROXY|y|Y)
            USE_PROXY="y"
            log "已选择代理下载: ${PROXY_PREFIX}"
            ;;
        *)
            USE_PROXY="n"
            log "已选择直连下载"
            ;;
    esac
}

proxy_url() {
    local url="$1"
    if [[ "${USE_PROXY}" == "y" ]]; then
        # 仅对 GitHub 相关链接套代理
        if [[ "${url}" == https://github.com/* || "${url}" == https://raw.githubusercontent.com/* || "${url}" == https://objects.githubusercontent.com/* || "${url}" == https://codeload.github.com/* ]]; then
            echo "${PROXY_PREFIX}${url}"
            return
        fi
    fi
    echo "${url}"
}

download_file() {
    local url="$1"
    local dest="$2"
    local final_url
    final_url="$(proxy_url "${url}")"
    log "下载: ${url}"
    if [[ "${final_url}" != "${url}" ]]; then
        log "实际请求: ${final_url}"
    fi
    log "保存到: ${dest}"
    if ! curl -k -L --connect-timeout 20 --retry 3 --retry-delay 2 -# "${final_url}" -o "${dest}"; then
        log "错误: 下载失败: ${url}"
        return 1
    fi
    if [[ ! -s "${dest}" ]]; then
        log "错误: 下载文件为空: ${dest}"
        return 1
    fi
    log "下载成功: ${dest} ($(du -h "${dest}" | awk '{print $1}'))"
}

# 预检下载链接是否可达 (拉前 2KB)
url_reachable() {
    local url="$1"
    local final_url code size
    final_url="$(proxy_url "${url}")"
    read -r code size < <(curl -k -s -o /dev/null -w "%{http_code} %{size_download}" -L --connect-timeout 12 --max-time 25 -A "Mozilla/5.0" -r 0-2047 "${final_url}" || echo "000 0")
    if [[ "${code}" =~ ^[0-9]+$ && "${code}" -lt 400 && "${size}" -gt 0 ]]; then
        return 0
    fi
    log "链接不可用: HTTP ${code}, bytes=${size}, url=${url}"
    return 1
}

ensure_deps() {
    local missing=()
    for c in curl unzip jq; do
        need_cmd "$c" || missing+=("$c")
    done
    if [[ "${PACKAGE_FORMAT}" == "deb" ]]; then
        need_cmd dpkg || missing+=("dpkg")
    else
        need_cmd rpm2cpio || missing+=("rpm2cpio")
        need_cmd cpio || missing+=("cpio")
    fi
    need_cmd xvfb-run || true
    need_cmd screen || true

    if [[ ${#missing[@]} -eq 0 ]]; then
        log "依赖检查通过"
        return 0
    fi

    log "缺少依赖: ${missing[*]}"
    if [[ "$(id -u)" -eq 0 ]]; then
        SUDO=""
    elif need_cmd sudo; then
        SUDO="sudo"
    else
        log "错误: 缺少 sudo, 请手动安装: ${missing[*]}"
        exit 1
    fi

    if [[ "${PACKAGE_MANAGER}" == "apt" ]] || need_cmd apt-get; then
        ${SUDO} apt-get update -y -qq
        ${SUDO} apt-get install -y -qq curl unzip jq dpkg xvfb xauth screen dialog screen dialog flatpak 2>/dev/null || \
        ${SUDO} apt-get install -y -qq curl unzip jq dpkg xvfb xauth screen dialog screen dialog
    elif need_cmd dnf; then
        ${SUDO} dnf install -y curl unzip jq cpio rpm xvfb-run xorg-x11-server-Xvfb screen || \
        ${SUDO} dnf install -y curl unzip jq cpio rpm screen || \
        ${SUDO} dnf install -y curl unzip jq cpio rpm
    elif need_cmd yum; then
        ${SUDO} yum install -y curl unzip jq cpio rpm screen || ${SUDO} yum install -y curl unzip jq cpio rpm
    else
        log "错误: 无法自动安装依赖, 请手动安装: ${missing[*]}"
        exit 1
    fi
    log "依赖安装完成"
}

load_qq_versions() {
    mkdir -p "${WORKDIR}"
    local local_copy="${WORKDIR}/qq_versions.json"

    if [[ -f "${QQ_VERSIONS_FILE}" ]]; then
        cp -f "${QQ_VERSIONS_FILE}" "${local_copy}"
        log "已加载本地版本列表: ${QQ_VERSIONS_FILE}"
    else
        log "本地版本列表不存在, 尝试在线获取..."
        local ok=0
        for remote in "${QQ_VERSIONS_REMOTE_CANDIDATES[@]}"; do
            if download_file "${remote}" "${local_copy}"; then
                ok=1
                break
            fi
        done
        if [[ ${ok} -ne 1 ]]; then
            log "错误: 无法获取 QQ 版本列表"
            exit 1
        fi
    fi

    if ! jq -e '.packages | type=="array"' "${local_copy}" >/dev/null 2>&1; then
        log "错误: 版本列表格式无效"
        exit 1
    fi
    QQ_VERSIONS_FILE="${local_copy}"
    log "版本列表同步时间: $(jq -r '.synced_at // "unknown"' "${QQ_VERSIONS_FILE}")"
    log "版本条目数: $(jq -r '.count // (.packages|length)' "${QQ_VERSIONS_FILE}")"
}

choose_qq_version() {
    load_qq_versions

    # 使用 JSON 数组，避免 TSV 空字段错位；按版本聚合后取最新 15 个
    local list_file="${WORKDIR}/qq_choices.json"
    jq --arg arch "${SYSTEM_ARCH}" --arg fmt "${PACKAGE_FORMAT}" '
        [.packages[]
         | select(.arch==$arch and .format==$fmt)
         | select(.available != false)
        ]
        | group_by(.version)
        | map(sort_by(.update_time) | reverse | .[0])
        | sort_by(.update_time) | reverse
        | .[0:15]
    ' "${QQ_VERSIONS_FILE}" > "${list_file}"

    local count
    count="$(jq 'length' "${list_file}")"
    if [[ "${count}" -eq 0 ]]; then
        log "错误: 在版本列表中未找到 ${SYSTEM_ARCH}/${PACKAGE_FORMAT} 的 QQ 包"
        log "提示: 可尝试切换系统架构/包格式选项"
        exit 1
    fi

    echo ""
    log "可选 QQ 版本 (显示最新 ${count} 个, 架构=${SYSTEM_ARCH}, 格式=${PACKAGE_FORMAT})"
    printf "%-4s %-12s %-12s %-10s %-6s %s\n" "序号" "版本" "更新日期" "架构" "格式" "文件名"
    echo "----------------------------------------------------------------"
    local i ver date arch fmt fname
    for ((i=0; i<count; i++)); do
        ver="$(jq -r --argjson i "$i" '.[$i].version' "${list_file}")"
        date="$(jq -r --argjson i "$i" '.[$i].update_date // .[$i].update_time[0:10]' "${list_file}")"
        arch="$(jq -r --argjson i "$i" '.[$i].arch' "${list_file}")"
        fmt="$(jq -r --argjson i "$i" '.[$i].format' "${list_file}")"
        fname="$(jq -r --argjson i "$i" '.[$i].filename' "${list_file}")"
        printf "%-4s %-12s %-12s %-10s %-6s %s\n" "$((i+1))" "${ver}" "${date}" "${arch}" "${fmt}" "${fname}"
    done
    echo "----------------------------------------------------------------"
    echo -e "直接回车 = 最新版 (序号 1); 或输入序号 1-${count}"

    local choice
    choice="$(prompt_timeout 10 "请选择 QQ 版本序号 [1]: " "1")"
    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || [[ "${choice}" -lt 1 || "${choice}" -gt ${count} ]]; then
        log "警告: 无效序号 '${choice}', 使用默认最新版"
        choice="1"
    fi

    local idx=$((choice-1))
    SELECTED_QQ_VERSION="$(jq -r --argjson i "$idx" '.[$i].version' "${list_file}")"
    SELECTED_QQ_URL="$(jq -r --argjson i "$idx" '.[$i].url' "${list_file}")"
    SELECTED_QQ_SHA256="$(jq -r --argjson i "$idx" '.[$i].sha256 // empty' "${list_file}")"
    SELECTED_QQ_MD5="$(jq -r --argjson i "$idx" '.[$i].md5 // empty' "${list_file}")"
    SELECTED_QQ_FILENAME="$(jq -r --argjson i "$idx" '.[$i].filename' "${list_file}")"
    date="$(jq -r --argjson i "$idx" '.[$i].update_date // .[$i].update_time[0:10]' "${list_file}")"
    arch="$(jq -r --argjson i "$idx" '.[$i].arch' "${list_file}")"
    fmt="$(jq -r --argjson i "$idx" '.[$i].format' "${list_file}")"

    log "已选择 QQ: 版本=${SELECTED_QQ_VERSION}, 架构=${arch}, 格式=${fmt}"
    log "更新时间: ${date}"
    log "下载链接: ${SELECTED_QQ_URL}"
    [[ -n "${SELECTED_QQ_SHA256}" ]] && log "SHA256: ${SELECTED_QQ_SHA256}"
    [[ -n "${SELECTED_QQ_MD5}" ]] && log "MD5: ${SELECTED_QQ_MD5}"

    # 安装前校验链接；失效则在同版本/架构/格式中寻找可用替代
    resolve_qq_download_url "${SELECTED_QQ_VERSION}" "${arch}" "${fmt}"

    log "最终下载链接: ${SELECTED_QQ_URL}"
    log "安装位置: ${INSTALL_BASE_DIR}"
    log "QQ 路径: ${QQ_BASE_PATH}"
    log "NapCat 路径: ${NAPCAT_DIR}"
}

# 校验并在失效时回退到同版本可用源 / 次新版本
resolve_qq_download_url() {
    local want_ver="$1"
    local want_arch="$2"
    local want_fmt="$3"

    if url_reachable "${SELECTED_QQ_URL}"; then
        log "下载链接预检通过"
        return 0
    fi

    log "警告: 所选链接失效, 尝试寻找替代源..."
    local alt_file="${WORKDIR}/qq_alt.json"
    jq --arg ver "${want_ver}" --arg arch "${want_arch}" --arg fmt "${want_fmt}" '
        [.packages[]
         | select(.arch==$arch and .format==$fmt)
         | select((.available != false))
        ]
        | sort_by(.update_time) | reverse
    ' "${QQ_VERSIONS_FILE}" > "${alt_file}"

    local n i ver url sha md5 fname date
    n="$(jq 'length' "${alt_file}")"
    for ((i=0; i<n; i++)); do
        ver="$(jq -r --argjson i "$i" '.[$i].version' "${alt_file}")"
        url="$(jq -r --argjson i "$i" '.[$i].url' "${alt_file}")"
        # 先同版本，再其他较新版本
        if [[ "${ver}" != "${want_ver}" && ${i} -eq 0 ]]; then
            :
        fi
        log "尝试替代: version=${ver} url=${url}"
        if url_reachable "${url}"; then
            SELECTED_QQ_VERSION="${ver}"
            SELECTED_QQ_URL="${url}"
            SELECTED_QQ_SHA256="$(jq -r --argjson i "$i" '.[$i].sha256 // empty' "${alt_file}")"
            SELECTED_QQ_MD5="$(jq -r --argjson i "$i" '.[$i].md5 // empty' "${alt_file}")"
            SELECTED_QQ_FILENAME="$(jq -r --argjson i "$i" '.[$i].filename' "${alt_file}")"
            date="$(jq -r --argjson i "$i" '.[$i].update_date // .[$i].update_time[0:10]' "${alt_file}")"
            log "已切换到可用源: 版本=${SELECTED_QQ_VERSION}, 更新=${date}"
            log "文件名: ${SELECTED_QQ_FILENAME}"
            return 0
        fi
    done

    log "错误: 未找到可用的 QQ 下载链接 (${want_arch}/${want_fmt})"
    log "可稍后重试, 或手动更新 data/qq_versions.json"
    exit 1
}


check_existing_install() {
    if [[ ! -d "${INSTALL_BASE_DIR}" && ! -d "${NAPCAT_DIR}" ]]; then
        return 0
    fi

    echo ""
    log "检测到已有安装目录"
    [[ -d "${INSTALL_BASE_DIR}" ]] && log "  存在: ${INSTALL_BASE_DIR}"
    [[ -d "${NAPCAT_DIR}" ]] && log "  存在: ${NAPCAT_DIR}"
    if [[ -f "${QQ_PACKAGE_JSON_PATH}" ]] && need_cmd jq; then
        local cur
        cur="$(jq -r '.version // empty' "${QQ_PACKAGE_JSON_PATH}" 2>/dev/null || true)"
        [[ -n "${cur}" ]] && log "  当前 QQ 版本: ${cur}"
    fi

    echo -e "  ${YELLOW}1${NC}) 覆盖安装 (删除后重装) [默认]"
    echo -e "  ${CYAN}2${NC}) 退出"
    local choice
    choice="$(prompt_timeout 10 "请选择 [1]: " "1")"
    case "${choice}" in
        2|q|Q|n|N|exit)
            log "用户选择退出"
            exit 0
            ;;
        *)
            FORCE_OVERWRITE="y"
            log "将覆盖安装"
            ;;
    esac
}

install_linuxqq() {
    mkdir -p "${DOWNLOAD_DIR}"
    local pkg_path="${DOWNLOAD_DIR}/${SELECTED_QQ_FILENAME}"

    log "开始下载 LinuxQQ..."
    log "目标安装目录: ${INSTALL_BASE_DIR}"
    download_file "${SELECTED_QQ_URL}" "${pkg_path}"

    if [[ -n "${SELECTED_QQ_SHA256}" ]] && need_cmd sha256sum; then
        local actual
        actual="$(sha256sum "${pkg_path}" | awk '{print $1}')"
        if [[ "${actual}" != "${SELECTED_QQ_SHA256}" ]]; then
            log "错误: SHA256 校验失败"
            log "期望: ${SELECTED_QQ_SHA256}"
            log "实际: ${actual}"
            exit 1
        fi
        log "SHA256 校验成功"
    elif [[ -n "${SELECTED_QQ_MD5}" ]] && need_cmd md5sum; then
        local actual
        actual="$(md5sum "${pkg_path}" | awk '{print $1}')"
        if [[ "${actual}" != "${SELECTED_QQ_MD5}" ]]; then
            log "错误: MD5 校验失败"
            log "期望: ${SELECTED_QQ_MD5}"
            log "实际: ${actual}"
            exit 1
        fi
        log "MD5 校验成功"
    else
        log "警告: 无校验和或缺少校验工具, 跳过完整性校验"
    fi

    if [[ "${FORCE_OVERWRITE}" == "y" && -d "${INSTALL_BASE_DIR}" ]]; then
        local backup_cfg=""
        if [[ -d "${NAPCAT_DIR}/config" ]]; then
            backup_cfg="${WORKDIR}/napcat_config_backup"
            mkdir -p "${backup_cfg}"
            cp -a "${NAPCAT_DIR}/config/." "${backup_cfg}/" || true
            log "已备份 NapCat 配置到: ${backup_cfg}"
        fi
        log "删除旧安装: ${INSTALL_BASE_DIR}"
        rm -rf "${INSTALL_BASE_DIR}"
        # restore later after napcat install via env
        if [[ -n "${backup_cfg}" && -d "${backup_cfg}" ]]; then
            export NAPCAT_CONFIG_BACKUP="${backup_cfg}"
        fi
    fi

    mkdir -p "${INSTALL_BASE_DIR}"
    log "解压 QQ 到: ${INSTALL_BASE_DIR}"
    if [[ "${PACKAGE_FORMAT}" == "deb" ]]; then
        dpkg -x "${pkg_path}" "${INSTALL_BASE_DIR}"
    else
        rpm2cpio "${pkg_path}" | (cd "${INSTALL_BASE_DIR}" && cpio -idm)
    fi

    if [[ ! -x "${QQ_EXECUTABLE}" && -f "${QQ_EXECUTABLE}" ]]; then
        chmod +x "${QQ_EXECUTABLE}" || true
    fi
    if [[ ! -f "${QQ_PACKAGE_JSON_PATH}" ]]; then
        log "错误: QQ 解压后未找到 ${QQ_PACKAGE_JSON_PATH}"
        exit 1
    fi
    log "LinuxQQ 安装成功"
    log "QQ 可执行文件: ${QQ_EXECUTABLE}"
}

download_and_install_napcat() {
    local zip_path="${DOWNLOAD_DIR}/NapCat.Shell.zip"
    local napcat_url="https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"

    log "开始下载 NapCat..."
    download_file "${napcat_url}" "${zip_path}"

    local extract_dir="${WORKDIR}/NapCatExtract"
    rm -rf "${extract_dir}"
    mkdir -p "${extract_dir}"
    log "解压 NapCat 到: ${extract_dir}"
    unzip -q -o "${zip_path}" -d "${extract_dir}"

    # 兼容 zip 内是否多一层目录
    local src_dir="${extract_dir}"
    if [[ -d "${extract_dir}/NapCat" ]]; then
        src_dir="${extract_dir}/NapCat"
    elif [[ -f "${extract_dir}/napcat.mjs" ]]; then
        src_dir="${extract_dir}"
    else
        # 取第一个包含 napcat.mjs 的目录
        local found
        found="$(find "${extract_dir}" -type f -name 'napcat.mjs' | head -n1 || true)"
        if [[ -n "${found}" ]]; then
            src_dir="$(dirname "${found}")"
        fi
    fi

    mkdir -p "${NAPCAT_DIR}"
    log "安装 NapCat 到: ${NAPCAT_DIR}"
    cp -a "${src_dir}/." "${NAPCAT_DIR}/"
    chmod -R +x "${NAPCAT_DIR}" || true

    if [[ -n "${NAPCAT_CONFIG_BACKUP:-}" && -d "${NAPCAT_CONFIG_BACKUP}" ]]; then
        mkdir -p "${NAPCAT_DIR}/config"
        cp -a "${NAPCAT_CONFIG_BACKUP}/." "${NAPCAT_DIR}/config/" || true
        log "已恢复 NapCat 配置"
    fi

    local loader="${QQ_BASE_PATH}/resources/app/loadNapCat.js"
    log "写入启动注入: ${loader}"
    echo "(async () => {await import('file:///${NAPCAT_DIR}/napcat.mjs');})();" > "${loader}"

    log "修改 QQ package.json main 入口"
    local tmp_pkg="${WORKDIR}/package.json.tmp"
    jq '.main = "./loadNapCat.js"' "${QQ_PACKAGE_JSON_PATH}" > "${tmp_pkg}"
    mv "${tmp_pkg}" "${QQ_PACKAGE_JSON_PATH}"
    log "NapCat 安装成功"
}

install_napcat_tui_cli() {
    # 安装官方 NapCat-TUI-CLI (dialog 终端 UI)
    # 来源: https://github.com/NapNeko/NapCat-TUI-CLI
    echo ""
    log "是否安装官方 NapCat TUI-CLI? (输入 napcat 进入终端管理界面)"
    log "默认安装 [Y], 10 秒后自动确认"
    local choice
    choice="$(prompt_timeout 10 "安装 TUI-CLI? [Y/n]: " "Y")"
    if [[ "${choice}" =~ ^[Nn]$ ]]; then
        log "已跳过 TUI-CLI 安装, 将创建简易启动命令"
        install_napcat_simple_command
        return 0
    fi

    # 依赖: dialog (TUI 必需), ffmpeg (推荐)
    local missing=()
    need_cmd dialog || missing+=("dialog")
    need_cmd ffmpeg || missing+=("ffmpeg")
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "安装 TUI 依赖: ${missing[*]}"
        if [[ "$(id -u)" -eq 0 ]]; then
            SUDO=""
        elif need_cmd sudo; then
            SUDO="sudo"
        else
            log "警告: 无法自动安装依赖 ${missing[*]}, 请手动安装后重试 TUI"
            install_napcat_simple_command
            return 1
        fi
        if need_cmd apt-get; then
            ${SUDO} apt-get update -y -qq || true
            ${SUDO} apt-get install -y -qq "${missing[@]}" || true
        elif need_cmd dnf; then
            ${SUDO} dnf install -y "${missing[@]}" || true
        elif need_cmd yum; then
            ${SUDO} yum install -y "${missing[@]}" || true
        fi
    fi
    if ! need_cmd dialog; then
        log "错误: dialog 未安装, 无法使用官方 TUI, 回退简易命令"
        install_napcat_simple_command
        return 1
    fi

    local target_dir="/usr/local/bin"
    local use_sudo_install="n"
    if [[ -w "${target_dir}" ]] || [[ "$(id -u)" -eq 0 ]]; then
        use_sudo_install="n"
    elif need_cmd sudo; then
        use_sudo_install="y"
    else
        target_dir="${HOME}/.local/bin"
        mkdir -p "${target_dir}"
        log "无 /usr/local/bin 写权限, 安装到: ${target_dir}"
    fi

    local base_url="https://raw.githubusercontent.com/NapNeko/NapCat-TUI-CLI/main/script/tui-cli"
    local files=("napcat" "_napcat_Boot" "_napcat_Config" "_napcat_old")
    local failed="n"
    local tmp_dir="${WORKDIR}/tui-cli"
    mkdir -p "${tmp_dir}"

    log "开始安装官方 NapCat TUI-CLI 组件到 ${target_dir}"
    local f url dest tmpf
    for f in "${files[@]}"; do
        url="${base_url}/${f}"
        tmpf="${tmp_dir}/${f}"
        dest="${target_dir}/${f}"
        log "下载组件: ${f}"
        if ! download_file "${url}" "${tmpf}"; then
            log "错误: 下载失败 ${f}"
            failed="y"
            break
        fi
        # 校验 shebang
        if ! head -n1 "${tmpf}" | grep -q '^#!'; then
            log "错误: ${f} 内容无效 (非脚本)"
            head -n5 "${tmpf}" || true
            failed="y"
            break
        fi
        chmod 755 "${tmpf}"
        if [[ "${use_sudo_install}" == "y" ]]; then
            if ! sudo mv "${tmpf}" "${dest}"; then
                log "错误: 无法写入 ${dest}"
                failed="y"
                break
            fi
            sudo chmod 755 "${dest}" || true
        else
            if ! mv "${tmpf}" "${dest}"; then
                log "错误: 无法写入 ${dest}"
                failed="y"
                break
            fi
            chmod 755 "${dest}" || true
        fi
        log "已安装: ${dest}"
    done

    if [[ "${failed}" == "y" ]]; then
        log "警告: 官方 TUI-CLI 安装失败, 回退简易启动命令"
        install_napcat_simple_command
        return 1
    fi

    NAPCAT_CMD_PATH="${target_dir}/napcat"
    log "官方 TUI-CLI 安装成功: ${NAPCAT_CMD_PATH}"
    if [[ "${target_dir}" == "${HOME}/.local/bin" ]]; then
        if ! echo ":${PATH}:" | grep -q ":${target_dir}:"; then
            log "警告: ${target_dir} 不在 PATH 中"
            log "可执行: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
        fi
    fi
    log "使用方式: 直接运行  napcat  进入终端管理界面"
    log "带参数时走旧版 CLI, 例如: napcat help"
}

install_napcat_simple_command() {
    # 简易启动包装 (TUI 不可用时的回退)
    local cmd_path=""
    local user_bin="${HOME}/.local/bin"
    mkdir -p "${user_bin}"
    if [[ -w /usr/local/bin ]] || [[ "$(id -u)" -eq 0 ]]; then
        cmd_path="/usr/local/bin/napcat"
    else
        cmd_path="${user_bin}/napcat"
    fi

    local wrapper_tmp="${WORKDIR}/napcat.simple"
    cat > "${wrapper_tmp}" << EOF
#!/usr/bin/env bash
set -euo pipefail
QQ_BIN="${QQ_EXECUTABLE}"
INSTALL_BASE="${INSTALL_BASE_DIR}"
NAPCAT_HOME="${NAPCAT_DIR}"
SESSION_NAME="napcat"
if [[ ! -f "\${QQ_BIN}" ]]; then
    echo "错误: 未找到 QQ: \${QQ_BIN}"; exit 1
fi
run_fg() {
    if command -v xvfb-run >/dev/null 2>&1; then
        exec xvfb-run -a "\${QQ_BIN}" --no-sandbox "\$@"
    else
        exec "\${QQ_BIN}" --no-sandbox "\$@"
    fi
}
session_exists() {
    command -v screen >/dev/null 2>&1 || return 1
    screen -list 2>/dev/null | grep -qE "[0-9]+\\.\${SESSION_NAME}[[:space:]]"
}
cmd="\${1:-start}"; shift || true
case "\${cmd}" in
    start|run|fg|"") run_fg "\$@" ;;
    bg|background|daemon)
        command -v screen >/dev/null 2>&1 || { echo "需要 screen"; exit 1; }
        session_exists && { echo "已在运行"; exit 0; }
        if command -v xvfb-run >/dev/null 2>&1; then
            screen -dmS "\${SESSION_NAME}" xvfb-run -a "\${QQ_BIN}" --no-sandbox "\$@"
        else
            screen -dmS "\${SESSION_NAME}" "\${QQ_BIN}" --no-sandbox "\$@"
        fi
        echo "后台已启动: screen -r \${SESSION_NAME}"
        ;;
    stop) session_exists && screen -S "\${SESSION_NAME}" -X quit && echo stopped || echo "未运行" ;;
    status)
        echo "QQ=\${QQ_BIN}"; echo "NAPCAT=\${NAPCAT_HOME}"
        session_exists && echo "后台: 运行中" || echo "后台: 未运行"
        ;;
    help|-h|--help)
        echo "简易 napcat: start|bg|stop|status"
        echo "提示: 官方 TUI 安装失败时使用此回退命令"
        ;;
    *)
        if [[ "\${cmd}" =~ ^[0-9]+$ ]]; then run_fg -q "\${cmd}" "\$@"; else
            echo "未知参数: \${cmd}"; exit 1
        fi
        ;;
esac
EOF
    if [[ "${cmd_path}" == /usr/local/bin/napcat ]]; then
        if [[ -w /usr/local/bin ]] || [[ "$(id -u)" -eq 0 ]]; then
            install -m 755 "${wrapper_tmp}" "${cmd_path}"
        elif need_cmd sudo && sudo install -m 755 "${wrapper_tmp}" "${cmd_path}"; then
            :
        else
            cmd_path="${user_bin}/napcat"
            install -m 755 "${wrapper_tmp}" "${cmd_path}"
        fi
    else
        install -m 755 "${wrapper_tmp}" "${cmd_path}"
    fi
    NAPCAT_CMD_PATH="${cmd_path}"
    log "已安装简易命令: ${cmd_path}"
}

show_summary() {
    echo ""
    log "======== 安装完成 ========"
    log "安装目录: ${INSTALL_BASE_DIR}"
    log "QQ 路径: ${QQ_EXECUTABLE}"
    log "NapCat 路径: ${NAPCAT_DIR}"
    log "下载缓存: ${DOWNLOAD_DIR}"
    log "QQ 版本: ${SELECTED_QQ_VERSION}"
    log "系统架构: ${SYSTEM_ARCH}"
    log "包格式: ${PACKAGE_FORMAT}"
    log "下载方式: $([ "${USE_PROXY}" = "y" ] && echo "代理 ${PROXY_PREFIX}" || echo "直连")"
    echo ""
    log "快捷命令 (官方 TUI-CLI):"
    if [[ -n "${NAPCAT_CMD_PATH:-}" ]]; then
        echo -e "  ${CYAN}napcat${NC}              # 打开终端管理界面 (dialog TUI)"
        echo -e "  命令路径: ${CYAN}${NAPCAT_CMD_PATH}${NC}"
        echo -e "  文档: ${CYAN}https://napneko.github.io/guide/napcat${NC}"
        echo -e "  项目: ${CYAN}https://github.com/NapNeko/NapCat-TUI-CLI${NC}"
    else
        echo -e "  ${CYAN}xvfb-run -a ${QQ_EXECUTABLE} --no-sandbox${NC}"
    fi
    echo ""
    log "等价原生命令:"
    echo -e "  ${CYAN}xvfb-run -a ${QQ_EXECUTABLE} --no-sandbox${NC}"
    echo ""
    log "WebUI Token 文件:"
    echo -e "  ${CYAN}${NAPCAT_DIR}/config/webui.json${NC}"
    log "=========================="
}

main() {
    clear || true
    logo

    detect_arch
    detect_distro
    choose_package_format
    choose_proxy

    DOWNLOAD_DIR="${WORKDIR}/downloads"
    mkdir -p "${DOWNLOAD_DIR}"
    log "临时工作目录: ${WORKDIR}"
    log "文件下载目录: ${DOWNLOAD_DIR}"
    log "最终安装目录: ${INSTALL_BASE_DIR}"

    ensure_deps
    choose_qq_version
    check_existing_install
    install_linuxqq
    download_and_install_napcat
    install_napcat_tui_cli
    show_summary
}

main "$@"
