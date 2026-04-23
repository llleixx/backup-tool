# 备份工具 (Backup Tool)

这是一个基于 `restic` 的**备份和通知管理**脚本，旨在简化和自动化备份配置流程。它通过一个交互式的命令行菜单，帮助你快速设置备份任务、管理保留策略以及通知任务，并自动生成对应的 `systemd` 服务和定时器，实现**自动化备份**和**成功 / 失败通知**。

[Restic](https://restic.readthedocs.io/en/stable/) 是一个开源、多平台的备份工具，相比常见的使用 `rclone` 同步文件备份方案有以下优点：

- `restic` 能够方便地**备份多个文件**（从文件中读取需要备份的路径）
- `restic` 会对备份文件进行**压缩**
- `restic` 支持**版本控制**（每次备份都是一个快照）
- `restic` 备份文件默认是**加密**的（密码也可以留空，但一般不建议）
- `restic` 是**多平台**的，Windows 也能使用

推荐搭配 [rclone](https://rclone.org/) 使用，[简单教程](https://lllei.top/2025/09/18/backup-tool/)。

## ✨ 主要功能

- **交互式菜单**：通过一个清晰的 CLI 菜单管理备份和通知配置。
- **自动化调度**：自动创建和管理 `systemd` 服务和定时器，根据 `OnCalendar` 表达式执行定时备份。
- **多配置管理**：支持同时管理多个独立的备份任务和通知任务。
- **灵活的后端**：通过 `restic` 和 `rclone`，支持将数据备份到**本地、SFTP 或各种主流云存储服务（如 S3, Google Drive, Dropbox 等）**。
- **备份保留策略**：轻松定义快照保留策略，例如保留最近 7 天的每日备份和最近 4 周的每周备份。
- **状态通知**：支持通过 **Telegram** 和 **Email** 发送备份成功或失败通知。
- **交互式恢复**：可以直接从菜单中选择快照并恢复到指定目录。
- **rclone 安装**：在高级菜单中提供 `rclone` 安装。
- **自动配置迁移**：旧版本配置会在启动时自动迁移到新格式，无需手动处理。

![面板](https://img.lllei.top/i/2025/09/22/093741-0.webp)

![rclone 安装](https://img.lllei.top/i/2025/09/22/093801-0.webp)

![telegram](https://img.lllei.top/i/2025/09/22/095614-0.webp)

![Email](https://img.lllei.top/i/2025/09/22/095244-0.webp)

## 📋 环境要求

- 一个支持 **systemd** 的 Linux 发行版（如 Debian、Ubuntu、CentOS、Fedora 等）
- **root** 权限，用于安装和管理 `systemd` 服务

## 🚀 安装

使用以下一键安装命令即可完成安装。脚本会自动处理依赖项、设置目录并创建 `systemd` 通知服务。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/llleixx/backup-tool/main/install.sh)
```

安装脚本会执行以下操作：

1. 检查 `root` 权限和 `systemd` 环境。
2. 自动检测包管理器并安装所需依赖：`msmtp`、`jq`、`curl`、`bzip2`。
3. 通过 GitHub Release API 下载并安装最新 `restic` 到 `/usr/local/bin/restic`。
4. 从 GitHub 下载最新版本的脚本文件到 `/opt/backup`。
5. 设置 `systemd` 模板服务，用于发送成功 / 失败通知。
6. 创建软链接，让你可以在任意路径下通过 `but` 或 `backup-tool` 命令运行主程序。

安装完成后，直接运行：

```bash
backup-tool
```

如果你之前装过旧版本，重新运行 `install.sh` 即可完成升级；旧配置会在脚本启动时自动迁移。

## 🛠️ 使用方法

安装完成后，直接在终端中运行 `backup-tool` 或 `but` 即可打开菜单页面。

主菜单顶部会显示当前已有的**备份配置数量**和**通知配置数量**，方便快速确认当前状态。

### 备份

**配置生成、编辑和删除应由脚本完成，请勿手动更改。**

一般情况下，通过菜单新增或修改备份后，脚本会自动应用到 `systemd`，无需手动再执行“应用备份”。

主菜单中的**应用备份**主要用于以下场景：

- 你手动迁移了配置文件
- 你手动改动了 `/opt/backup/conf/` 下的配置（不推荐）
- 你希望重新生成对应的 `systemd` 单元文件

高级菜单中提供：

- **立即备份**：立即触发一次备份任务
- **恢复备份**：从已有快照恢复到指定目录

立即备份触发后，可以使用以下命令查看实时日志：

```bash
journalctl -u backup-xxxx.service -f
```

一个备份配置包含以下参数：

配置项|示例|描述
---|---|---
`BACKUP_FILES_LIST`|`/opt/backup/backup_list.txt`|该文件指定所有需要备份的文件路径，每行一个路径
`RESTIC_REPOSITORY`|`rclone:remote:backup-host`|示例为指定 rclone 的名为 remote 的后端作为存储，将后端的 `backup-host` 作为备份目录
`RESTIC_PASSWORD`|`123`|指定仓库密码，可为空
`ON_CALENDAR`|`*-*-* 01:30:00 Asia/Shanghai`|UTC+8 时区，每日凌晨 01:30:00 备份（会有随机 15 分钟内延迟）
`KEEP_DAILY`|`7`|在过去 7 天内，每天保留一个最新快照
`KEEP_WEEKLY`|`4`|在过去 4 周内，每周保留一个最新快照
`GROUP_BY`|`tags`|`restic` 备份时父镜像选择依据，默认为 `tags`，当前脚本不提供修改入口
`PRE_BACKUP_HOOK`|`/opt/backup/hooks/pre.sh`|备份开始前执行的脚本路径（可留空）
`POST_SUCCESS_HOOK`|`/opt/backup/hooks/success.sh`|备份成功后执行的脚本路径（可留空）
`POST_FAILURE_HOOK`|`/opt/backup/hooks/failure.sh`|备份失败后执行的脚本路径（可留空）

### 通知

**通知配置同样应由脚本完成管理，请勿手动更改。**

高级菜单中包含**测试通知**选项，建议配置完成后先测试一遍。

#### Telegram

配置项|示例|描述
---|---|---
`NOTIFY_TYPE`|`telegram`|Telegram 类型
`NOTIFY_ON_SUCCESS`|`true`|当备份成功时使用该通知
`NOTIFY_ON_FAILURE`|`true`|当备份失败时使用该通知
`TELEGRAM_BOT_TOKEN`|`3283018834:XXXX...`|Telegram Bot Token，通过 @BotFather 生成
`TELEGRAM_CHAT_ID`|`5322534137`|接收通知的聊天 ID，可通过向 @userinfobot 发送 `/start` 获取

#### Email

配置项|示例|描述
---|---|---
`NOTIFY_TYPE`|`email`|Email 类型
`NOTIFY_ON_SUCCESS`|`true`|当备份成功时使用该通知
`NOTIFY_ON_FAILURE`|`true`|当备份失败时使用该通知
`SMTP_HOST`|`smtp.gmail.com`|SMTP 服务器地址
`SMTP_PORT`|`587`|SMTP 服务器端口
`SMTP_USER`|`xx@gmail.com`|发件人邮箱地址或用户名
`SMTP_PASS`|`xxx`|发件人邮箱密码 / App Password
`FROM_ADDR`|`xx@gmail.com`|发件人地址，一般与用户名相同
`TO_ADDR`|`yy@gmail.com,xx@outlook.com`|收件人地址，多个用逗号分隔
`SMTP_TLS`|`starttls`|TLS 设置，可选 `starttls`、`on`、`off`

通常：

- `SMTP_PORT` 为 `587` 或 `25` 时，`SMTP_TLS` 常设置为 `starttls`
- `SMTP_PORT` 为 `465` 时，`SMTP_TLS` 常设置为 `on`

具体以你的 SMTP 服务商要求为准。

## 📁 目录结构

所有相关文件和配置都存储在 `/opt/backup` 目录下：

- `/opt/backup/backup-tool.sh`：主执行脚本
- `/opt/backup/conf/`：存放所有 `backup-*.conf` 和 `notify-*.conf` 配置文件
- `/opt/backup/lib/`：存放核心功能脚本

其中 `/opt/backup/conf/` 下的配置文件由脚本自动维护。当前版本会将配置保存为更安全的新格式，旧版本配置会在启动时自动迁移。

## 🔄 更新与卸载

### 更新脚本

在高级菜单中选择：

- **更新脚本**

脚本会下载最新版本并重新启动主程序。

### 卸载

在主菜单中选择：

- **卸载**

卸载会删除脚本目录、配置文件以及相关 `systemd` 单元，请谨慎操作。

## 🔧 依赖项

以下依赖会在安装过程中自动安装：

- **restic (>= 0.17.0)**：核心备份工具，通过 GitHub Release 自动安装到 `/usr/local/bin/restic`
- **msmtp**：用于发送 Email 通知
- **jq**：用于解析 JSON 数据
- **curl**：用于下载脚本和发送 Telegram 通知
- **bzip2**：用于解压 `restic` 的 release 二进制包

推荐使用 [rclone](https://rclone.org/) 作为仓库存储。

## 📌 补充说明

- `restic` 现在不再依赖系统仓库版本，而是直接从 GitHub Release 安装，因此在 Ubuntu 24.04 这类环境下也能正常获得完整功能。
- 如果你的 `restic` 版本过低，重新运行 `install.sh` 即可完成更新。
- 支持同时管理多个备份配置和多个通知配置。
- 恢复功能会列出可用快照，并在恢复前再次确认，避免误覆盖文件。
