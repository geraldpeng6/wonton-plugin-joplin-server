# 笔记同步（Joplin Server）

像有道云笔记，把手机和电脑上的 Joplin 笔记存到家里，换设备接着写。网页是账号管理页，写笔记用免费的 [Joplin 应用](https://joplinapp.org)。

开发流程见[插件开发指南](https://github.com/wontonapp/wonton-docs/blob/main/develop.md)。

## 用法

1. 在云吞的插件详情里查看“Joplin 初始密码”，用 `admin@localhost` 登录插件网页。可以在 Joplin 管理页修改邮箱、密码或创建普通账号。
2. 在手机或电脑上安装 Joplin，在云吞里打开这个应用的客户端入口，复制显示的地址。
3. 在 Joplin 的“设置 → 同步”选择“Joplin Server”，填写地址和自己的 Joplin 账号、密码，点“检查同步配置”。

云吞只显示客户端地址，不代替 Joplin 管理账号。改过初始密码后，插件详情里的值不会跟着变；使用自己改过的密码。

## 地址与账号

- 使用上游官方 `joplin/server:3.7.5` 和 `postgres:16.15`，均按清单列表摘要固定，不修改上游源码。
- `APP_BASE_URL` 使用核心注入的 `WONTON_EXTERNAL_URL`；`clients.http.single_host: true` 让各入口转发给 Joplin 的 `Host` 与规范地址一致。入口开关改变地址时，由核心重建应用。
- Joplin 3.7.5 的 `API_BASE_URL`、`USER_CONTENT_BASE_URL` 不设时都使用 `APP_BASE_URL`，无需第二个域名或子路径。上游的[配置定义](https://github.com/laurent22/joplin/blob/server-v3.7.5/packages/server/src/config.ts)和[分享地址检查](https://github.com/laurent22/joplin/blob/server-v3.7.5/packages/server/src/models/ShareModel.ts)均支持同址；不把页面里出现的两个配置项当成必须两个入口。
- 初始管理员密码经上游 `DEFAULT_ADMIN_PASSWORD` 设置，来自核心生成的 `client` 密钥。后续重建不覆盖用户修改过的账号。自助注册显式关闭。
- 客户端入口用 `auth.app`，由 Joplin 自己验证邮箱和密码。`setup-done.js` 使用镜像自带的 PostgreSQL 驱动和密码比较函数，只读确认已存在启用的管理员且没有管理员仍用 `admin` 密码；数据库不可用返回“不确定”，不放行入口。
- 管理页和分享内容共用一个来源，没有独立域名隔离。给别人分享笔记前确认内容确实可以公开；只在家里打开入口时，外面的人不能访问分享链接。
- 找回密码和邀请邮件经云吞的信箱发送，只收发给家里人的内部邮箱。初始 `admin@localhost` 不能收这类信；需要时先在 Joplin 中设成自己的云吞内部邮箱。
- 容器使用宿主机时钟，按上游支持的 `MAX_TIME_DRIFT=0` 关闭插件网络内不可达的 NTP 探测，不额外申请出网权限。

## 数据

笔记、账号和同步状态都在应用数据目录的 `postgres/`。备份时先停止插件再复制整个目录，或使用 PostgreSQL 的 `pg_dump`；运行中直接复制可能不一致。PostgreSQL 大版本升级需要手动迁移，依赖更新配置不自动跨大版本。

## 许可证

Joplin Server 使用 [Joplin Server Personal Use License](https://github.com/laurent22/joplin/blob/server-v3.7.5/packages/server/LICENSE.md)，限个人非商业用途，不是开源许可证。安装和使用前由主人自行阅读并决定是否接受；本插件不代为接受许可。Joplin 客户端是开源的。

## 验证

`scripts/smoke-probes.sh` 验证登录页、管理员 API 会话、网页表单登录，以及真实 Joplin 笔记的上传和读取。数据探针用于套件的升级与重装保数据检查；未声明 MCP 工具。

## 图标

`icon.svg` 原样使用 [Joplin 官方标志](https://github.com/laurent22/joplin/blob/server-v3.7.5/Assets/JoplinIcon.svg)，来源、版权、许可全文和商标说明见 [NOTICE](NOTICE)。Joplin 名称和标志属于上游，本插件不代表官方合作或背书。
