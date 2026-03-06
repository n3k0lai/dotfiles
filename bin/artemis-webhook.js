#!/usr/bin/env node
/**
 * Artemis Platform Deploy Webhook
 * 
 * Listens for GitHub push events and auto-deploys the Expo web build.
 * POST /webhook with X-Hub-Signature-256 header for verification.
 */

const http = require('http');
const crypto = require('crypto');
const { execSync } = require('child_process');
const path = require('path');

const PORT = parseInt(process.env.WEBHOOK_PORT || '9000');
const SECRET = process.env.WEBHOOK_SECRET || '';
const PLATFORM_DIR = process.env.PLATFORM_DIR || '/opt/artemis/platform';
const DEPLOY_DIR = process.env.DEPLOY_DIR || '/var/www/artemis';

function verify(signature, body) {
  if (!SECRET) return true; // no secret = no verification (dev mode)
  const expected = 'sha256=' + crypto.createHmac('sha256', SECRET).update(body).digest('hex');
  return crypto.timingSafeEqual(Buffer.from(signature || ''), Buffer.from(expected));
}

function deploy() {
  console.log(`[${new Date().toISOString()}] Starting deploy...`);
  try {
    execSync('git pull --ff-only', { cwd: PLATFORM_DIR, stdio: 'inherit' });
    execSync('npm ci', { cwd: PLATFORM_DIR, stdio: 'inherit' });
    execSync('npx expo export --platform web', { cwd: PLATFORM_DIR, stdio: 'inherit' });
    execSync(`rm -rf ${DEPLOY_DIR}/dist && cp -r ${PLATFORM_DIR}/dist ${DEPLOY_DIR}/dist`, { stdio: 'inherit' });
    console.log(`[${new Date().toISOString()}] Deploy complete!`);
  } catch (err) {
    console.error(`[${new Date().toISOString()}] Deploy failed:`, err.message);
  }
}

const server = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/webhook') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      const sig = req.headers['x-hub-signature-256'];
      if (!verify(sig, body)) {
        res.writeHead(403);
        res.end('Forbidden');
        return;
      }

      try {
        const payload = JSON.parse(body);
        const repo = payload.repository?.full_name;
        const ref = payload.ref;

        if (repo === 'artemis-bond/platform' && ref === 'refs/heads/main') {
          console.log(`[${new Date().toISOString()}] Push to platform/main detected`);
          res.writeHead(200);
          res.end('Deploying...');
          // Deploy async so we don't block the webhook response
          setTimeout(deploy, 100);
        } else {
          res.writeHead(200);
          res.end('Ignored (not platform/main)');
        }
      } catch (e) {
        res.writeHead(400);
        res.end('Bad request');
      }
    });
  } else if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200);
    res.end('ok');
  } else {
    res.writeHead(404);
    res.end('Not found');
  }
});

server.listen(PORT, () => {
  console.log(`[${new Date().toISOString()}] Artemis deploy webhook listening on :${PORT}`);
});
