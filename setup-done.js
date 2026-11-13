'use strict';

// 用应用镜像自带的 PostgreSQL 驱动和密码比较函数，只读检查管理员；主人改过密码也不会被重置。
const appRequire = require('node:module').createRequire(`${process.cwd()}/package.json`);
const { Client } = appRequire('pg');
const bcrypt = appRequire('bcryptjs');

async function main() {
  const db = new Client({
    host: process.env.POSTGRES_HOST,
    port: Number(process.env.POSTGRES_PORT),
    database: process.env.POSTGRES_DATABASE,
    user: process.env.POSTGRES_USER,
    password: process.env.POSTGRES_PASSWORD,
    connectionTimeoutMillis: 5000,
    query_timeout: 5000,
  });
  try {
    await db.connect();
    const { rows } = await db.query('SELECT password FROM users WHERE is_admin = 1 AND enabled = 1');
    if (rows.length === 0) {
      console.error('Joplin 没有启用的管理员账号');
      return 1;
    }
    for (const row of rows) {
      if (!row.password || await bcrypt.compare('admin', row.password)) {
        console.error('Joplin 管理员仍在使用上游默认密码，请先在管理页修改');
        return 1;
      }
    }
    return 0;
  } finally {
    await db.end();
  }
}

main().then((code) => { process.exitCode = code; }).catch((error) => {
  console.error(`无法确认 Joplin 管理员是否就绪：${error.message}`);
  process.exitCode = 2;
});
