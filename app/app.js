// Экран приложения Xray. ES5: на webOS 4.5 движок Chromium 53.
// Всё, что требует root, делает xrayctl через exec Homebrew Channel.
var CTL = 'sh /media/developer/apps/usr/palm/applications/xraytv.app/xrayctl ';
var HB = 'luna://org.webosbrew.hbchannel.service/';
var NO_REPLY = 'ошибка: нет ответа от xrayctl';

function sec(ms) { return (ms / 1000).toFixed(1).replace('.', ',') + ' с'; }
function day(iso) { var p = iso.slice(0, 10).split('-'); return p[2] + '.' + p[1] + '.' + p[0]; }
function net(i) { return i === 'eth0' ? 'кабель' : i === 'wlan0' ? 'Wi-Fi' : i || 'нет сети'; }

// Статус xrayctl → что показать. Чистая функция, её проверяет test/app.test.js.
function describe(s) {
  var state = !s.keyUpdated ? { text: 'Подписка не введена', color: 'yellow' }
    : !s.enabled ? { text: 'Выключен', color: 'red' }
    : !s.running ? { text: 'Не запустился', color: 'red' }
    : !s.youtube.ok ? { text: 'Запущен, но YouTube не отвечает', color: 'yellow' }
    : { text: 'Работает', color: 'green' };
  return {
    state: state,
    rows: [
      ['YouTube', s.running ? 'через прокси' : 'напрямую', s.youtube.ok ? 'работает, ' + sec(s.youtube.ms) : 'не отвечает'],
      ['Сервер', s.server.host || '—', s.server.ok ? 'отвечает, ' + s.server.ms + ' мс' : 'не отвечает'],
      // сеть сменилась при работающем Xray: он держится за старый интерфейс, интернет ТВ стоит
      ['Сеть', net(s.iface), s.running && s.xrayIface && s.xrayIface !== s.iface
        ? 'Xray привязан к: ' + net(s.xrayIface) + ' — нажмите «Выключить», затем «Включить»' : ''],
      ['Ключ', s.keyUpdated ? 'обновлён ' + day(s.keyUpdated) : 'подписка не введена', '']
    ],
    errors: s.errors.length ? s.errors.join('\n') : 'нет',
    toggle: s.enabled ? 'Выключить' : 'Включить'
  };
}

// Ответ exec Homebrew Channel → { out, err }. Битый ответ — ошибка, а не исключение:
// исключение в колбэке оставило бы кнопки заблокированными навсегда.
// errorText упавшей команды — «Command failed: <вся команда>», в ней бывает подписка: берём только stderr.
function reply(m) {
  var r = null;
  try { r = JSON.parse(m); } catch (e) {}
  if (!r) return { out: '', err: NO_REPLY };
  return { out: (r.stdoutString || '').trim(), err: r.returnValue ? ''
    : 'stderrString' in r ? r.stderrString.trim() || 'ошибка: xrayctl завершился с ошибкой' : r.errorText || NO_REPLY };
}

function quote(t) { return "'" + t.replace(/'/g, "'\\''") + "'"; }   // строка для sh

if (typeof module !== 'undefined') module.exports = { describe: describe, reply: reply, quote: quote };

if (typeof document !== 'undefined') (function () {
  var keep = [], busy = false, last = null, autoStarted = false, idx = 0;
  function $(id) { return document.getElementById(id); }
  function esc(t) { return String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;'); }
  var buttons = [$('b-check'), $('b-toggle'), $('b-key'), $('b-sub')];
  var input = $('sub-url'), form = [input, $('b-save'), $('b-cancel')];
  var items = buttons;   // что выбирают стрелки: ряд кнопок или поле ввода подписки
  // значок состояния: крутящееся кольцо, пока ждём, потом кружок с галочкой / крестиком / «!»
  var SPIN = '<svg class="icon spin" viewBox="0 0 36 36"><circle cx="18" cy="18" r="15" stroke-dasharray="66 30"/></svg>';
  var MARK = { green: 'M11 19l5 5 9-11', red: 'M13 13l10 10M23 13l-10 10', yellow: 'M18 10v10M18 25v1' };
  function icon(c) { return '<svg class="icon" viewBox="0 0 36 36"><circle cx="18" cy="18" r="15"/><path class="mark" d="' + MARK[c] + '"/></svg>'; }
  function wait() { $('state').innerHTML = SPIN; $('state').className = ''; }

  function luna(uri, params, cb) {
    var b = new PalmServiceBridge();
    keep.push(b);  // без ссылки мост соберёт сборщик мусора раньше ответа
    b.onservicecallback = function (m) { keep.splice(keep.indexOf(b), 1); cb(m); };
    b.call(uri, JSON.stringify(params));
  }
  function run(command, cb) {
    luna(HB + 'exec', { command: command }, function (m) { var r = reply(m); cb(r.out, r.err); });
  }
  function show(d) {
    $('state').innerHTML = icon(d.state.color) + esc(d.state.text);
    $('state').className = d.state.color;
    var html = '';
    d.rows.forEach(function (r) {
      html += '<tr><td>' + r[0] + '</td><td>' + esc(r[1]) + '</td><td>' + esc(r[2]) + '</td></tr>';
    });
    $('rows').innerHTML = html;
    $('errors').textContent = 'Последние ошибки\n' + d.errors;
    $('b-toggle').textContent = d.toggle;
  }
  function refresh(note) {
    busy = true;
    wait();
    run(CTL + 'status', function (out, err) {
      busy = false;
      var d = null;
      try { last = JSON.parse(out); d = describe(last); } catch (e) { last = null; }
      if (!d) {
        $('state').innerHTML = icon('red') + 'Нет статуса';
        $('state').className = 'red';
        $('msg').textContent = err || NO_REPLY;
        return;
      }
      show(d);
      $('msg').textContent = note || '';
      if (!last.keyUpdated && items === buttons) focus(3);   // подписки нет — сразу к её вводу
      // после отключения света хук автозапуска ещё ждёт 25 с — запускаем сразу, один раз за открытие
      if (!autoStarted && last.keyUpdated && last.enabled && !last.running) { autoStarted = true; act(CTL + 'start', 'запускаю Xray'); }
    });
  }
  function act(command, label, done) {
    if (busy) return;
    busy = true;
    wait();
    $('msg').textContent = label + '…';
    run(command, function (out, err) { busy = false; if (done) done(!err); refresh((out + ' ' + err).trim()); });
  }
  function focus(i, mouse) {
    buttons.concat(form).forEach(function (b) { b.className = ''; });
    idx = (i + items.length) % items.length;
    items[idx].className = 'focus';
    if (mouse) return;   // указатель Magic Remote не трогает экранную клавиатуру
    input.blur();
    if (items[idx] === input) input.focus();   // поле в фокусе — webOS показывает клавиатуру
  }

  // Ввод подписки. Поле стирается сразу после «Сохранить» и при закрытии.
  // ponytail: пока идёт setup, подписка видна в списке процессов ТВ (аргумент sh -c у exec); другого канала нет
  function openForm() { items = form; $('nav').hidden = true; $('sub').hidden = false; focus(0); }
  function closeForm() {
    input.value = '';
    $('msg').textContent = '';
    items = buttons; $('sub').hidden = true; $('nav').hidden = false; focus(3);
  }
  function save() {
    var u = input.value.trim();
    if (busy) return;
    if (!/^https?:\/\//.test(u)) { $('msg').textContent = 'введите ссылку на подписку: http://… или https://…'; focus(0); return; }
    input.value = '';
    focus(1);
    act("printf '%s\\n' " + quote(u) + ' | ' + CTL + 'setup -', 'настраиваю', function (ok) { if (ok) closeForm(); });
  }

  buttons[0].onclick = function () { if (!busy) refresh(); };
  buttons[1].onclick = function () { if (last) act(CTL + (last.enabled ? 'stop' : 'start'), last.enabled ? 'выключаю' : 'включаю'); };
  buttons[2].onclick = function () { act(CTL + 'update-key', 'обновляю ключ'); };
  buttons[3].onclick = function () { if (!busy) openForm(); };
  form[1].onclick = save;
  form[2].onclick = function () { if (!busy) closeForm(); };
  buttons.concat(form).forEach(function (b) { b.onmouseover = function () { if (items.indexOf(b) >= 0) focus(items.indexOf(b), true); }; });
  input.onclick = function () { focus(0, true); };
  document.addEventListener('keydown', function (e) {
    if (e.keyCode === 37) focus(idx - 1);
    else if (e.keyCode === 39) focus(idx + 1);
    else if (e.keyCode === 13) { if (items[idx] === input || document.activeElement === input) save(); else items[idx].onclick(); }
    else if (e.keyCode === 461 || e.keyCode === 27) { if (items === form) form[2].onclick(); else window.close(); }  // «Назад» на пульте
    else return;
    e.preventDefault();
  });
  focus(0);
  wait();
  // поднять автозапуск Homebrew (нужно после отключения света), потом проверить статус
  luna(HB + 'autostart', {}, function () { refresh(); });
})();
