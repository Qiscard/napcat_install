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

## 资源获取方式

安装时二选一（10 秒超时，默认 1）：

1. **直连下载**（默认）
2. **手动导入安装包**

### 手动导入

把文件放到：

```text
<仓库目录>/packages/
# 克隆安装时一般是:
./packages/
# 或
/root/napcat_install/packages/
```

| 文件 | 格式 | 文件名/规则 | 说明 |
|------|------|-------------|------|
| NapCat | `.zip` | `NapCat.Shell.zip`（固定） | 必需 |
| LinuxQQ | `.deb` 或 `.rpm` | `QQ_*.deb` / `QQ_*.rpm`，或 `QQ.deb` / `QQ.rpm` | 必需，与系统包格式一致 |
| 校验（可选） | 文本 | `NapCat.Shell.zip.sha256` | 可选 |

准备就绪后：

```bash
# 若还没运行安装脚本
cd /root/napcat_install   # 按实际路径
bash install.sh
# 选择: 2) 手动导入
# 按提示放好文件后，在安装终端直接回车继续
```

也可先放好再装：

```bash
mkdir -p /root/napcat_install/packages
# 上传 NapCat.Shell.zip 与 QQ deb/rpm 到该目录
ls -lah /root/napcat_install/packages
cd /root/napcat_install && bash install.sh
```

## 装完后

```bash
napcat
```

## 安装位置

| 路径 | 说明 |
|------|------|
| `~/Napcat` | 安装根目录 |
| `~/Napcat/opt/QQ` | LinuxQQ |
| `~/Napcat/opt/QQ/resources/app/app_launcher/napcat` | NapCat |
| `/usr/local/bin/napcat` | TUI 命令 |

## 基本功能

- Rootless 安装 LinuxQQ + NapCat
- 直连下载 或 手动导入
- 可选官方 TUI-CLI（`napcat` 终端界面）
- QQ 版本列表 + 已有目录检测
