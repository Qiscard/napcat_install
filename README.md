# napcat_install

LinuxQQ 与 NapCat 的无 root 安装脚本。脚本根据 `dpkg` 或 `rpm` 命令检测包格式和系统架构，不提供架构自定义选项。

## 拉取安装

```bash
git clone https://github.com/Qiscard/napcat_install.git
cd napcat_install
bash install.sh
```

已有仓库时：

```bash
cd /root/napcat_install
git pull
bash install.sh
```

## 一键脚本

GitHub 版本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Qiscard/napcat_install/main/install.sh)
```

Gitee 版本：

```bash
bash <(curl -fsSL https://gitee.com/qiscard/napcat_install/raw/main/install.sh)
```

脚本会先检查 `packages/` 内的安装包。QQ 包大于 100 MB、`NapCat.Shell.zip` 大于 20 MB 时视为存在，存在的包会跳过下载。缺包时可选择：

1. 直连下载：按直链顺序下载缺失包。
2. Gitee 下载：使用 Gitee 的 NapCat 直链下载缺失的 NapCat 包；QQ 仍使用版本列表中的腾讯官方直链。
3. 手动导入：检查目标位置；缺包时输出文件格式与位置，并提示“导入成功后重新运行手动模式”后结束运行。

可用环境变量跳过交互：`NAPCAT_INSTALL_MODE=direct`、`NAPCAT_INSTALL_MODE=gitee` 或 `NAPCAT_INSTALL_MODE=manual`。

## 手动导入注意事项

将文件放到仓库的 `packages/` 目录：

```text
<仓库目录>/packages/
```

| 文件 | 命名格式 | 大小要求 |
| --- | --- | --- |
| LinuxQQ | `QQ*.deb` 或 `QQ*.rpm`，与检测到的包格式一致 | 大于 100 MB |
| NapCat | `NapCat.Shell.zip`（固定文件名） | 大于 20 MB |

示例：

```bash
mkdir -p /root/napcat_install/packages
# 上传 QQ*.deb 或 QQ*.rpm 与 NapCat.Shell.zip 到该目录
cd /root/napcat_install
NAPCAT_INSTALL_MODE=manual bash install.sh
```

包齐全后，脚本会直接安装；缺包时会显示存放目录和命名格式，并结束运行。

## 启动命令

安装完成后执行：

```bash
napcat
```

脚本会将启动命令安装到 `~/.local/bin/napcat`。若该目录不在 `PATH` 中，可执行：

```bash
~/.local/bin/napcat
```

## 安装位置

| 路径 | 说明 |
| --- | --- |
| `~/Napcat` | 安装根目录 |
| `~/Napcat/opt/QQ` | LinuxQQ |
| `~/Napcat/opt/QQ/resources/app/app_launcher/napcat` | NapCat |
| `~/.local/bin/napcat` | 启动命令 |
