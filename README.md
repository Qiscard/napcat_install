# napcat_install

精简版 NapCat Linux 安装脚本（Rootless Shell + 官方 TUI-CLI）。

## 拉取安装

```bash
git clone https://github.com/Qiscard/napcat_install.git
cd napcat_install
bash install.sh
```

本机已有仓库：

```bash
cd /root/napcat_install
git pull
bash install.sh
```

在线一键：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Qiscard/napcat_install/main/install.sh)
```

GitHub 较慢时：

```bash
bash <(curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/Qiscard/napcat_install/main/install.sh)
```

> 克隆安装会优先使用仓库内置 `packages/NapCat.Shell.zip`；在线一键若无本地包，则自动从 GitHub 下载。

## 安装时选项（10 秒超时，默认自动确认）

| 选项 | 默认 | 说明 |
|------|------|------|
| 包格式 | 自动识别 | 可选 deb / rpm |
| 下载方式 | 直连 | 可选 `https://ghproxy.net/`（仅 GitHub） |
| QQ 版本 | 最新 | 可输入序号选择最近 15 个版本 |
| TUI-CLI | 安装 | 官方终端管理界面 |

## 装完后

```bash
napcat
```

打开官方 TUI 管理界面。也可：

```bash
xvfb-run -a ~/Napcat/opt/QQ/qq --no-sandbox
```

## 安装位置

| 路径 | 说明 |
|------|------|
| `~/Napcat` | 安装根目录 |
| `~/Napcat/opt/QQ` | LinuxQQ |
| `~/Napcat/opt/QQ/resources/app/app_launcher/napcat` | NapCat 插件 |
| `/usr/local/bin/napcat` | TUI 命令（或 `~/.local/bin/napcat`） |

## 基本功能

- Rootless 安装 LinuxQQ + NapCat
- 内置 `packages/NapCat.Shell.zip`（优先本地，失败再联网）
- 校验并选择可用 QQ deb/rpm 版本
- 默认安装 [NapCat-TUI-CLI](https://github.com/NapNeko/NapCat-TUI-CLI)
- 检测已有 `~/Napcat`，可覆盖或退出
- 每周同步 `data/qq_versions.json`

## 目录

```text
napcat_install/
├── install.sh
├── packages/NapCat.Shell.zip
├── data/qq_versions.json
└── scripts/sync_qq_versions.py
```
