// Самопроверка describe() экрана: node test/app.test.js
const assert = require('assert');
const { execFileSync } = require('child_process');
const { describe, reply, quote } = require('../app/app.js');
const base = {
  enabled: true, running: true, iface: 'eth0',
  server: { host: 'h.example', port: 443, ok: true, ms: 48 },
  youtube: { ok: true, ms: 612 }, keyUpdated: '2026-10-10T12:00:00Z', errors: [],
};
const st = (o) => Object.assign({}, base, o);

let v = describe(base);
assert.deepStrictEqual(v.state, { text: 'Работает', color: 'green' });
assert.deepStrictEqual(v.rows, [
  ['YouTube', 'через прокси', 'работает, 0,6 с'],
  ['Сервер', 'h.example', 'отвечает, 48 мс'],
  ['Сеть', 'кабель', ''],
  ['Ключ', 'обновлён 10.10.2026', ''],
]);
assert.strictEqual(v.errors, 'нет');
assert.strictEqual(v.toggle, 'Выключить');

v = describe(st({ youtube: { ok: false, ms: 8001 } }));
assert.deepStrictEqual(v.state, { text: 'Запущен, но YouTube не отвечает', color: 'yellow' });
assert.strictEqual(v.rows[0][2], 'не отвечает');

v = describe(st({ enabled: false, running: false }));
assert.deepStrictEqual(v.state, { text: 'Выключен', color: 'red' });
assert.strictEqual(v.toggle, 'Включить');
assert.strictEqual(v.rows[0][1], 'напрямую');

v = describe(st({ running: false }));
assert.deepStrictEqual(v.state, { text: 'Не запустился', color: 'red' });

assert.strictEqual(describe(st({ iface: 'wlan0' })).rows[2][1], 'Wi-Fi');
assert.strictEqual(describe(st({ iface: '' })).rows[2][1], 'нет сети');
// сеть сменилась при работающем Xray: он привязан к старому интерфейсу
assert.strictEqual(describe(st({ xrayIface: 'eth0' })).rows[2][2], '');
assert.match(describe(st({ iface: 'wlan0', xrayIface: 'eth0' })).rows[2][2], /привязан к: кабель/);

// подписка не введена: ключа нет, Xray не запускался
v = describe(st({ running: false, keyUpdated: null, server: { host: '', port: 0, ok: false, ms: 0 } }));
assert.deepStrictEqual(v.state, { text: 'Подписка не введена', color: 'yellow' });
assert.deepStrictEqual(v.rows[3], ['Ключ', 'подписка не введена', '']);
assert.deepStrictEqual(v.rows[1], ['Сервер', '—', 'не отвечает']);

assert.strictEqual(describe(st({ errors: ['a', 'b'] })).errors, 'a\nb');
// ответ exec Homebrew Channel: битый или пустой — ошибка, а не исключение
assert.deepStrictEqual(reply('{"returnValue":true,"stdoutString":" Xray включён\\n"}'), { out: 'Xray включён', err: '' });
assert.deepStrictEqual(reply('{"returnValue":false,"stdoutString":"","stderrString":"ошибка: подписка недоступна\\n"}'),
  { out: '', err: 'ошибка: подписка недоступна' });
// errorText exec — «Command failed: <вся команда>», в ней подписка: на экран не попадает
const failed = reply(JSON.stringify({ returnValue: false, errorText: "Command failed: printf '%s\\n' 'https://h/sub/SECRET' | sh x setup -",
  stdoutString: '', stderrString: '' }));
assert.doesNotMatch(failed.err, /SECRET/);
assert.match(failed.err, /^ошибка/);
// ошибка самой шины (сервис недоступен) — без stdout/stderr, её текст полезен
assert.strictEqual(reply('{"returnValue":false,"errorText":"Unknown method"}').err, 'Unknown method');
for (const m of ['', '{"returnValue":tr', 'null']) {
  assert.deepStrictEqual(reply(m), { out: '', err: 'ошибка: нет ответа от xrayctl' });
}

// подписка уходит в sh в одинарных кавычках: проверяем настоящим sh
const sub = "https://h.example/sub/a'b\"c $HOME `id` \\ x''";
assert.strictEqual(execFileSync('sh', ['-c', "printf '%s' " + quote(sub)]).toString(), sub);
console.log('app.test: ok');
