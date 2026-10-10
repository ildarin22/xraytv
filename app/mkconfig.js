// Разбор подписки и сборка конфига Xray. ES5 и только fs/dns: на ТВ Node v0.12.
//   node mkconfig.js parse <файл подписки> <хост подписки> <IP хоста>  → key JSON
//   node mkconfig.js render <шаблон> <key.json> <интерфейс>             → конфиг Xray
//   node mkconfig.js get <файл json> <поле>                              → значение поля
//   node mkconfig.js resolve <хост>                                      → IPv4
var fs = require('fs');

function read(f) { return fs.readFileSync(f, 'utf8'); }
function trim(s) { return s.replace(/^\s+|\s+$/g, ''); }

function b64(s) {
  // ponytail: Buffer.from нет в Node 0.12, а new Buffer на новых Node пишет предупреждение
  var useFrom = Buffer.from && Buffer.from !== Uint8Array.from;
  return (useFrom ? Buffer.from(s, 'base64') : new Buffer(s, 'base64')).toString('utf8');
}

// Подписка бывает base64 (обычный и url-safe) или простым текстом со ссылками.
function subText(raw) {
  var t = trim(String(raw));
  if (t.indexOf('://') < 0) t = b64(t.replace(/\s+/g, '').replace(/-/g, '+').replace(/_/g, '/'));
  return t;
}

function parse(raw, subHost, subIp) {
  var lines = subText(raw).split(/\r?\n/), line = null;
  for (var i = 0; i < lines.length && !line; i++) {
    if (/^vless:\/\//.test(trim(lines[i]))) line = trim(lines[i]);
  }
  if (!line) throw new Error('в подписке нет ссылки vless://');
  var m = /^vless:\/\/([^@]+)@([^:\/?#\[\]]+):(\d+)\/?\?([^#]*)/.exec(line);
  if (!m) throw new Error('не удалось разобрать ссылку vless://');
  var q = {};
  m[4].split('&').forEach(function (kv) {
    var j = kv.indexOf('=');
    if (j > 0) q[kv.slice(0, j)] = decodeURIComponent(kv.slice(j + 1));
  });
  if (q.security !== 'reality' || (q.type || 'tcp') !== 'tcp' || !q.pbk || !q.sni) {
    throw new Error('неподдерживаемый ключ: нужен VLESS + Reality + TCP');
  }
  // Сервер на том же IP, что и подписка → пишем домен подписки: смена IP подхватится сама.
  var address = m[2];
  if (subHost && /^\d{1,3}(\.\d{1,3}){3}$/.test(address) && address === subIp) address = subHost;
  return {
    address: address, port: Number(m[3]), id: decodeURIComponent(m[1]), flow: q.flow || '',
    sni: q.sni, fp: q.fp || 'chrome', pbk: q.pbk, sid: q.sid || '', spx: q.spx || ''
  };
}

function byTag(list, tag) {
  for (var i = 0; i < list.length; i++) if (list[i].tag === tag) return list[i];
  throw new Error('в шаблоне нет ' + tag);
}

function render(tpl, key, iface) {
  var c = JSON.parse(tpl);
  byTag(c.inbounds, 'tun-in').settings.autoOutboundsInterface = iface;
  var p = byTag(c.outbounds, 'proxy'), v = p.settings.vnext[0], r = p.streamSettings.realitySettings;
  v.address = key.address; v.port = key.port;
  v.users[0].id = key.id; v.users[0].flow = key.flow;
  r.serverName = key.sni; r.fingerprint = key.fp; r.publicKey = key.pbk; r.shortId = key.sid; r.spiderX = key.spx;
  return c;
}

function out(o) { process.stdout.write((typeof o === 'string' ? o : JSON.stringify(o, null, 1)) + '\n'); }

var a = process.argv.slice(2);
try {
  if (a[0] === 'parse') out(parse(read(a[1]), a[2] || '', a[3] || ''));
  else if (a[0] === 'render') out(render(read(a[1]), JSON.parse(read(a[2])), a[3]));
  else if (a[0] === 'get') { var val = JSON.parse(read(a[1]))[a[2]]; out(val === undefined ? '' : String(val)); }
  else if (a[0] === 'resolve') {
    require('dns').lookup(a[1], 4, function (e, ip) {
      if (e) { process.stderr.write('ошибка: не удалось найти адрес ' + a[1] + '\n'); process.exit(1); }
      out(ip);
    });
  } else { process.stderr.write('использование: parse | render | get | resolve (см. начало файла)\n'); process.exit(2); }
} catch (e) {
  process.stderr.write('ошибка: ' + e.message + '\n');
  process.exit(1);
}
