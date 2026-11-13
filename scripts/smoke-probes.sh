# shellcheck shell=bash
# Joplin API 只认 x-api-auth，网页登录另走 session Cookie。数据探针上传真实序列化笔记，不用空的资源条目。

_server() {
  [[ -n "${SMOKE_INSTANCE:-}" ]] || { echo '缺少 SMOKE_INSTANCE，不能定位本实例'; return 1; }
  local containers
  containers="$(docker ps --format '{{.Names}}' \
    --filter "label=wonton.instance=$SMOKE_INSTANCE" \
    --filter "label=wonton.plugin=$SMOKE_PLUGIN_ID" --filter 'label=wonton.service=server')" || return 1
  [[ -n "$containers" && "$containers" != *$'\n'* ]] || { echo '找不到唯一的本实例 server 容器'; return 1; }
  printf '%s' "$containers"
}

_admin_password() {
  local container
  container="$(_server)" || return 1
  docker exec "$container" printenv DEFAULT_ADMIN_PASSWORD
}

_api_session() {
  local pw response
  pw="$(_admin_password)" || return 1
  response="$(web_get /api/sessions --fail-with-body -X POST -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg pw "$pw" '{email:"admin@localhost",password:$pw}')")" || {
    echo 'Joplin 初始管理员登录失败'; return 1;
  }
  jq -er '.id' <<<"$response"
}

web_assert() { grep -qi 'joplin'; }

identity_check() {
  local token users pw code location headers
  token="$(_api_session)" || return 1
  users="$(web_get /api/users --fail-with-body -H "x-api-auth: $token")" || return 1
  jq -e '[.items[] | select(.email == "admin@localhost" and (.is_admin == 1 or .is_admin == true))] | length == 1' \
    <<<"$users" >/dev/null || { echo 'Joplin 会话没有识别初始管理员'; return 1; }
  pw="$(_admin_password)" || return 1
  headers="$(mktemp)"
  code="$(web_get /login -o /dev/null -w '%{http_code}' -D "$headers" -c "$SMOKE_JAR" \
    -H "Origin: $SMOKE_WEB_ORIGIN" --data-urlencode email=admin@localhost --data-urlencode "password=$pw")" || {
    rm -f "$headers"; return 1;
  }
  location="$(tr -d '\r' <"$headers" | grep -i '^location:')"
  rm -f "$headers"
  [[ "$code" == 302 && "$location" == *'/admin/dashboard' ]] || {
    echo "Joplin 网页登录没有跳转到管理页（HTTP $code）"; return 1;
  }
  web_get /admin/dashboard --fail-with-body | grep -qi 'joplin'
}

_note() {
  local id="$1"
  printf 'Wonton smoke %s\n\nWonton note body %s\n\nid: %s\nparent_id: \ncreated_time: 2026-01-01T00:00:00.000Z\nupdated_time: 2026-01-01T00:00:00.000Z\nuser_created_time: 2026-01-01T00:00:00.000Z\nuser_updated_time: 2026-01-01T00:00:00.000Z\nis_conflict: 0\nis_todo: 0\norder: 0\nencryption_cipher_text: \nencryption_applied: 0\nmarkup_language: 1\nis_shared: 0\ndeleted_time: 0\ntype_: 1' "$id" "$id" "$id"
}

data_write() {
  local token marker response note
  token="$(_api_session)" || return 1
  marker="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  note="$(mktemp)"
  _note "$marker" >"$note"
  response="$(web_get "/api/items/root:/$marker.md:/content" --fail-with-body -X PUT \
    -H "x-api-auth: $token" -F "file=@$note;filename=$marker.md;type=text/plain")" || {
    rm -f "$note"; return 1;
  }
  rm -f "$note"
  jq -e --arg name "$marker.md" '.id != null and .name == $name' <<<"$response" >/dev/null || return 1
  printf '%s' "$marker" >"$SMOKE_STATE"
}

data_check() {
  local token marker got
  token="$(_api_session)" || return 1
  marker="$(cat "$SMOKE_STATE")" || return 1
  [[ "$marker" =~ ^[a-f0-9]{32}$ ]] || { echo '笔记标记无效'; return 1; }
  got="$(web_get "/api/items/root:/$marker.md:/content" --fail-with-body -H "x-api-auth: $token")" || return 1
  python3 - "$marker" "$got" <<'PY'
import sys
marker, content = sys.argv[1:]
text, metadata = content.rsplit("\n\n", 1)
fields = dict(line.split(": ", 1) for line in metadata.splitlines())
if text != f"Wonton smoke {marker}\n\nWonton note body {marker}" or fields.get("id") != marker or fields.get("type_") != "1":
    sys.exit("读回的笔记标题、正文或标识与写入的不一致")
PY
}
