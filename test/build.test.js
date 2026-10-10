// Проверка манифеста каталога после сборки: ./build.sh && node test/build.test.js
const assert = require('assert');
const crypto = require('crypto'), fs = require('fs'), path = require('path');
const dist = path.join(__dirname, '../dist');
const info = require('../app/appinfo.json');
const m = JSON.parse(fs.readFileSync(path.join(dist, 'xraytv.app.manifest.json'), 'utf8'));
const ipk = fs.readFileSync(path.join(dist, m.ipkUrl));
assert.deepStrictEqual(m, {
  id: 'xraytv.app', version: info.version, type: 'web', title: 'Xray',
  ipkUrl: `xraytv.app_${info.version}_arm.ipk`,
  ipkHash: { sha256: crypto.createHash('sha256').update(ipk).digest('hex') },
  ipkSize: ipk.length,
});
console.log('build.test: ok');
