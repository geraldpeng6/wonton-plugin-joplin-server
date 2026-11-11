# shellcheck shell=bash
# Joplin Server：sso=none（应用自带登录）；清单没有 mcp。
# Joplin 的 API 和网页同端口（22300）：身份探针经网关用 lan.client 的账号（主人邮箱+核心生成的密码）
# POST /api/sessions 拿会话，再断言认出的是主人的管理员账号。
# 数据探针按 Joplin 的同步条目接口写一个原始条目（PUT /api/items/root:/<标记>:/content，
# multipart 的 file 字段是条目内容），存的是 Postgres 里的用户数据，重装不删数据就还在。
#
# 变量别叫 state：shellcheck 把这份文件连着 probes.sh 一起分析，probes.sh 自己也读一个 dev.sh 提供的 state；
# 子壳体函数（fn() ( … ) )里给 state 赋值，SC2031 就报在 probes.sh 上，CI 红。

_container() { # <插件 id> <服务名>：本实例里这个服务的容器
  local inst="${SMOKE_INSTANCE:-}" args=(--filter "label=wonton.plugin=$1" --filter "label=wonton.service=$2")
  if [[ -z "$inst" && -n "${SMOKE_BASE:-}" ]]; then
    inst="${SMOKE_BASE#http://}"; inst="${inst%%.*}"
  fi
  [[ -z "$inst" ]] || args+=(--filter "label=wonton.instance=${inst//-/}")
  docker ps --format '{{.Names}}' "${args[@]}" | head -1
}

web_assert() { grep -qi 'joplin'; }   # 登录页是应用的真实页面（根路径重定向到 /login）

identity_check() { # Joplin 按邮箱登录：lan.client 的账号就是一次性服务改写过的主人管理员账号
  local c email pw resp uid user
  c="$(_container "$SMOKE_PLUGIN_ID" server)" || { echo "找不到 server 容器"; return 1; }
  email="$(docker exec "$c" printenv WONTON_OWNER_EMAIL)" || { echo "server 容器里没有 WONTON_OWNER_EMAIL"; return 1; }
  pw="$(docker exec "$c" printenv WONTON_SECRET_CLIENT_PASSWORD)" || { echo "server 容器里没有 WONTON_SECRET_CLIENT_PASSWORD"; return 1; }
  resp="$(web_get /api/sessions -X POST -H 'Content-Type: application/json' \
    --data "{\"email\":\"$email\",\"password\":\"$pw\"}")" \
    || { echo "POST /api/sessions 失败：$resp"; return 1; }
  uid="$(jq -r '.user_id // empty' <<<"$resp")"
  [[ -n "$uid" ]] || { echo "登录没有返回 user_id：$(head -c 200 <<<"$resp")"; return 1; }
  user="$(web_get "/api/users/$uid" -H "x-api-auth: $(jq -r '.id' <<<"$resp")")" \
    || { echo "GET /api/users/$uid 失败：$user"; return 1; }
  jq -e --arg e "$email" '.is_admin == true and .email == $e' <<<"$user" >/dev/null \
    || { echo "登录到的不是主人的管理员账号：$(head -c 200 <<<"$user")"; return 1; }
}

# 合并前验证升级、重装不丢用户数据：写一个带随机标记的同步条目，标记存进标记文件。
marker_file() { # SMOKE_STATE 在套件里是状态目录（e2e 传的是标记文件本身），标记放对应路径
  if [[ -d "$SMOKE_STATE" ]]; then printf '%s' "$SMOKE_STATE/joplin-marker"; else printf '%s' "${SMOKE_STATE}.marker"; fi
}

data_write() {
  local marker resp
  marker="wonton-smoke-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
  # root:/<名字>:/content：名字不带 .md 时按原始内容存（Joplin 资源 blob 的同步方式），不用构造序列化的笔记。
  resp="$(web_get "/api/items/root:/$marker:/content" -X PUT -F "file=$marker")" \
    || { echo "PUT 条目失败：$resp"; return 1; }
  jq -e --arg m "$marker" '.id != null and .name == $m' <<<"$resp" >/dev/null \
    || { echo "PUT 返回的不是这条条目：$(head -c 200 <<<"$resp")"; return 1; }
  printf '%s' "$marker" >"$(marker_file)"
}

data_check() { # 同步条目还在，内容是那个标记
  local marker got
  marker="$(cat "$(marker_file)")"
  [[ -n "$marker" ]] || { echo "标记文件里没有标记"; return 1; }
  got="$(web_get "/api/items/root:/$marker:/content")" || { echo "读回条目失败：$got"; return 1; }
  grep -qF "$marker" <<<"$got" || { echo "条目内容不是 $marker：$(head -c 200 <<<"$got")"; return 1; }
}
