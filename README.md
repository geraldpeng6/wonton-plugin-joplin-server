# 云吞插件：笔记同步（Joplin Server）

开发流程见[插件开发指南](https://github.com/wontonapp/wonton-docs/blob/main/develop.md)。

Joplin 官方的同步服务端：手机、电脑上的 Joplin 笔记本把笔记同步到你家里的服务器，换设备接着写。
网页（经核心网关）是管理页，应用自带登录；Joplin 客户端连局域网端口 22300（`lan.client`，默认关，
在插件详情里打开"在局域网开放"后显示地址和账号）。

## 用法

1. 在手机或电脑上安装免费的 [Joplin](https://joplinapp.org) 应用。
2. 在云吞的插件详情里打开"在局域网开放"，复制显示的地址、账号和密码。
3. 在 Joplin 应用的 设置 → 同步 里选择"Joplin Server"，把地址、账号、密码填进去，点"检查同步配置"。

## 插件行为

- 两个服务：`server`（joplin/server，端口 22300）和 `db`（Postgres，数据卷在应用数据目录的 `postgres/`）。
  上游官方 compose 就是这两个服务；镜像按清单列表（index）摘要固定。
- 一次性 `provision` 服务：Joplin Server 首次启动自带默认管理员 `admin@localhost`/`admin`，
  不能留着。它调 Joplin 的 API（`POST /api/sessions`、`PATCH /api/users/:id`）把默认管理员的邮箱改成
  主人的内部邮箱、密码换成核心生成的密码——Joplin 客户端按邮箱+密码登录，改完的账号就是 `lan.client`
  显示的账号。脚本幂等：重装、重建容器时主人账号直接登录通过就跳过，改写没有生效会报错退出。
- `APP_BASE_URL` 用注入的网页地址（`WONTON_APP_URL`）：Joplin 的网页登录后会重定向到 `${APP_BASE_URL}/home`，
  写错网页登录回不来。Joplin 客户端的同步不读这个值（客户端直连局域网端口），两者地址不同不影响同步（实测见 PR）。
- 自助注册上游默认就关（`SIGNUP_ENABLED` 默认 false）；账号由一次性服务建，`lan.client` 显示给用户。
- 发信（找回密码、共享邀请）接核心的信箱（`notify` 权限）：`MAILER_*` 指向 `WONTON_SMTP_HOST/PORT`，
  `MAILER_SECURITY=none`（核心的 SMTP 不加密）；收件人只能是家里的人，外部地址会被拒收。
- 网页上能分享笔记出去的外链功能没有外部入口（分享链接指向网页地址，收件人没有云吞会话打不开）。

## 数据存在哪

- 笔记内容、账号都在 Postgres 里：应用数据目录的 `postgres/`（宿主机上）。没有别的数据目录。
- 备份：备份整个 `postgres/` 目录要先停止插件（或用 `pg_dump`），目录在服务运行时直接复制可能不一致。

## 已知限制

- Joplin Server 是 "Joplin Server Personal Use License"，只许个人使用，不是开源许可证（全文见
  [NOTICE](NOTICE)）；笔记数据本身在你自己的服务器上，客户端应用（Joplin）是开源的。
- 从外部网络（不在家里、也不经云吞的隧道）同步：需要自己把 22300 端口映射出去，本插件没有申请这个能力。
- Postgres 大版本升级要手动迁移数据（Dependabot 的配置里已忽略大版本）。

## 先跑起来

```bash
scripts/dev.sh up
scripts/dev.sh install
```

`up` 在本机起一套云吞并打印它的地址，用 `scripts/dev.sh token` 输出的用户令牌登录；`install` 列出插件要的
权限，确认后装上。打开插件网页是 Joplin 的登录页，用 `lan.client` 显示的账号（或改密码前的初始账号）
登录进管理页。

## 仓库里有什么

| 路径 | 内容 |
| --- | --- |
| `docker-compose.yml` | 插件本身：compose 加上 `x-wonton` 清单 |
| `provision.js` | 一次性 `provision` 服务的脚本：改写默认管理员，建主人账号 |
| `icon.svg` | 插件图标（Joplin 官方标志） |
| `screenshots/` | 商店详情页里的截图 |
| `scripts/smoke-probes.sh` | `scripts/dev.sh smoke` 的网页、身份、数据探测 |

## 图标来源与授权

`icon.svg` 原样使用 Joplin 官方标志（上游仓库 Assets/JoplinIcon.svg），未改动图形；来源、版权（上游声明
未经许可不得使用）、Joplin Server 许可证全文和商标说明见 [NOTICE](NOTICE)。Joplin 名称和标志是
Joplin 项目（Laurent Cozic）的商标；本插件是独立维护的云吞插件包，不代表上游官方出品、合作或背书。
