# napcat_install

NapCat Linux 安装脚本 (Rootless Shell + 官方 TUI-CLI)。

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

## 一键脚本

GitHub 版本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Qiscard/napcat_install/main/install.sh)
```

Gitee 版本：

```bash
bash <(curl -fsSL https://gitee.com/qiscard/napcat_install/raw/main/install.sh)
```

## 资源获取方式

安装时三选一（10 秒超时，默认 1）：

1. **直连下载**（默认）— 按直链顺序对缺失包进行安装
2. **Gitee 下载** — 按 Gitee 直链顺序对缺失包进行安装（网络因素选择此方案）
3. **手动导入** — 检测目标位置是否存在包（qq.deb > 100MB，napcat > 20MB 视为存在），存在则直接安装；否则输出缺失包命名格式/存放位置，并提示"导入成功后重新运行手动模式"后结束

### 手动导入注意事项

把文件放到：

```text
<仓库目录>/packages/
# 克隆安装时一般是:
./packages/
# 或
/root/napcat_install/packages/
```

| 文件 | 格式 | 文件名规则 | 大小要求 | 说明 |
|------|------|-----------|---------|------|
| NapCat | `.zip` | `NapCat.Shell.zip`（固定） | > 20MB | 必需 |
| LinuxQQ | `.deb` 或 `.rpm` | `QQ_*.deb` / `QQ_*.rpm`，或 `QQ.deb` / `QQ.rpm` | > 100MB | 必需，跟系统包格式一致 |

准备就绪后：

```bash
# 如果还没运行安装脚本
cd /root/napcat_install   # 按实际路径
bash install.sh
# 选择: 3) 手动导入
# 提示放好文件后，在终端直接回车继续
```

也可先放好再装：

```bash
mkdir -p /root/napcat_install/packages
# 上传 NapCat.Shell.zip 与 QQ deb/rpm 到该目录
ls -lah /root/napcat_install/packages
cd /root/napcat_install && bash install.sh
```

## 启动命令

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
- 直连下载 / Gitee 下载 / 手动导入
- 本地包检测（按大小判定），存在则跳过下载
- 可选官方 TUI-CLI（`napcat` 终端界面）
- QQ 版本列表 + 已有目录检查
