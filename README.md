# napcat_install

精简版 [NapCat](https://github.com/NapNeko/NapCatQQ) Linux 安装脚本。

基于 [NapCat-Installer](https://github.com/NapNeko/NapCat-Installer) 改造：移除 Docker / TUI / 多节点测速等逻辑，保留 Rootless Shell 安装主流程。

## 特性

- 交互式选择（均 10 秒超时，超时用默认值）
  - 下载方式：默认直连，可选 `https://ghproxy.net/` 代理（仅 GitHub 资源）
  - 系统包格式：默认自动识别，可选 Ubuntu/Debian (deb) 或 Fedora/RHEL (rpm)
  - QQ 版本：默认最新，可输入序号选择最近 15 个版本
- 安装前检测 `~/Napcat`，可选择覆盖或退出
- 默认安装官方 NapCat TUI-CLI：输入 `napcat` 进入终端管理界面
- 日志明确输出：下载链接、保存路径、安装路径、架构、校验信息
- QQ 版本列表来自 [qq-versions](https://rodert.github.io/qq-versions/) / [Releases](https://github.com/Rodert/qq-versions/releases) 与官方配置，仓库每周自动同步

## 快速开始

```bash
git clone https://github.com/Qiscard/napcat_install.git
cd napcat_install
bash install.sh
```

或：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Qiscard/napcat_install/main/install.sh)
```

> 在线一键执行时，若仓库内没有本地 `data/qq_versions.json`，脚本会尝试从本仓库 raw 地址拉取版本列表。

## 目录结构

```text
napcat_install/
├── install.sh                 # 安装脚本
├── data/qq_versions.json      # QQ 版本列表（更新时间/版本/链接/架构/sha256/md5）
├── scripts/sync_qq_versions.py
└── .github/workflows/sync-qq-versions.yml
```

## 版本列表同步

手动同步（拉取后会校验链接，自动剔除失效项）：

```bash
python3 scripts/sync_qq_versions.py
```

GitHub Actions 默认每周一自动运行并提交 `data/qq_versions.json`。

安装时也会对所选 QQ 下载链接做预检；若失效，会自动在同架构/格式的可用版本中回退。

列表字段说明：

| 字段 | 含义 |
|------|------|
| update_time / update_date | 更新时间 |
| version | QQ 版本号 |
| arch | amd64 / arm64 / ... |
| format | deb / rpm |
| url | 下载链接 |
| sha256 / md5 | 校验值（有则填充） |
| filename / size / source | 文件名、大小、来源 |

## 安装位置

| 路径 | 说明 |
|------|------|
| `~/Napcat` | 安装根目录 |
| `~/Napcat/opt/QQ` | LinuxQQ |
| `~/Napcat/opt/QQ/resources/app/app_launcher/napcat` | NapCat 插件 |

启动：

安装时默认会安装官方 [NapCat-TUI-CLI](https://github.com/NapNeko/NapCat-TUI-CLI)。装完后：

```bash
napcat          # 打开终端管理界面 (dialog TUI)
```

官方文档: <https://napneko.github.io/guide/napcat>

等价原生命令：

```bash
xvfb-run -a ~/Napcat/opt/QQ/qq --no-sandbox
```

若跳过 TUI 或安装失败，会回退到简易 `napcat start|bg|stop|status` 命令。

## 说明

- 仅支持 Shell Rootless 安装
- 代理节点仅保留 `https://ghproxy.net/`
- QQ 安装包版权归腾讯；版本索引来自公开镜像与官方下载配置
