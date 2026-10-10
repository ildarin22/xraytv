// Самопроверка mkconfig.js на ПК: node test/mkconfig.test.js
// Нужен Xray для ПК: .cache/Xray-linux-64/xray (его качает build.sh).
const assert = require('assert');
const { spawnSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const MK = path.join(__dirname, '../app/mkconfig.js');
const TPL = path.join(__dirname, '../app/config.template.json');
const XRAY = path.join(__dirname, '../.cache/Xray-linux-64/xray');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mkconfig-'));
const file = (name, text) => { const f = path.join(dir, name); fs.writeFileSync(f, text); return f; };
const run = (...args) => spawnSync('node', [MK, ...args], { encoding: 'utf8' });
const b64 = (s) => Buffer.from(s).toString('base64');
const LINK = 'vless://11111111-2222-3333-4444-555555555555@203.0.113.7:443?type=tcp&security=reality' +
  '&pbk=9wrWWeEdTVkygfL62NS86fIS2wKgWO_28akrGTg0ynU&fp=firefox&sni=www.example.com&sid=ab12' +
  '&spx=%2Fx1y2&flow=xtls-rprx-vision#test-node';

// 1. base64-подписка, IP из ссылки совпадает с IP хоста подписки → пишется домен
let r = run('parse', file('s1', b64(LINK) + '\n'), 'sub.example.org', '203.0.113.7');
assert.strictEqual(r.status, 0, r.stderr);
const key = JSON.parse(r.stdout);
assert.deepStrictEqual(key, {
  address: 'sub.example.org', port: 443, id: '11111111-2222-3333-4444-555555555555',
  flow: 'xtls-rprx-vision', sni: 'www.example.com', fp: 'firefox',
  pbk: '9wrWWeEdTVkygfL62NS86fIS2wKgWO_28akrGTg0ynU', sid: 'ab12', spx: '/x1y2',
});
// 2. IP чужой → остаётся IP
r = run('parse', file('s2', b64(LINK)), 'sub.example.org', '198.51.100.1');
assert.strictEqual(JSON.parse(r.stdout).address, '203.0.113.7');
// 3. домен в ссылке остаётся как есть
r = run('parse', file('s3', b64(LINK.replace('203.0.113.7', 'node.example.net'))), 'sub.example.org', '203.0.113.7');
assert.strictEqual(JSON.parse(r.stdout).address, 'node.example.net');
// 4. подписка простым текстом, перед vless — чужая ссылка: берётся первая vless://
r = run('parse', file('s4', 'trojan://x@h:1#t\n' + LINK + '\n'), '', '');
assert.strictEqual(r.status, 0, r.stderr);
assert.strictEqual(JSON.parse(r.stdout).address, '203.0.113.7');
// 5. не Reality → понятный отказ
r = run('parse', file('s5', b64(LINK.replace('security=reality', 'security=tls'))), '', '');
assert.strictEqual(r.status, 1);
assert.match(r.stderr, /^ошибка: неподдерживаемый ключ/);
// 6. мусор вместо подписки → понятный отказ
r = run('parse', file('s6', 'hello world'), '', '');
assert.strictEqual(r.status, 1);
assert.match(r.stderr, /^ошибка: в подписке нет ссылки vless/);
// 7. render: поля на месте, правила не тронуты, настоящий xray принимает конфиг
const keyFile = file('key.json', JSON.stringify(key));
r = run('render', TPL, keyFile, 'wlan0');
assert.strictEqual(r.status, 0, r.stderr);
const cfg = JSON.parse(r.stdout);
assert.strictEqual(cfg.inbounds.find((i) => i.tag === 'tun-in').settings.autoOutboundsInterface, 'wlan0');
const p = cfg.outbounds.find((o) => o.tag === 'proxy');
assert.strictEqual(p.settings.vnext[0].address, 'sub.example.org');
assert.strictEqual(p.settings.vnext[0].users[0].id, key.id);
assert.strictEqual(p.streamSettings.realitySettings.spiderX, '/x1y2');
assert.deepStrictEqual(cfg.routing, JSON.parse(fs.readFileSync(TPL, 'utf8')).routing);
const t = spawnSync(XRAY, ['run', '-test', '-c', file('cfg.json', r.stdout)], { encoding: 'utf8' });
assert.match(t.stdout + t.stderr, /Configuration OK/);
// 8. get
assert.strictEqual(run('get', keyFile, 'port').stdout, '443\n');
assert.strictEqual(run('get', keyFile, 'nope').stdout, '\n');
console.log('mkconfig.test: ok');
