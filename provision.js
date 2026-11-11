// 一次性服务：Joplin Server 首次启动自带默认管理员 admin@localhost / admin，不能留着。
// 把它的邮箱改成主人的内部邮箱（WONTON_OWNER_EMAIL）、密码换成核心生成的密码
// （WONTON_SECRET_CLIENT，lan.client 显示给 Joplin 客户端用的就是它）。
// Joplin Server 3.7.5 的实测行为：
//   POST /api/sessions {email, password} -> {id, user_id}，后续请求带 x-api-auth: <id>；
//   PATCH /api/users/:id 同上带 x-api-auth，body {email, password}，管理员改自己不用旧密码。
// 幂等：账号已改好时主人账号直接登录通过，跳过；默认账号登录失败且主人账号也失败时如实报错退出。
'use strict';

const base = 'http://server:22300';
const ownerEmail = process.env.WONTON_OWNER_EMAIL;
const clientPassword = process.env.WONTON_SECRET_CLIENT;
if (!ownerEmail || !clientPassword) {
  console.error('缺少 WONTON_OWNER_EMAIL 或 WONTON_SECRET_CLIENT，核心没有注入');
  process.exit(1);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function call(path, options) {
  const res = await fetch(base + path, options);
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`${options.method || 'GET'} ${path} -> HTTP ${res.status} ${text.slice(0, 200)}`);
    err.status = res.status;
    throw err;
  }
  return text ? JSON.parse(text) : null;
}

// 登录是探测语义：账号不存在、密码不对都返回 null，由调用方决定下一步；其余错误如实抛出。
async function tryLogin(email, password) {
  try {
    return await call('/api/sessions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
  } catch (err) {
    if (err.status === 400 || err.status === 403) return null;
    throw err;
  }
}

async function waitUntilReady() {
  const deadline = Date.now() + 120000;
  while (Date.now() < deadline) {
    try {
      await call('/api/ping', {});
      return;
    } catch {
      await sleep(2000);
    }
  }
  throw new Error('Joplin Server 120 秒内没有应答 /api/ping');
}

async function main() {
  await waitUntilReady();

  const ownerSession = await tryLogin(ownerEmail, clientPassword);
  if (ownerSession) {
    console.log('主人账号已就绪');
    return;
  }

  console.log('主人账号登录失败，尝试把默认管理员改成主人账号');
  const adminSession = await tryLogin('admin@localhost', 'admin');
  if (!adminSession) {
    console.error('默认管理员 admin@localhost 登录失败，主人账号也登录失败：无法完成首次设置');
    process.exit(1);
  }

  await call(`/api/users/${adminSession.user_id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', 'x-api-auth': adminSession.id },
    body: JSON.stringify({ email: ownerEmail, password: clientPassword }),
  });

  const newSession = await tryLogin(ownerEmail, clientPassword);
  if (!newSession) {
    console.error('改完账号后主人账号登录失败，可能密码或邮箱没有生效');
    process.exit(1);
  }
  const me = await call(`/api/users/${newSession.user_id}`, {
    headers: { 'x-api-auth': newSession.id },
  });
  if (!me.is_admin || me.email !== ownerEmail) {
    console.error(`改完的账号不对：email=${me.email} is_admin=${me.is_admin}`);
    process.exit(1);
  }

  if (await tryLogin('admin@localhost', 'admin')) {
    console.error('默认管理员 admin@localhost/admin 仍然能登录：改写没有生效');
    process.exit(1);
  }

  console.log(`主人账号 ${ownerEmail} 已就绪，默认管理员已改写`);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
