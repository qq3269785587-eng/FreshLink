import { createRequire } from 'module';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { execFileSync } from 'child_process';

const require = createRequire(import.meta.url);
const root = process.cwd();
const evidenceDir = process.argv[2];
if (!evidenceDir) throw new Error('evidence directory argument is required');
const evidence = path.resolve(root, evidenceDir);
const screenshots = path.join(evidence, 'screenshots');
fs.mkdirSync(screenshots, { recursive: true });
const apiRoot = 'http://127.0.0.1:18080/jeecg-boot';
const base = process.env.FRESHLINK_UI_BASE || 'http://127.0.0.1:13101';
const accounts = JSON.parse(fs.readFileSync(path.join(root, 'runtime', 'config', 'fresh-p1-demo-accounts.json'), 'utf8').replace(/^\uFEFF/, '')).users;
const yaml = fs.readFileSync(path.join(root, 'apps', 'backend', 'jeecg-module-system', 'jeecg-system-start', 'src', 'main', 'resources', 'application-dev.yml'), 'utf8');
const secret = /signatureSecret:\s*(\S+)/.exec(yaml)[1];
const redisCli = path.join(root, 'runtime', 'redis', 'bin', 'Redis-7.4.11-Windows-x64-msys2', 'redis-cli.exe');
const playwrightCore = process.env.FRESHLINK_PLAYWRIGHT_CORE || 'D:/Yuki/DeepSeek Harness/node_modules/.pnpm/node_modules/playwright-core';
const chromePath = process.env.FRESHLINK_CHROME || path.join(process.env.LOCALAPPDATA || '', 'ms-playwright', 'chromium-1243', 'chrome-win64', 'chrome.exe');
if (!fs.existsSync(chromePath)) throw new Error('Chromium executable not found: ' + chromePath);
const { chromium } = require(playwrightCore);

const assertions = [];
let total = 0;
function check(id, description, condition, actual = '') {
  total += 1;
  assertions.push({ id, description, expected: 'true', actual: String(actual || condition), passed: !!condition });
  if (!condition) throw new Error(`${id} failed: ${description} (${actual})`);
}
function sleep(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }

function redisKeys(pattern) {
  const out = execFileSync(redisCli, ['-h', '127.0.0.1', '-p', '6379', '-n', '15', 'KEYS', pattern], { encoding: 'utf8' });
  return out.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

async function login(page, username) {
  let captchaKey = '';
  let observedToken = '';
  page.on('request', (request) => {
    const match = /\/sys\/randomImage\/([^/?#]+)/.exec(request.url());
    if (match) captchaKey = match[1];
    const headers = request.headers();
    const token = headers['x-access-token'] || headers['authorization'];
    if (token) observedToken = token;
  });
  await page.goto(base + '/', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('input[placeholder="账号"]', { timeout: 30000 });
  for (let i = 0; i < 40 && !captchaKey; i++) await sleep(500);
  if (!captchaKey) {
    await page.locator('.ant-form img').first().click();
    for (let i = 0; i < 40 && !captchaKey; i++) await sleep(500);
  }
  if (!captchaKey) throw new Error('captcha request key was not observed');
  const prefix = crypto.createHash('md5').update(captchaKey + secret, 'utf8').digest('hex');
  let code = '';
  for (let i = 0; i < 20 && !code; i++) {
    const keys = redisKeys(prefix + '*');
    if (keys.length) code = keys[0].slice(prefix.length);
    else await sleep(300);
  }
  if (!code) throw new Error('captcha value was not found in isolated Redis DB15');
  await page.locator('input[placeholder="账号"]').first().fill(username);
  await page.locator('input[placeholder="密码"]').first().fill(accounts[username]);
  await page.locator('input[placeholder="验证码"]').first().fill(code);
  await Promise.all([
    page.waitForURL((url) => !url.pathname.includes('/login'), { timeout: 60000 }),
    page.getByRole('button', { name: /登\s*录/ }).first().click(),
  ]);
  await page.waitForSelector('.ant-layout', { timeout: 60000 });
  await sleep(1500);
  page.__observedToken = observedToken;
}

async function pageToken(page) {
  if (page.__observedToken) return page.__observedToken;
  return page.evaluate(() => {
    for (const storage of [localStorage, sessionStorage]) {
      for (const key of Object.keys(storage)) {
        const raw = storage.getItem(key) || '';
        if (!raw.includes('TOKEN__')) continue;
        try {
          const cache = JSON.parse(raw);
          const token = cache['TOKEN__'] && cache['TOKEN__'].value;
          if (token) return token;
        } catch (e) { /* ignore */ }
      }
    }
    return '';
  });
}

const browser = await chromium.launch({ executablePath: chromePath, headless: true });
const consoleErrors = [];
const failedResponses = [];
try {
  const hqContext = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await hqContext.newPage();
  page.on('console', (msg) => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
  page.on('pageerror', (error) => consoleErrors.push(String(error)));
  page.on('response', (response) => { if (response.status() >= 400) failedResponses.push({ url: response.url(), status: response.status() }); });
  await login(page, 'fresh_hq');
  await page.screenshot({ path: path.join(screenshots, '01-hq-dashboard.png') });

  await page.goto(base + '/fresh/suppliers', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('.ant-table', { timeout: 60000 });
  await page.waitForFunction(() => document.body.innerText.includes('生鲜供应商一'), null, { timeout: 30000 });
  const supplierText = await page.locator('.ant-table').innerText();
  check('UI-P1-01', 'HQ供应商页面显示S1/S2数据', supplierText.includes('S1') && supplierText.includes('S2'), 'table rows visible');
  await page.screenshot({ path: path.join(screenshots, '02-hq-suppliers.png') });

  // Open the add modal and submit an empty form: the page must show field errors, not save.
  await page.getByRole('button', { name: /新增/ }).first().click();
  await page.waitForSelector('.ant-modal', { timeout: 20000 });
  const modal = page.locator('.ant-modal').last();
  await modal.locator('.ant-btn-primary').last().click();
  await sleep(800);
  const errorText = await modal.innerText();
  check('UI-P1-02', '空表单提交显示必填错误', /请输入供应商编码|请输入供应商名称/.test(errorText), 'validation messages shown');
  await page.screenshot({ path: path.join(screenshots, '03-supplier-validation.png') });

  const code = 'FRESH-UI-' + Date.now();
  await modal.locator('input[placeholder="请输入供应商编码"]').fill(code);
  await modal.locator('input[placeholder="请输入供应商名称"]').fill('UI联调供应商');
  await modal.locator('.ant-btn-primary').last().click();
  await sleep(2500);
  const afterSave = await page.locator('.ant-table').innerText();
  check('UI-P1-01', '页面新增后列表刷新出现新供应商', afterSave.includes(code), 'new row visible');
  await page.screenshot({ path: path.join(screenshots, '04-supplier-saved.png') });

  // Clean up the UI-created row through the real API with the page session token.
  const token = await pageToken(page);
  check('UI-P1-04', '页面登录态可取得业务token', !!token, token ? 'token present (not written to evidence)' : 'missing');
  const listResponse = await fetch(apiRoot + '/fresh/suppliers/list?pageNo=1&pageSize=100', { headers: { 'X-Access-Token': token, Version: 'v3' } });
  const listPayload = await listResponse.json();
  const created = (listPayload.result.records || []).find((row) => row.supplierCode === code);
  check('UI-P1-01', '新增供应商真实落库并可查询', !!created, created ? created.id : 'not found');
  if (created) {
    const deleteResponse = await fetch(apiRoot + '/fresh/suppliers/delete?id=' + encodeURIComponent(created.id), { method: 'DELETE', headers: { 'X-Access-Token': token, Version: 'v3' } });
    const deletePayload = await deleteResponse.json();
    check('UI-P1-03', 'UI新增的临时供应商可清理', deletePayload.success === true, deletePayload.message);
  }

  await page.goto(base + '/fresh/stores', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('.ant-table', { timeout: 60000 });
  await page.waitForFunction(() => document.body.innerText.includes('门店A'), null, { timeout: 30000 });
  check('UI-P1-01', 'HQ门店页面加载并显示A/B', (await page.locator('.ant-table').innerText()).includes('门店B'));
  await page.screenshot({ path: path.join(screenshots, '05-hq-stores.png') });

  await page.goto(base + '/fresh/user-stores', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('.ant-table', { timeout: 60000 });
  await page.waitForFunction(() => document.body.innerText.includes('fresh_store_a'), null, { timeout: 30000 });
  check('UI-P1-01', '用户门店绑定页面加载并显示账号', (await page.locator('.ant-table').innerText()).includes('fresh_store_b'));
  await page.screenshot({ path: path.join(screenshots, '06-hq-user-stores.png') });

  await page.goto(base + '/fresh/products', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('.ant-table', { timeout: 60000 });
  await page.waitForFunction(() => document.body.innerText.includes('FRESH-X'), null, { timeout: 30000 });
  const productText = await page.locator('.ant-table').innerText();
  check('UI-P1-01', '食材页面显示温区与临期阈值列', productText.includes('温区') && productText.includes('临期阈值'), 'columns visible');
  await page.screenshot({ path: path.join(screenshots, '07-hq-products.png') });

  await page.goto(base + '/fresh/zones', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('.ant-table', { timeout: 60000 });
  await page.waitForFunction(() => document.body.innerText.includes('冷藏区'), null, { timeout: 30000 });
  const zoneText = await page.locator('.ant-table').innerText();
  check('UI-P1-01', '温区与库位页面显示温区标签', zoneText.includes('温区') && zoneText.includes('冷藏区'), 'zone page loaded');
  await page.screenshot({ path: path.join(screenshots, '07b-hq-zones.png') });

  const menuText = await page.locator('body').innerText();
  check('UI-P1-05', 'HQ菜单包含生鲜基础资料', menuText.includes('生鲜基础资料'), 'menu visible');

  // Store account: own store only, no maintenance buttons.
  const storeContext = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const storePage = await storeContext.newPage();
  storePage.on('console', (msg) => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
  storePage.on('pageerror', (error) => consoleErrors.push(String(error)));
  storePage.on('response', (response) => { if (response.status() >= 400) failedResponses.push({ url: response.url(), status: response.status() }); });
  await login(storePage, 'fresh_store_a');
  await storePage.goto(base + '/fresh/my-store', { waitUntil: 'domcontentloaded' });
  await storePage.waitForSelector('.ant-table', { timeout: 60000 });
  await storePage.waitForFunction(() => document.body.innerText.includes('门店A'), null, { timeout: 30000 });
  const storeBody = await storePage.locator('body').innerText();
  check('UI-P1-04', '门店A页面只显示本店', storeBody.includes('门店A') && !storeBody.includes('门店B'), 'own store only');
  check('UI-P1-04', '门店A页面没有新增门店按钮', (await storePage.getByRole('button', { name: /新增/ }).count()) === 0, 'no add button');
  await storePage.screenshot({ path: path.join(screenshots, '08-store-a-my-store.png') });

  const storeMenus = await storePage.locator('body').innerText();
  check('UI-P1-04', '门店菜单不显示供应商/用户绑定', !storeMenus.includes('生鲜基础资料'), 'restricted menu');
  // Pre-existing shell integrations (legacy 8080 websocket, CLodop, socket.io) are not P1 pages.
  const blockingErrors = consoleErrors.filter((text) => /Failed to fetch|Cannot read|Uncaught|TypeError/.test(text) && !/websocket|CLodop|socket\.io/i.test(text));
  check('UI-P1-06', '业务页面无阻断性脚本错误', blockingErrors.length === 0, blockingErrors.slice(0, 3).join(' | '));
  const blocking404 = failedResponses.filter((item) => item.status === 404 && /\/fresh\/|wmsProducts|getUserPermissionByToken/.test(item.url));
  check('UI-P1-06', 'P1页面与接口无404', blocking404.length === 0, JSON.stringify(blocking404.slice(0, 3)));

  await storeContext.close();
  await hqContext.close();
} finally {
  await browser.close();
  fs.writeFileSync(path.join(evidence, 'ui-assertions.json'), JSON.stringify({ total, passed: assertions.filter((a) => a.passed).length, assertions, consoleErrors, failedResponses }, null, 2), 'utf8');
  const lines = [
    '# P1 real page probe',
    '',
    `- URL: ${base} (production build, proxy /jeecgboot -> 18080)`,
    `- Time: ${new Date().toISOString()}`,
    `- Assertions: ${total}; passed: ${assertions.filter((a) => a.passed).length}`,
    `- Console errors captured: ${consoleErrors.length}`,
    '',
    '| id | assertion | passed |',
    '|---|---|---|',
    ...assertions.map((a) => `| ${a.id} | ${a.description} | ${a.passed} |`),
    '',
    'Screenshots are in `screenshots/`. Passwords and tokens are not written to evidence.',
  ];
  fs.writeFileSync(path.join(evidence, 'ui-probe.md'), lines.join('\n'), 'utf8');
}
console.log(`P1 UI probe PASS: ${total} assertions`);
