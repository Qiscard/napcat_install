#!/usr/bin/env bash
# NapCat installer. Packages are checked locally before any network request.

set -euo pipefail

readonly QQ_MIN_SIZE=$((100 * 1024 * 1024))
readonly NAPCAT_MIN_SIZE=$((20 * 1024 * 1024))
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
if [[ "${SCRIPT_SOURCE}" == /dev/fd/* || "${SCRIPT_SOURCE}" == /proc/self/fd/* ]]; then
    # `bash <(curl ...)` has no repository directory; use the caller's directory.
    SCRIPT_DIR="$(pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
fi
readonly PACKAGE_DIR="${SCRIPT_DIR}/packages"
QQ_VERSIONS_FILE="${SCRIPT_DIR}/data/qq_versions.json"
readonly INSTALL_BASE_DIR="${HOME}/Napcat"
readonly QQ_BASE_PATH="${INSTALL_BASE_DIR}/opt/QQ"
readonly QQ_EXECUTABLE="${QQ_BASE_PATH}/qq"
readonly QQ_PACKAGE_JSON_PATH="${QQ_BASE_PATH}/resources/app/package.json"
readonly NAPCAT_DIR="${QQ_BASE_PATH}/resources/app/app_launcher/napcat"
readonly DIRECT_NAPCAT_URL="https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
readonly GITEE_NAPCAT_URL="https://gitee.com/qiscard/napcat_install/raw/main/packages/NapCat.Shell.zip"
readonly GITEE_REPOSITORY_ARCHIVE_URL="https://gitee.com/qiscard/napcat_install/repository/archive/main.zip"
readonly DIRECT_QQ_VERSIONS_URL="https://raw.githubusercontent.com/Qiscard/napcat_install/main/data/qq_versions.json"
readonly GITEE_QQ_VERSIONS_URL="https://gitee.com/qiscard/napcat_install/raw/main/data/qq_versions.json"

WORKDIR="${TMPDIR:-/tmp}/napcat_install_$$"
PACKAGE_FORMAT=""
DETECTED_ARCH=""
DOWNLOAD_MODE=""
QQ_PACKAGE=""
NAPCAT_PACKAGE=""
SELECTED_QQ_VERSION=""
SELECTED_QQ_FILENAME=""
SELECTED_QQ_URL=""
SELECTED_QQ_SHA256=""
NAPCAT_CMD_PATH=""

cleanup() {
    [[ -d "${WORKDIR}" ]] && rm -rf "${WORKDIR}"
}
trap cleanup EXIT

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { log "错误: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }

file_size() {
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || printf '0'
}

is_large_enough() {
    local file="$1" minimum="$2"
    [[ -f "${file}" ]] && (( $(file_size "${file}") > minimum ))
}

detect_package_platform() {
    # Package tooling is the source of truth; there is no user-selectable architecture.
    if need_cmd dpkg; then
        PACKAGE_FORMAT="deb"
        DETECTED_ARCH="$(dpkg --print-architecture)"
    elif need_cmd rpm && need_cmd rpm2cpio; then
        PACKAGE_FORMAT="rpm"
        DETECTED_ARCH="$(rpm --eval '%{_arch}')"
        case "${DETECTED_ARCH}" in
            x86_64) DETECTED_ARCH="amd64" ;;
            aarch64) DETECTED_ARCH="arm64" ;;
        esac
    else
        die "未检测到可用的 dpkg 或 rpm/rpm2cpio，无法确定安装包格式"
    fi
    log "检测到安装包格式: ${PACKAGE_FORMAT}; 系统架构: ${DETECTED_ARCH}"
}

find_local_qq_package() {
    local candidate
    QQ_PACKAGE=""
    shopt -s nullglob nocaseglob
    for candidate in "${PACKAGE_DIR}"/QQ*."${PACKAGE_FORMAT}"; do
        if is_large_enough "${candidate}" "${QQ_MIN_SIZE}"; then
            QQ_PACKAGE="${candidate}"
            break
        fi
    done
    shopt -u nullglob nocaseglob
    [[ -n "${QQ_PACKAGE}" ]]
}

find_local_napcat_package() {
    NAPCAT_PACKAGE=""
    local candidate="${PACKAGE_DIR}/NapCat.Shell.zip"
    if is_large_enough "${candidate}" "${NAPCAT_MIN_SIZE}"; then
        NAPCAT_PACKAGE="${candidate}"
        return 0
    fi
    return 1
}

show_manual_import_guide() {
    mkdir -p "${PACKAGE_DIR}"
    log "缺少安装包，请手动导入后重新运行手动模式。"
    printf '\n存放位置:\n  %s\n\n' "${PACKAGE_DIR}"
    printf '需要的文件:\n'
    printf '  1. QQ*.%s（大于 100 MB）\n' "${PACKAGE_FORMAT}"
    printf '  2. NapCat.Shell.zip（固定文件名，大于 20 MB）\n\n'
    printf '导入成功后重新运行手动模式。\n'
}

choose_download_mode() {
    if [[ -n "${NAPCAT_INSTALL_MODE:-}" ]]; then
        DOWNLOAD_MODE="${NAPCAT_INSTALL_MODE}"
    else
        printf '\n缺少安装包，选择获取方式:\n'
        printf '  1) 直连下载\n'
        printf '  2) Gitee 下载（网络因素可选择此方案）\n'
        printf '  3) 手动导入\n'
        read -r -p '请选择 [1]: ' DOWNLOAD_MODE </dev/tty || DOWNLOAD_MODE="1"
    fi
    case "${DOWNLOAD_MODE:-1}" in
        1|direct) DOWNLOAD_MODE="direct" ;;
        2|gitee) DOWNLOAD_MODE="gitee" ;;
        3|manual) DOWNLOAD_MODE="manual" ;;
        *) die "无效的获取方式: ${DOWNLOAD_MODE}" ;;
    esac
}

ensure_dependencies() {
    local missing=() command
    for command in curl unzip jq; do
        need_cmd "${command}" || missing+=("${command}")
    done
    if [[ "${PACKAGE_FORMAT}" == "deb" ]]; then
        need_cmd dpkg || missing+=("dpkg")
    else
        need_cmd rpm2cpio || missing+=("rpm2cpio")
        need_cmd cpio || missing+=("cpio")
    fi
    [[ ${#missing[@]} -eq 0 ]] && return 0

    local sudo_cmd=()
    [[ "$(id -u)" -eq 0 ]] || { need_cmd sudo || die "缺少依赖: ${missing[*]}，且 sudo 不可用"; sudo_cmd=(sudo); }
    if need_cmd apt-get; then
        "${sudo_cmd[@]}" apt-get update -y
        "${sudo_cmd[@]}" apt-get install -y curl unzip jq dpkg
    elif need_cmd dnf; then
        "${sudo_cmd[@]}" dnf install -y curl unzip jq cpio rpm
    elif need_cmd yum; then
        "${sudo_cmd[@]}" yum install -y curl unzip jq cpio rpm
    else
        die "请先安装依赖: ${missing[*]}"
    fi
}

prepare_qq_versions_file() {
    [[ -f "${QQ_VERSIONS_FILE}" ]] && return 0
    local source_url="${DIRECT_QQ_VERSIONS_URL}"
    [[ "${DOWNLOAD_MODE}" == "gitee" ]] && source_url="${GITEE_QQ_VERSIONS_URL}"
    QQ_VERSIONS_FILE="${WORKDIR}/qq_versions.json"
    log "获取 QQ 版本列表: ${source_url}"
    curl -fL --connect-timeout 20 --max-time 120 --retry 3 --retry-delay 2 "${source_url}" -o "${QQ_VERSIONS_FILE}" || die "QQ 版本列表下载失败"
    jq -e '.packages | type == "array"' "${QQ_VERSIONS_FILE}" >/dev/null || die "QQ 版本列表格式无效"
}

select_qq_package() {
    prepare_qq_versions_file
    local matches="${WORKDIR}/qq-matches.json"
    jq --arg arch "${DETECTED_ARCH}" --arg format "${PACKAGE_FORMAT}" '
        [.packages[]
         | select(.arch == $arch and .format == $format)
         | select(.available != false)]
        | sort_by(.update_time) | reverse
    ' "${QQ_VERSIONS_FILE}" > "${matches}"
    [[ "$(jq 'length' "${matches}")" -gt 0 ]] || die "版本列表中没有 ${DETECTED_ARCH}/${PACKAGE_FORMAT} 的 QQ 包"
    SELECTED_QQ_VERSION="$(jq -r '.[0].version' "${matches}")"
    SELECTED_QQ_FILENAME="$(jq -r '.[0].filename' "${matches}")"
    SELECTED_QQ_URL="$(jq -r '.[0].url' "${matches}")"
    SELECTED_QQ_SHA256="$(jq -r '.[0].sha256 // empty' "${matches}")"
    log "已按命令检测结果选择 QQ ${SELECTED_QQ_VERSION}: ${SELECTED_QQ_FILENAME}"
}

download_file() {
    local url="$1" destination="$2" minimum_size="$3"
    log "下载: ${url}"
    rm -f "${destination}"
    curl -fL --connect-timeout 20 --max-time 900 --retry 3 --retry-delay 2 "${url}" -o "${destination}" || return 1
    is_large_enough "${destination}" "${minimum_size}" || { rm -f "${destination}"; return 1; }
}

download_gitee_napcat() {
    local destination="$1"
    if download_file "${GITEE_NAPCAT_URL}" "${destination}" "${NAPCAT_MIN_SIZE}"; then
        return 0
    fi

    # Gitee may deny raw requests for large files. Its repository archive is a
    # signed Gitee download URL and contains the same tracked package.
    local archive="${WORKDIR}/downloads/gitee-repository.zip"
    log "Gitee 单文件下载失败，尝试 Gitee 仓库归档直链。"
    if ! download_file "${GITEE_REPOSITORY_ARCHIVE_URL}" "${archive}" 0; then
        return 1
    fi
    rm -f "${destination}"
    unzip -p "${archive}" '*/packages/NapCat.Shell.zip' > "${destination}" || return 1
    is_large_enough "${destination}" "${NAPCAT_MIN_SIZE}" || { rm -f "${destination}"; return 1; }
}

download_missing_packages() {
    mkdir -p "${WORKDIR}/downloads"
    if [[ -z "${QQ_PACKAGE}" ]]; then
        select_qq_package
        QQ_PACKAGE="${WORKDIR}/downloads/${SELECTED_QQ_FILENAME}"
        # QQ packages are published by Tencent. The link comes from data/qq_versions.json.
        download_file "${SELECTED_QQ_URL}" "${QQ_PACKAGE}" "${QQ_MIN_SIZE}" || die "QQ 下载失败"
        if [[ -n "${SELECTED_QQ_SHA256}" ]] && need_cmd sha256sum; then
            [[ "$(sha256sum "${QQ_PACKAGE}" | awk '{print $1}')" == "${SELECTED_QQ_SHA256}" ]] || die "QQ SHA256 校验失败"
        fi
    fi
    if [[ -z "${NAPCAT_PACKAGE}" ]]; then
        NAPCAT_PACKAGE="${WORKDIR}/downloads/NapCat.Shell.zip"
        if [[ "${DOWNLOAD_MODE}" == "gitee" ]]; then
            download_gitee_napcat "${NAPCAT_PACKAGE}" || die "NapCat 的 Gitee 下载失败"
        else
            download_file "${DIRECT_NAPCAT_URL}" "${NAPCAT_PACKAGE}" "${NAPCAT_MIN_SIZE}" || die "NapCat 下载失败"
        fi
    fi
}

install_qq() {
    log "安装 QQ: ${QQ_PACKAGE}"
    mkdir -p "${INSTALL_BASE_DIR}"
    if [[ "${PACKAGE_FORMAT}" == "deb" ]]; then
        dpkg -x "${QQ_PACKAGE}" "${INSTALL_BASE_DIR}"
    else
        rpm2cpio "${QQ_PACKAGE}" | (cd "${INSTALL_BASE_DIR}" && cpio -idm)
    fi
    [[ -f "${QQ_PACKAGE_JSON_PATH}" ]] || die "QQ 解压失败，未找到 ${QQ_PACKAGE_JSON_PATH}"
    [[ -x "${QQ_EXECUTABLE}" ]] || chmod +x "${QQ_EXECUTABLE}" 2>/dev/null || true
}

install_napcat() {
    log "安装 NapCat: ${NAPCAT_PACKAGE}"
    unzip -t "${NAPCAT_PACKAGE}" >/dev/null || die "NapCat 压缩包无效"
    local extract_dir="${WORKDIR}/napcat"
    mkdir -p "${extract_dir}"
    unzip -q -o "${NAPCAT_PACKAGE}" -d "${extract_dir}"
    local source_dir="${extract_dir}"
    [[ -d "${extract_dir}/NapCat" ]] && source_dir="${extract_dir}/NapCat"
    [[ -f "${source_dir}/napcat.mjs" ]] || die "NapCat 压缩包中未找到 napcat.mjs"
    mkdir -p "${NAPCAT_DIR}"
    cp -a "${source_dir}/." "${NAPCAT_DIR}/"
    chmod -R +x "${NAPCAT_DIR}" || true
    printf "(async () => { await import('file://%s/napcat.mjs'); })();\n" "${NAPCAT_DIR}" > "${QQ_BASE_PATH}/resources/app/loadNapCat.js"
    jq '.main = "./loadNapCat.js"' "${QQ_PACKAGE_JSON_PATH}" > "${WORKDIR}/package.json"
    mv "${WORKDIR}/package.json" "${QQ_PACKAGE_JSON_PATH}"
}

install_start_command() {
    local command_dir="${HOME}/.local/bin"
    mkdir -p "${command_dir}"
    NAPCAT_CMD_PATH="${command_dir}/napcat"
    cat > "${NAPCAT_CMD_PATH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
QQ_BIN="${QQ_EXECUTABLE}"
if command -v xvfb-run >/dev/null 2>&1; then
    exec xvfb-run -a "\${QQ_BIN}" --no-sandbox "\$@"
fi
exec "\${QQ_BIN}" --no-sandbox "\$@"
EOF
    chmod 755 "${NAPCAT_CMD_PATH}"
}

show_summary() {
    printf '\n安装完成。\n'
    printf '安装位置: %s\n' "${INSTALL_BASE_DIR}"
    printf '启动命令: %s\n' "${NAPCAT_CMD_PATH}"
    printf '若 ~/.local/bin 已在 PATH 中，可直接运行: napcat\n'
}

main() {
    detect_package_platform
    mkdir -p "${PACKAGE_DIR}"
    find_local_qq_package || true
    find_local_napcat_package || true
    [[ -n "${QQ_PACKAGE}" ]] && log "检测到本地 QQ 包: ${QQ_PACKAGE}" || log "未检测到本地 QQ 包（>${QQ_MIN_SIZE} 字节）"
    [[ -n "${NAPCAT_PACKAGE}" ]] && log "检测到本地 NapCat 包: ${NAPCAT_PACKAGE}" || log "未检测到本地 NapCat 包（>${NAPCAT_MIN_SIZE} 字节）"

    if [[ -z "${QQ_PACKAGE}" || -z "${NAPCAT_PACKAGE}" ]]; then
        choose_download_mode
        if [[ "${DOWNLOAD_MODE}" == "manual" ]]; then
            # Manual mode only reports and exits; it never waits for an in-place upload.
            find_local_qq_package || true
            find_local_napcat_package || true
            if [[ -z "${QQ_PACKAGE}" || -z "${NAPCAT_PACKAGE}" ]]; then
                show_manual_import_guide
                exit 0
            fi
        else
            ensure_dependencies
            download_missing_packages
        fi
    else
        log "本地安装包齐全，跳过下载。"
    fi

    ensure_dependencies
    install_qq
    install_napcat
    install_start_command
    show_summary
}

main "$@"
