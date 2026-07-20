#!/usr/bin/env bash
# NapCat Installer (Simplified)
# Features: skip-if-exists, gitee/manual modes, size-based detection

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

DOWNLOAD_MODE="direct"   # direct | gitee | manual
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
MANUAL_PKG_DIR=""
MANUAL_QQ_PKG=""
MANUAL_NAPCAT_ZIP=""

QQ_MIN_SIZE=$((100 * 1024 * 1024))
NAPCAT_MIN_SIZE=$((20 * 1024 * 1024))

QQ_VERSIONS_FILE="${SCRIPT_DIR}/data/qq_versions.json"
NAPCAT_INSTALL_REPO="${NAPCAT_INSTALL_REPO:-Qiscard/napcat_install}"
QQ_VERSIONS_REMOTE_CANDIDATES=(
    "https://raw.githubusercontent.com/${NAPCAT_INSTALL_REPO}/main/data/qq_versions.json"
    "https://cdn.jsdelivr.net/gh/${NAPCAT_INSTALL_REPO}@main/data/qq_versions.json"
    "https://gitee.com/${NAPCAT_INSTALL_REPO}/raw/main/data/qq_versions.json"
)

cleanup() {
    if [[ -n "${WORKDIR:-}" && -d "${WORKDIR}" ]]; then rm -rf "${WORKDIR}"; fi
}
trap cleanup EXIT

log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')]: $1"
    case "$1" in
        *"失败"*|*"错误"*|*"无法"*) echo -e "${RED}${message}${NC}" >&2 ;;
        *"成功"*) echo -e "${GREEN}${message}${NC}" >&2 ;;
        *"忽略"*|*"跳过"*|*"警告"*|*"默认"*) echo -e "${YELLOW}${message}${NC}" >&2 ;;
        *) echo -e "${BLUE}${message}${NC}" >&2 ;;
    esac
}

logo() {
    echo -e "${MAGENTA}NapCat Installer (Simplified)${NC}"
    echo -e "${CYAN}Install Dir: ${INSTALL_BASE_DIR}${NC}"
    echo ""
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

prompt_timeout() {
    local seconds="$1" prompt="$2" default="$3" input=""
    if read -t "${seconds}" -r -p "${prompt}" input </dev/tty; then
        echo "" >&2
        [[ -z "${input}" ]] && printf "%s" "${default}" || printf "%s" "${input}"
    else
        echo "" >&2; log "Timeout, using default: ${default}"; printf "%s" "${default}"
    fi
}

detect_arch() {
    local raw=$(uname -m)
    case "${raw}" in
        x86_64|amd64) SYSTEM_ARCH="amd64" ;;
        aarch64|arm64) SYSTEM_ARCH="arm64" ;;
        loongarch64) SYSTEM_ARCH="loongarch64" ;;
        mips64el|mips64) SYSTEM_ARCH="mips64el" ;;
        *) log "Unsupported arch: ${raw}"; exit 1 ;;
    esac
    log "Arch: ${raw} -> ${SYSTEM_ARCH}"
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        log "Distro: ${NAME:-$DISTRO_ID} (${VERSION_ID:-unknown})"
    else DISTRO_ID="unknown"; fi
    if need_cmd apt-get || need_cmd dpkg; then PACKAGE_MANAGER="apt"; PACKAGE_FORMAT="deb"
    elif need_cmd dnf || need_cmd yum || need_cmd rpm; then PACKAGE_MANAGER="dnf"; PACKAGE_FORMAT="rpm"
    else PACKAGE_MANAGER="unknown"; PACKAGE_FORMAT="deb"; fi
    log "Package format: ${PACKAGE_FORMAT} (${PACKAGE_MANAGER})"
}

check_local_qq_package() {
    local dir="${1:-$(manual_pkg_dir)}"
    local fmt="${PACKAGE_FORMAT}"

    if [[ -f "${dir}/QQ.${fmt}" ]]; then
        local size=$(stat -c%s "${dir}/QQ.${fmt}" 2>/dev/null || stat -f%z "${dir}/QQ.${fmt}" 2>/dev/null || echo 0)
        if (( size > QQ_MIN_SIZE )); then
            MANUAL_QQ_PKG="${dir}/QQ.${fmt}"
            return 0
        fi
    fi

    local found=$(ls -1 "${dir}"/QQ_*.${fmt} 2>/dev/null | head -n1 || true)
    if [[ -n "${found}" && -f "${found}" ]]; then
        local size=$(stat -c%s "${found}" 2>/dev/null || stat -f%z "${found}" 2>/dev/null || echo 0)
        if (( size > QQ_MIN_SIZE )); then
            MANUAL_QQ_PKG="${found}"
            return 0
        fi
    fi

    return 1
}

check_local_napcat_package() {
    local dir="${1:-$(manual_pkg_dir)}"

    if [[ -f "${dir}/NapCat.Shell.zip" ]]; then
        local size=$(stat -c%s "${dir}/NapCat.Shell.zip" 2>/dev/null || stat -f%z "${dir}/NapCat.Shell.zip" 2>/dev/null || echo 0)
        if (( size > NAPCAT_MIN_SIZE )); then
            MANUAL_NAPCAT_ZIP="${dir}/NapCat.Shell.zip"
            return 0
        fi
    fi

    return 1
}

manual_pkg_dir() {
    if [[ -n "${MANUAL_PKG_DIR}" ]]; then echo "${MANUAL_PKG_DIR}"; return; fi
    if [[ -d "${SCRIPT_DIR}/packages" ]] || [[ -f "${SCRIPT_DIR}/install.sh" ]]; then
        echo "${SCRIPT_DIR}/packages"
    else
        echo "$(pwd)/packages"
    fi
}

print_manual_import_guide() {
    local dir=$(manual_pkg_dir)
    mkdir -p "${dir}"
    echo ""
    log "======== Manual Import Guide ========"
    log "Place files in:"
    echo -e "  ${CYAN}${dir}${NC}"
    echo ""
    log "Required:"
    echo -e "  1) ${GREEN}NapCat.Shell.zip${NC}  (zip, >20MB)"
    echo -e "     Source: https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
    echo ""
    echo -e "  2) ${GREEN}LinuxQQ package${NC}  (.${PACKAGE_FORMAT}, >100MB)"
    echo -e "     Filename: QQ*.${PACKAGE_FORMAT}"
    echo -e "     Arch: ${SYSTEM_ARCH}"
    echo -e "     Source: https://rodert.github.io/qq-versions/"
    echo ""
    log "Optional:"
    echo -e "  - NapCat.Shell.zip.sha256 (verify)"
    echo ""
    log "After placing files, press Enter to continue"
    echo -e "  ${CYAN}Enter -> detect files and install${NC}"
    log "=============================="
}

wait_manual_packages() {
    local dir=$(manual_pkg_dir)
    MANUAL_PKG_DIR="${dir}"
    mkdir -p "${dir}"
    print_manual_import_guide
    echo ""
    read -r -p "Press Enter when ready (q to quit): " ans </dev/tty || true
    if [[ "${ans}" =~ ^[Qq]$ ]]; then log "Cancelled"; exit 0; fi

    local qq_ok="n" napcat_ok="n"

    if check_local_qq_package "${dir}"; then
        qq_ok="y"
        log "Found QQ: ${MANUAL_QQ_PKG} ($(du -h "${MANUAL_QQ_PKG}" | awk '{print $1}'))"
    else
        log "Missing: QQ package (.${PACKAGE_FORMAT}, >100MB)"
        log "Format: QQ_*.${PACKAGE_FORMAT} or QQ.${PACKAGE_FORMAT}"
        log "Location: ${dir}/"
    fi

    if check_local_napcat_package "${dir}"; then
        napcat_ok="y"
        log "Found NapCat.Shell.zip ($(du -h "${MANUAL_NAPCAT_ZIP}" | awk '{print $1}'))"
    else
        log "Missing: NapCat.Shell.zip (>20MB)"
        log "Format: NapCat.Shell.zip (fixed)"
        log "Location: ${dir}/"
    fi

    if [[ "${qq_ok}" == "y" && "${napcat_ok}" == "y" ]]; then
        log "Manual import check passed, continuing"
        return 0
    fi

    echo ""
    log "=============================="
    log "Missing packages. Import to: ${dir}/"
    log "Re-run manual mode after import"
    log "=============================="
    exit 1
}

download_file() {
    local url="$1" dest="$2"
    log "Download: ${url}"
    log "Save to: ${dest}"
    rm -f "${dest}"
    if ! curl -k -L --connect-timeout 20 --max-time 600 --retry 3 --retry-delay 2 -# "${url}" -o "${dest}"; then
        log "Error: download failed: ${url}"
        return 1
    fi
    if [[ ! -s "${dest}" ]]; then log "Error: empty file"; return 1; fi
    log "Downloaded: ${dest} ($(du -h "${dest}" | awk '{print $1}'))"
}

url_reachable() {
    local url="$1"
    local code size
    read -r code size < <(curl -k -s -o /dev/null -w "%{http_code} %{size_download}" -L --connect-timeout 12 --max-time 25 -A "Mozilla/5.0" -r 0-2047 "${url}" || echo "000 0")
    if [[ "${code}" =~ ^[0-9]+$ && "${code}" -lt 400 && "${size}" -gt 0 ]]; then return 0; fi
    log "Unreachable: HTTP ${code}, bytes=${size}, url=${url}"
    return 1
}

ensure_deps() {
    local missing=()
    for c in curl unzip jq; do need_cmd "$c" || missing+=("$c"); done
    if [[ "${PACKAGE_FORMAT}" == "deb" ]]; then need_cmd dpkg || missing+=("dpkg")
    else need_cmd rpm2cpio || missing+=("rpm2cpio"); need_cmd cpio || missing+=("cpio"); fi
    need_cmd xvfb-run || true; need_cmd screen || true
    if [[ ${#missing[@]} -eq 0 ]]; then log "Deps OK"; return 0; fi
    log "Missing deps: ${missing[*]}"
    local SUDO=""
    if [[ "$(id -u)" -ne 0 ]]; then need_cmd sudo && SUDO="sudo" || { log "Need sudo"; exit 1; }; fi
    if [[ "${PACKAGE_MANAGER}" == "apt" ]] || need_cmd apt-get; then
        ${SUDO} apt-get update -y -qq
        ${SUDO} apt-get install -y -qq curl unzip jq dpkg xvfb xauth screen dialog 2>/dev/null || ${SUDO} apt-get install -y -qq curl unzip jq dpkg xvfb xauth screen dialog
    elif need_cmd dnf; then
        ${SUDO} dnf install -y curl unzip jq cpio rpm xvfb-run screen || ${SUDO} dnf install -y curl unzip jq cpio rpm
    elif need_cmd yum; then
        ${SUDO} yum install -y curl unzip jq cpio rpm screen || ${SUDO} yum install -y curl unzip jq cpio rpm
    else log "Cannot auto-install: ${missing[*]}"; exit 1; fi
    log "Deps installed"
}

gitee_download_napcat() {
    local dest="$1"
    local urls=(
        "https://gitee.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
        "https://raw.gitmirror.com/NapNeko/NapCatQQ/main/NapCat.Shell.zip"
    )
    for url in "${urls[@]}"; do
        log "Gitee source: ${url}"
        if download_file "${url}" "${dest}" && unzip -t "${dest}" >/dev/null 2>&1; then
            return 0
        fi
        rm -f "${dest}"
    done
    return 1
}

install_linuxqq() {
    mkdir -p "${DOWNLOAD_DIR}"
    if [[ "${DOWNLOAD_MODE}" == "manual" && -n "${MANUAL_QQ_PKG:-}" ]]; then
        SELECTED_QQ_FILENAME="$(basename "${MANUAL_QQ_PKG}")"
    fi
    local pkg_path="${DOWNLOAD_DIR}/${SELECTED_QQ_FILENAME}"
    log "Getting LinuxQQ package..."
    if [[ "${DOWNLOAD_MODE}" == "manual" && -n "${MANUAL_QQ_PKG:-}" && -s "${MANUAL_QQ_PKG}" ]]; then
        log "Using local: ${MANUAL_QQ_PKG}"
        cp -f "${MANUAL_QQ_PKG}" "${pkg_path}"
    else
        log "Downloading: ${SELECTED_QQ_URL}"
        if ! download_file "${SELECTED_QQ_URL}" "${pkg_path}"; then
            log "Error: download failed"; exit 1
        fi
    fi
    if [[ -n "${SELECTED_QQ_SHA256}" ]] && need_cmd sha256sum; then
        local actual=$(sha256sum "${pkg_path}" | awk '{print $1}')
        if [[ "${actual}" != "${SELECTED_QQ_SHA256}" ]]; then log "Error: SHA256 mismatch"; exit 1; fi
        log "SHA256 OK"
    fi
    if [[ "${FORCE_OVERWRITE}" == "y" && -d "${INSTALL_BASE_DIR}" ]]; then
        local backup_cfg=""
        if [[ -d "${NAPCAT_DIR}/config" ]]; then
            backup_cfg="${WORKDIR}/napcat_config_backup"
            mkdir -p "${backup_cfg}"
            cp -a "${NAPCAT_DIR}/config/." "${backup_cfg}/" || true
        fi
        rm -rf "${INSTALL_BASE_DIR}"
        [[ -n "${backup_cfg}" ]] && export NAPCAT_CONFIG_BACKUP="${backup_cfg}"
    fi
    mkdir -p "${INSTALL_BASE_DIR}"
    log "Extracting QQ..."
    if [[ "${PACKAGE_FORMAT}" == "deb" ]]; then dpkg -x "${pkg_path}" "${INSTALL_BASE_DIR}"
    else rpm2cpio "${pkg_path}" | (cd "${INSTALL_BASE_DIR}" && cpio -idm); fi
    [[ ! -x "${QQ_EXECUTABLE}" && -f "${QQ_EXECUTABLE}" ]] && chmod +x "${QQ_EXECUTABLE}" || true
    if [[ ! -f "${QQ_PACKAGE_JSON_PATH}" ]]; then log "Error: QQ extraction failed"; exit 1; fi
    log "LinuxQQ installed"
}

download_and_install_napcat() {
    local zip_path="${DOWNLOAD_DIR}/NapCat.Shell.zip"
    local local_zip="" cand
    local napcat_url="https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
    if [[ "${DOWNLOAD_MODE}" == "manual" && -n "${MANUAL_NAPCAT_ZIP:-}" && -s "${MANUAL_NAPCAT_ZIP}" ]]; then
        local_zip="${MANUAL_NAPCAT_ZIP}"
    fi
    if [[ -z "${local_zip}" ]]; then
        for cand in "${SCRIPT_DIR}/packages/NapCat.Shell.zip" "${SCRIPT_DIR}/NapCat.Shell.zip" "./packages/NapCat.Shell.zip" "./NapCat.Shell.zip"; do
            [[ -f "${cand}" && -s "${cand}" ]] && { local_zip="${cand}"; break; }
        done
    fi
    if [[ -n "${local_zip}" ]]; then
        log "Using local NapCat: ${local_zip}"
        if [[ -f "${local_zip}.sha256" ]]; then
            local expect=$(awk 'NR==1{print $1}' "${local_zip}.sha256")
            local actual=$(sha256sum "${local_zip}" | awk '{print $1}')
            if [[ -n "${expect}" && "${expect}" != "${actual}" ]]; then
                log "Warning: local SHA256 mismatch"
                [[ "${DOWNLOAD_MODE}" == "manual" ]] && { log "Error: manual package corrupt"; exit 1; }
                local_zip=""
            fi
        fi
    fi
    if [[ -n "${local_zip}" ]]; then
        cp -f "${local_zip}" "${zip_path}"
    else
        if [[ "${DOWNLOAD_MODE}" == "manual" ]]; then log "Error: no NapCat.Shell.zip"; print_manual_import_guide; exit 1; fi
        if [[ "${DOWNLOAD_MODE}" == "gitee" ]]; then
            log "Gitee download NapCat..."
            if ! gitee_download_napcat "${zip_path}"; then
                log "Gitee failed, falling back to GitHub..."
                download_file "${napcat_url}" "${zip_path}" || { log "Error: download failed"; exit 1; }
            fi
        else
            log "Direct download NapCat..."
            if ! download_file "${napcat_url}" "${zip_path}"; then
                log "Direct failed, trying Gitee sources..."
                gitee_download_napcat "${zip_path}" || { log "Error: all download sources failed"; exit 1; }
            fi
        fi
        unzip -t "${zip_path}" >/dev/null 2>&1 || { log "Error: invalid zip"; exit 1; }
    fi
    local extract_dir="${WORKDIR}/NapCatExtract"
    rm -rf "${extract_dir}"; mkdir -p "${extract_dir}"
    unzip -q -o "${zip_path}" -d "${extract_dir}"
    local src_dir="${extract_dir}"
    [[ -d "${extract_dir}/NapCat" ]] && src_dir="${extract_dir}/NapCat"
    [[ -f "${extract_dir}/napcat.mjs" ]] && src_dir="${extract_dir}"
    mkdir -p "${NAPCAT_DIR}"
    cp -a "${src_dir}/." "${NAPCAT_DIR}/"
    chmod -R +x "${NAPCAT_DIR}" || true
    if [[ -n "${NAPCAT_CONFIG_BACKUP:-}" && -d "${NAPCAT_CONFIG_BACKUP}" ]]; then
        mkdir -p "${NAPCAT_DIR}/config"; cp -a "${NAPCAT_CONFIG_BACKUP}/." "${NAPCAT_DIR}/config/" || true
        log "Restored NapCat config"
    fi
    local loader="${QQ_BASE_PATH}/resources/app/loadNapCat.js"
    echo "(async () => {await import('file:///${NAPCAT_DIR}/napcat.mjs');})();" > "${loader}"
    jq '.main = "./loadNapCat.js"' "${QQ_PACKAGE_JSON_PATH}" > "${WORKDIR}/pkg.tmp"
    mv "${WORKDIR}/pkg.tmp" "${QQ_PACKAGE_JSON_PATH}"
    log "NapCat installed"
}

install_napcat_tui_cli() {
    echo ""
    log "Install official NapCat TUI-CLI?"
    local choice=$(prompt_timeout 10 "Install TUI-CLI? [Y/n]: " "Y")
    [[ "${choice}" =~ ^[Nn]$ ]] && { install_napcat_simple_command; return 0; }
    local missing=()
    need_cmd dialog || missing+=("dialog")
    need_cmd ffmpeg || missing+=("ffmpeg")
    if [[ ${#missing[@]} -gt 0 ]]; then
        local SUDO=""
        [[ "$(id -u)" -ne 0 ]] && need_cmd sudo && SUDO="sudo" || true
        if need_cmd apt-get; then ${SUDO} apt-get update -y -qq || true; ${SUDO} apt-get install -y -qq "${missing[@]}" || true
        elif need_cmd dnf; then ${SUDO} dnf install -y "${missing[@]}" || true
        elif need_cmd yum; then ${SUDO} yum install -y "${missing[@]}" || true; fi
    fi
    need_cmd dialog || { install_napcat_simple_command; return 1; }
    local target_dir="/usr/local/bin" use_sudo_install="n"
    if [[ -w "${target_dir}" ]] || [[ "$(id -u)" -eq 0 ]]; then use_sudo_install="n"
    elif need_cmd sudo; then use_sudo_install="y"
    else target_dir="${HOME}/.local/bin"; mkdir -p "${target_dir}"; fi
    local base_url="https://raw.githubusercontent.com/NapNeko/NapCat-TUI-CLI/main/script/tui-cli"
    local files=("napcat" "_napcat_Boot" "_napcat_Config" "_napcat_old")
    local failed="n" tmp_dir="${WORKDIR}/tui-cli"
    mkdir -p "${tmp_dir}"
    local f url dest tmpf
    for f in "${files[@]}"; do
        url="${base_url}/${f}"; tmpf="${tmp_dir}/${f}"; dest="${target_dir}/${f}"
        download_file "${url}" "${tmpf}" || { failed="y"; break; }
        head -n1 "${tmpf}" | grep -q "^#!"  || { failed="y"; break; }
        chmod 755 "${tmpf}"
        if [[ "${use_sudo_install}" == "y" ]]; then
            sudo mv "${tmpf}" "${dest}" && sudo chmod 755 "${dest}" || { failed="y"; break; }
        else
            mv "${tmpf}" "${dest}" && chmod 755 "${dest}" || { failed="y"; break; }
        fi
    done
    [[ "${failed}" == "y" ]] && { install_napcat_simple_command; return 1; }
    NAPCAT_CMD_PATH="${target_dir}/napcat"
    log "TUI-CLI installed: ${NAPCAT_CMD_PATH}"
}

install_napcat_simple_command() {
    local cmd_path="" user_bin="${HOME}/.local/bin"
    mkdir -p "${user_bin}"
    if [[ -w /usr/local/bin ]] || [[ "$(id -u)" -eq 0 ]]; then cmd_path="/usr/local/bin/napcat"
    else cmd_path="${user_bin}/napcat"; fi
    local wrapper_tmp="${WORKDIR}/napcat.simple"
    cat > "${wrapper_tmp}" << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
QQ_BIN="QQBIN_PLACEHOLDER"
INSTALL_BASE="INSTALLBASE_PLACEHOLDER"
NAPCAT_HOME="NAPCATHOME_PLACEHOLDER"
SESSION_NAME="napcat"
if [[ ! -f "${QQ_BIN}" ]]; then echo "Error: QQ not found: ${QQ_BIN}"; exit 1; fi
run_fg() {
    if command -v xvfb-run >/dev/null 2>&1; then exec xvfb-run -a "${QQ_BIN}" --no-sandbox "$@"
    else exec "${QQ_BIN}" --no-sandbox "$@"; fi
}
session_exists() { command -v screen >/dev/null 2>&1 || return 1; screen -list 2>/dev/null | grep -qE "[0-9]+\.${SESSION_NAME}[[:space:]]"; }
cmd="${1:-start}"; shift || true
case "${cmd}" in
    start|run|fg|"") run_fg "$@" ;;
    bg|background|daemon)
        command -v screen >/dev/null 2>&1 || { echo "Need screen"; exit 1; }
        session_exists && { echo "Already running"; exit 0; }
        if command -v xvfb-run >/dev/null 2>&1; then screen -dmS "${SESSION_NAME}" xvfb-run -a "${QQ_BIN}" --no-sandbox "$@"
        else screen -dmS "${SESSION_NAME}" "${QQ_BIN}" --no-sandbox "$@"; fi
        echo "Background started: screen -r ${SESSION_NAME}"
        ;;
    stop) session_exists && screen -S "${SESSION_NAME}" -X quit && echo stopped || echo "Not running" ;;
    status) echo "QQ=${QQ_BIN}"; echo "NAPCAT=${NAPCAT_HOME}"; session_exists && echo "BG: running" || echo "BG: stopped" ;;
    help|-h|--help) echo "Usage: napcat start|bg|stop|status" ;;
    *) if [[ "${cmd}" =~ ^[0-9]+$ ]]; then run_fg -q "${cmd}" "$@"; else echo "Unknown: ${cmd}"; exit 1; fi ;;
esac
WRAPPER_EOF
    sed -i "s|QQBIN_PLACEHOLDER|${QQ_EXECUTABLE}|g" "${wrapper_tmp}"
    sed -i "s|INSTALLBASE_PLACEHOLDER|${INSTALL_BASE_DIR}|g" "${wrapper_tmp}"
    sed -i "s|NAPCATHOME_PLACEHOLDER|${NAPCAT_DIR}|g" "${wrapper_tmp}"
    if [[ "${cmd_path}" == /usr/local/bin/napcat ]]; then
        if [[ -w /usr/local/bin ]] || [[ "$(id -u)" -eq 0 ]]; then install -m 755 "${wrapper_tmp}" "${cmd_path}"
        elif need_cmd sudo && sudo install -m 755 "${wrapper_tmp}" "${cmd_path}"; then :
        else cmd_path="${user_bin}/napcat"; install -m 755 "${wrapper_tmp}" "${cmd_path}"; fi
    else install -m 755 "${wrapper_tmp}" "${cmd_path}"; fi
    NAPCAT_CMD_PATH="${cmd_path}"
    log "Simple command: ${cmd_path}"
}

show_summary() {
    echo ""
    log "======== Installation Complete ========"
    log "Install dir: ${INSTALL_BASE_DIR}"
    log "QQ path: ${QQ_EXECUTABLE}"
    log "NapCat path: ${NAPCAT_DIR}"
    log "QQ version: ${SELECTED_QQ_VERSION}"
    log "Source: $([ "${DOWNLOAD_MODE}" = "manual" ] && echo "Manual" || ([ "${DOWNLOAD_MODE}" = "gitee" ] && echo "Gitee" || echo "Direct"))"
    echo ""
    log "Start command:"
    if [[ -n "${NAPCAT_CMD_PATH:-}" ]]; then
        echo -e "  ${CYAN}napcat${NC}    # Terminal UI"
        echo -e "  Path: ${CYAN}${NAPCAT_CMD_PATH}${NC}"
        echo -e "  Docs: ${CYAN}https://napneko.github.io/guide/napcat${NC}"
    else
        echo -e "  ${CYAN}xvfb-run -a ${QQ_EXECUTABLE} --no-sandbox${NC}"
    fi
    echo ""
    log "Raw: xvfb-run -a ${QQ_EXECUTABLE} --no-sandbox"
    log "WebUI Token: ${NAPCAT_DIR}/config/webui.json"
    log "=========================="
}

main() {
    clear || true
    logo
    detect_arch
    detect_distro
    choose_download_mode
    echo ""
    log "Checking local packages..."
    local qq_found="n" napcat_found="n"
    local dir=$(manual_pkg_dir)
    check_local_qq_package && { qq_found="y"; log "Found QQ: ${MANUAL_QQ_PKG}"; }
    check_local_napcat_package && { napcat_found="y"; log "Found NapCat: ${MANUAL_NAPCAT_ZIP}"; }
    if [[ "${qq_found}" == "y" && "${napcat_found}" == "y" ]]; then
        log "Local packages ready, skip download"
        [[ "${DOWNLOAD_MODE}" != "manual" ]] && DOWNLOAD_MODE="manual"
    elif [[ "${DOWNLOAD_MODE}" == "manual" ]]; then
        wait_manual_packages
    fi
    DOWNLOAD_DIR="${WORKDIR}/downloads"
    mkdir -p "${DOWNLOAD_DIR}"
    log "Work dir: ${WORKDIR}"
    ensure_deps
    if [[ "${DOWNLOAD_MODE}" == "manual" ]]; then
        log "Manual: skip version selection"
        SELECTED_QQ_VERSION="manual"
        SELECTED_QQ_FILENAME="$(basename "${MANUAL_QQ_PKG}")"
    else
        choose_qq_version
    fi
    check_existing_install
    install_linuxqq
    download_and_install_napcat
    install_napcat_tui_cli
    show_summary
}

main "$@"
