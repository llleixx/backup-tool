# 备份工具 (Backup Tool)

这是一个基于 `restic` 的**备份和通知管理**脚本，旨在简化和自动化备份配置流程。它通过一个交互式的命令行菜单，帮助用户快速设置备份任务、管理保留策略以及通知任务，并自动生成相应的 `systemd` 服务和定时器，实现**自动化备份和成功或者失败通知**。

[Restic](https://restic.readthedocs.io/en/stable/) 是一个开源、多平台的备份工具，相比常见的使用 `rclone` 同步文件备份方案有以下优点：

- `restic` 能够方便地**备份多个文件**（从文件中读取需要备份的路径）
- `restic` 会对备份文件进行**压缩**
- `restic` 支持**版本控制**（每次备份都是一个快照）
- `restic` 备份文件是**加密**的（当然密码也可以设置为空），即使是共享云端存储空间，别人也不会知道内容（当然即使这样也不推荐）
- `restic` 是**多平台**的，Windows 也能使用

推荐搭配 [rclone](https://rclone.org/) 使用，[简单教程](https://lllei.top/2025/09/18/backup-tool/)。

## ✨ 主要功能

- **交互式菜单**：提供一个简单易用的命令行菜单，用于**管理配置和通知**。
- **自动化调度**：自动创建和管理 `systemd` 服务和定时器，根据用户定义的 `OnCalendar` 表达式执行定时备份。
- **多配置管理**：支持同时管理**多个**独立的**备份任务**和**通知任务**。
- **灵活的后端**：通过 `restic` 和 `rclone`，支持将数据备份到**本地、SFTP 或各种主流云存储服务（如 S3, Google Drive, Dropbox 等）**。
- **备份保留策略**：轻松定义**快照的保留策略**（例如，保留最近 7 天的每日备份和最近 4 周的每周备份）。
- **状态通知**：支持通过 **Telegram** 和 **Email** 发送备份成功或失败的通知。
- **交互式恢复**：提供安全的**交互式恢复**流程，允许从指定的快照恢复数据到任意路径。
- **rclone 安装**：在高级菜单中提供 `rclone` 安装。

<img width="565" height="520" alt="image" src="https://github.com/user-attachments/assets/d2ba64d7-b9a2-40f7-90c0-8a2a0ab78a8b" />

<img width="594" height="358" alt="image" src="https://github.com/user-attachments/assets/87ffad58-ce50-4be2-b311-6c78f176156c" />

## 📋 环境要求

- 一个支持 **systemd** 的 Linux 发行版（如 Debian, Ubuntu, CentOS, Fedora 等）。
- **root** 权限，用于安装和管理 `systemd` 服务。

## 🚀 安装

使用以下一键安装命令即可完成安装。脚本会自动处理依赖项、设置目录和创建 `systemd` 通知服务。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/llleixx/backup-tool/master/install.sh)
```

安装脚本会执行以下操作：

1. 检查 `root` 权限和 `systemd` 环境。
2. 自动检测包管理器并安装所需依赖：`restic`, `msmtp`, `jq`, `curl`。
3. 从 GitHub 下载最新的脚本文件到 `/opt/backup` 目录。
4. 设置 `systemd` 模板服务，用于发送成功 / 失败通知。
5. 创建软链接，让您可以在任意路径下通过 `but` 或 `backup-tool` 命令运行主程序。

## 🛠️ 使用方法

安装完成后，直接在终端中运行 `backup-tool` 或者 `but` 即可打开菜单页面。

### 备份

**配置生成、编辑以及删除应由脚本完成，请勿手动更改。**

主菜单中的**应用脚本**：当你手动修改脚本（不推荐）或者**配置文件迁移**（但是请不要两台机器**同时使用**一份配置（指配置的 `CONFIG_ID` 相同））时，需要调用**应用脚本**来让系统服务与配置同步。

高级菜单中提供**立即备份**选项。

一个备份配置包含以下参数：

配置项|示例|描述
---|---|---
`BACKUP_FILES_LIST`|`/opt/backup/backup_list.txt`|该文件指定所有需要备份的文件路径
`RESTIC_REPOSITORY`|`rclone:remote:backup-host`|示例为指定 rclone 的名为 remote 的后端作为存储，将后端的 `backup-host` 作为备份文件夹
`RESTIC_PASSWORD`|`123`|指定仓库密码，可为空
`ON_CALENDAR`|`*-*-* 01:30:00 Asia/Shanghai`|UTC+8 时区，每日凌晨 01:30:00 备份（会有随机 15min 内的时延）
`KEEP_DAILY`|`7`|在过去 7 天内，每天保留一个最新的快照
`KEEP_WEEKLY`|`4`|在过去 4 周内，每周保留一个最新的快照
`GROUP_BY`|`tags`|`restic` 备份时父镜像选择依据，默认为 `tags`，目前使用该脚本不能修改该选项

### 通知

**配置生成、编辑以及删除应由脚本完成，请勿手动更改。**

高级菜单中包含**通知测试**选项。

#### Telegram

配置项|示例|描述
---|---|---
`NOTIFY_TYPE`|`telegram`|telegram 类型
`NOTIFY_ON_SUCCESS`|`true`|当备份成功时使用该通知
`NOTIFY_ON_FAILURE`|`true`|当备份失败时使用该通知
`TELEGRAM_BOT_TOKEN`|`3283018834:XGGvsn1j-tK56yu0vZp5qJq1JVh_iGt2B7q`|Telegram Bot Token，通过 @BotFather 生成
`TELEGRAM_CHAT_ID`|`5322534137`|接受通知的聊天 ID，可以通过向 @userinfobot 发送 `/start` 获得

#### Email

配置项|示例|描述
---|---|---
`NOTIFY_TYPE`|`email`|email 类型
`NOTIFY_ON_SUCCESS`|`true`|当备份成功时使用该通知
`NOTIFY_ON_FAILURE`|`true`|当备份失败时使用该通知
`SMTP_HOST`|`smtp.gmail.com`|SMTP 服务器地址
`SMTP_PORT`|`587`|SMTP 服务器端口
`SMTP_USER`|`xx@gmail.com`|发件人邮箱地址
`SMTP_PASS`|`xxx`|发件人邮箱密码
`FROM_ADDR`|`xx@gmail.com`|和发件人邮箱地址相同即可
`TO_ADDR`|`yy@gmail.com,xx@outlook.com`|收件人地址（多个用逗号分隔）
`SMTP_TLS`|`starttls`|TLS 设置，选项有 `starttls`，`on` 以及 `off`

`SMTP_PORT` 为 587 或 25 时，`SMTP_TLS` 常设置为 `starttls`，`SMTP_PORT` 为 465 时，`SMTP_TLS` 常设置为 `on`，具体依据各自 SMTP 服务器而定。

## 📁 目录结构

所有相关文件和配置都存储在 `/opt/backup` 目录下：

- `/opt/backup/backup-tool.sh`：主执行脚本。
- `/opt/backup/conf/`：存放所有 `backup-*.conf` 和 `notify-*.conf` 配置文件。**请勿手动修改这些文件，应使用脚本菜单进行管理。**
- `/opt/backup/lib/`：存放核心功能的脚本。

## 🔧 依赖项

以下依赖会在安装过程中自动安装：

- **restic (>= 0.17.0)**：核心备份工具。
- **msmtp**：用于发送 Email 通知。
- **jq**：用于解析 JSON 数据。
- **curl**：用于下载脚本和发送 Telegram 通知。

推荐使用 [rclone](https://rclone.org/) 作为仓库存储。
