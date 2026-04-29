const { WebClient } = require('@slack/web-api');
const fs = require('fs');
const path = require('path');

const TOKEN = process.env.SLACK_USER_TOKEN;
if (!TOKEN) {
  console.error('SLACK_USER_TOKEN not set');
  process.exit(1);
}

const client = new WebClient(TOKEN);

async function main() {
  const cmd = process.argv[2] || 'help';

  if (cmd === 'history') {
    const channel = process.argv[3];
    const limit = parseInt(process.argv[4]) || 20;
    const resp = await client.conversations.history({ channel, limit });
    const msgs = (resp.messages || []).filter(m => !m.subtype);
    for (const m of msgs) {
      const ts = new Date(parseFloat(m.ts) * 1000).toISOString();
      const text = (m.text || '').replace(/\n+/g, ' ');
      console.log(`[${ts}] ${text.substring(0,300)}${text.length > 300 ? '...' : ''}`);
    }
  } else if (cmd === 'info') {
    const channel = process.argv[3];
    const resp = await client.conversations.info({ channel });
    const c = resp.channel;
    console.log(JSON.stringify({ id: c.id, name: c.name, is_im: c.is_im, user: c.user, num_members: c.num_members }, null, 2));
  } else if (cmd === 'users') {
    const resp = await client.users_list({ limit: 200 });
    const members = resp.members || [];
    const q = (process.argv[3] || '').toLowerCase();
    for (const m of members) {
      if (!q || m.real_name?.toLowerCase().includes(q) || m.name?.toLowerCase().includes(q)) {
        console.log(`${m.id.padEnd(15)} @${(m.name || '').padEnd(15)} ${m.real_name || ''}`);
      }
    }
  } else {
    console.log(`Usage: slack_history.js <history|info|users> [args]`);
    console.log(`  history <channel> [limit]  — fetch channel history`);
    console.log(`  info <channel>             — channel metadata`);
    console.log(`  users [query]              — list users`);
  }
}

main().catch(e => { console.error(e.message || e); process.exit(1); });
