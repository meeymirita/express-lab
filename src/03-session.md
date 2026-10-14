# Сессия 3 · Протокол HTTP и свой сервер
dur: ~4 ч

## 3.1 Сырой HTTP своими глазами | short: Запрос и ответ | est: ~25 мин
### intro
**Слова шага:** *стартовая строка* — первая строка запроса (`GET /health HTTP/1.1`) или ответа (`HTTP/1.1 200 OK`); *заголовок (header)* — пара `Имя: значение`, одна на строку; *тело (body)* — данные после пустой строки; `node:net` — модуль для сырых TCP-соединений, без HTTP поверх.

Express и даже `node:http` (сессия 1) прячут то, что на самом деле едет по сети: обычный **текст** по правилам протокола HTTP. Увидим его буквально — поднимем TCP-сокет через `node:net` и напечатаем байты запроса как есть, до того как их разберёт `node:http`:

**Файл:** `raw-tcp-server.js`.

```bash run
cd /work/sharebox
cat > raw-tcp-server.js <<'EOF'
import { createServer } from 'node:net'

const server = createServer((socket) => {
  socket.on('data', (chunk) => {
    console.log('--- сырые байты запроса ---')
    console.log(chunk.toString('utf8'))
    socket.end('HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok')
  })
})
server.listen(3100, () => console.log('raw TCP слушает 3100'))
EOF
node raw-tcp-server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3100/health?x=1
echo
kill $SERVER_PID
```

### result
```out auto
```

### why
Это и есть то, что `req`/`res` в `node:http` (сессия 1) уже разобрали за тебя: **стартовая строка** (`GET /health?x=1 HTTP/1.1`), следом заголовки по одному на строку (`Host:`, `User-Agent:`, `Accept:` — их добавил `curl` сам), пустая строка — конец заголовков, и тело (у `GET` без тела его обычно нет). Весь курс дальше — разные уровни надстроек над этим же текстом.

### deep Под капотом
`\r\n` (CRLF) — обязательный разделитель строк в HTTP, а не просто `\n`: протокол придумывался, когда разные системы по-разному переводили строку, и зафиксировали оба символа. Ответ в примере собран этой же строкой вручную — `node:http` и Express делают ровно то же самое под капотом, просто автоматически и без опечаток.

### deep Если не получилось
- **Пусто вместо байтов запроса** — сервер не успел подняться до `curl`; `sleep 1` в примере — для этого.
- **`curl` показывает тело `ok`, а заголовки запроса не видны** — `-s` в `curl` скрывает служебный вывод самого curl, но не меняет то, что сервер печатает в свой лог; ищи блок между `---`.

### quiz
- Из каких трёх частей состоит HTTP-запрос построчно?
- Чем заканчиваются заголовки и начинается тело?
- Что добавляет `curl` в запрос сам, без твоего участия?

### links
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Messages | анатомия HTTP-сообщений | MDN: HTTP messages

## 3.2 Методы, статусы, заголовки ответа | short: Методы и статусы | est: ~25 мин
### intro
**Слова шага:** *метод* — глагол действия (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`); *идемпотентность* — повторный одинаковый запрос не меняет результат второй раз (разберём подробнее в сессии 10); *код состояния* — трёхзначное число с классом по первой цифре (2xx успех, 4xx ошибка клиента, 5xx ошибка сервера); `Content-Type` — заголовок, которым сервер сообщает формат тела.

Методы — не просто разные имена, а **соглашение о смысле**: `GET` ничего не меняет на сервере (безопасный), `GET`/`PUT`/`DELETE` — идемпотентны (повтори хоть 10 раз — результат тот же), `POST` — нет (10 одинаковых `POST /orders` создадут 10 заказов). Допишем в `server.js` (сессия 1) разбор метода и путей с нормальными кодами ответа:

**Файл:** `server.js`.

```bash run
cat > server.js <<'EOF'
import { createServer } from 'node:http'

const server = createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`)
  console.log(req.method, url.pathname, Object.fromEntries(url.searchParams))

  if (url.pathname === '/health' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ status: 'ok', uptime: process.uptime() }))
    return
  }
  if (url.pathname === '/echo' && req.method === 'POST') {
    let body = ''
    req.on('data', (chunk) => { body += chunk })
    req.on('end', () => {
      res.writeHead(201, { 'Content-Type': 'application/json' })
      res.end(JSON.stringify({ youSent: body }))
    })
    return
  }
  res.writeHead(404, { 'Content-Type': 'text/plain' })
  res.end('Not Found')
})

const PORT = process.env.PORT || 3000
server.listen(PORT, () => console.log(`ShareBox слушает порт ${PORT}`))
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/health
curl -s -X POST -d 'привет' http://localhost:3000/echo
echo
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/nope
kill $SERVER_PID
```

**Разбор.** `new URL(req.url, base)` — разбирает путь и query-строку сам, без ручного `split('?')`; `req.on('data'/'end')` — тело POST-запроса приходит **потоком** (сессия 2!), и нужно собрать его целиком, прежде чем разбирать — `node:http` не читает тело за тебя автоматически, в отличие от Express (`express.json()`, сессия 9).

### result
```out auto
```

### why
`201 Created` для `POST`, который создал что-то новое, `200 OK` для успешного `GET`, `404` для несуществующего пути — это словарь, которым весь остальной курс (и любой HTTP API в принципе) будет пользоваться не задумываясь. Про идемпотентность и полный список кодов — подробнее в сессии 10, когда появится настоящий REST-контракт ShareBox.

### deep Как ещё можно
Полный список кодов — на [httpstatuses.com](https://httpstatuses.com/); из тех, что реже на слуху, пригодятся `204 No Content` (успех без тела — удаление), `409 Conflict` (конфликт состояния) и `429 Too Many Requests` (превышен лимит — сессия 17).

### deep Если не получилось
- **`req.on('end')` не срабатывает** — тело большое и ещё не всё пришло, либо забыт `req.on('data', ...)` до него (Node не начнёт накапливать события, если на них никто не подписан).
- **`url.searchParams` пустой, хотя в адресе есть `?x=1`** — `req.url` уже содержит query-строку, но `new URL` без второго аргумента (base) не распознаёт относительный путь — не забывай `http://${req.headers.host}`.

### quiz
- Почему `POST` не идемпотентен, а `GET` и `DELETE` — идемпотентны?
- Что нужно сделать с телом `POST`-запроса в `node:http`, прежде чем с ним работать, и почему Express это не делает сам?
- Какой код вернуть при успешном создании ресурса, а какой — при успехе без тела в ответе?

### links
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods | справочник по методам HTTP | MDN: HTTP request methods
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Status | справочник по кодам состояния | MDN: HTTP response status codes

## 3.3 Формы: x-www-form-urlencoded и multipart | short: Формы | est: ~30 мин
### intro
**Слова шага:** `application/x-www-form-urlencoded` — тело формы как query-строка (`a=1&b=2`); `multipart/form-data` — тело из нескольких частей, разделённых границей (boundary), нужен для файлов; *boundary* — случайная строка-разделитель между частями multipart-тела.

Браузерная `<form>` отправляет тело одним из двух способов. Увидим оба как сырой текст — продолжим `raw-tcp-server.js` из шага 3.1:

```bash run
node raw-tcp-server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3100 -d 'name=Mira&role=admin' >/dev/null
sleep 0.3
curl -s http://localhost:3100 -F 'name=Mira' -F 'avatar=@package.json' >/dev/null
sleep 0.3
kill $SERVER_PID
```

### result
```out auto
```

### why
`-d` отправляет `application/x-www-form-urlencoded` — тело выглядит как `name=Mira&role=admin`, разобрать его можно `new URLSearchParams(body)`, тем же классом, что в шаге 3.2 для query-строки. `-F` отправляет `multipart/form-data`: каждая часть (`name`, `avatar`) отделена строкой-**boundary** (её видно в заголовке `Content-Type` запроса и перед каждой частью тела) — именно так браузер отправляет файлы, и именно это разберёт `multer` в сессии 15, а не руками, как сейчас.

### deep Как ещё можно
Писать свой парсер `multipart/form-data` вручную — плохая идея для продакшена (границы, кодировки, потоковая обработка больших файлов — сложно и легко ошибиться); отсюда и `multer` в сессии 15. Но увидеть один раз, как выглядит реальный boundary в сыром виде, стоит — это убирает ощущение магии.

### deep Если не получилось
- **В выводе не видно `Content-Type: multipart/form-data; boundary=...`** — `curl -F` сам генерирует этот заголовок; сверь, что сервер печатает ВЕСЬ `chunk.toString()`, включая заголовки, а не только первую строку.
- **Между `curl`-вызовами результаты перемешались** — `sleep 0.3` разделяет их на выводе; в реальном сервере это не нужно, запросы не блокируют друг друга (event loop, `js-lab`).

### quiz
- Чем `application/x-www-form-urlencoded` отличается от `multipart/form-data` по структуре тела?
- Зачем multipart нужна граница (boundary) и откуда сервер узнаёт, какая именно строка — граница?
- Почему для файлов используют multipart, а не urlencoded?

### links
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/POST | отправка форм, оба формата | MDN: POST

## 3.4 Cookies и чанки (Transfer-Encoding) | short: Cookies и chunked | est: ~25 мин
### intro
**Слова шага:** `Set-Cookie` — заголовок ответа, которым сервер просит браузер запомнить пару имя=значение; `Cookie` — заголовок запроса, которым браузер возвращает их обратно; `Transfer-Encoding: chunked` — тело передаётся частями без заранее известного общего размера (в отличие от `Content-Length`).

**Cookies** — простой протокол «запомни и присылай обратно»: сервер один раз просит `Set-Cookie`, дальше браузер сам добавляет `Cookie` ко всем запросам на этот домен. Допишем в `server.js` (шаг 3.2) выдачу и чтение простой cookie:

**Файл:** `server.js` (добавить маршрут).

```bash run
cat >> server.js <<'EOF'
// добавлено в шаге 3.4 — но обработчик уже занял весь файл функцией выше;
// для демонстрации проще отдельный мини-сервер:
EOF
cat > cookie-demo.js <<'EOF'
import { createServer } from 'node:http'

const server = createServer((req, res) => {
  const cookies = Object.fromEntries((req.headers.cookie || '').split('; ').filter(Boolean).map((p) => p.split('=')))
  if (!cookies.visits) {
    res.writeHead(200, { 'Set-Cookie': 'visits=1; HttpOnly', 'Content-Type': 'text/plain' })
    res.end('первый визит, cookie выставлена')
  } else {
    res.writeHead(200, { 'Content-Type': 'text/plain' })
    res.end(`уже был(а): visits=${cookies.visits}`)
  }
})
server.listen(3200, () => console.log('cookie-demo на 3200'))
EOF
node cookie-demo.js &
SERVER_PID=$!
sleep 1
curl -s -c /tmp/cj.txt http://localhost:3200
echo
curl -s -b /tmp/cj.txt http://localhost:3200
echo
kill $SERVER_PID
```

**Разбор.** `-c /tmp/cj.txt` — `curl` сохраняет полученные cookie в файл (как это делает браузер в своём хранилище); `-b /tmp/cj.txt` — отправляет их обратно. `HttpOnly` — флаг, запрещающий JS в браузере читать эту cookie через `document.cookie` (защита от XSS-кражи токена — пригодится в сессии 14, refresh-токен ShareBox).

### result
```out auto
```

### why
Это тот самый механизм, на котором держится «запомненный вход» на любом сайте — и который ShareBox в сессии 14 заменит на JWT именно потому, что cookie с `HttpOnly` не видна фронтенду, а знать, истёк ли токен, иногда нужно. Понимание протокола объясняет, почему JWT ShareBox можно хранить и в cookie, и в заголовке `Authorization` — это выбор транспорта, а не части самого токена.

### deep Как ещё можно
`Transfer-Encoding: chunked` — альтернатива `Content-Length`, когда сервер не знает заранее полный размер ответа (например, генерирует его на лету): тело режется на куски, каждый со своим размером в начале, и завершается куском нулевой длины. `node:http` переключает на него сам, если ты не указал `Content-Length` и не вызвал `res.end()` сразу — увидеть это в сыром виде можно через `curl -v` (следующий шаг).

### deep Если не получилось
- **Второй `curl` тоже говорит «первый визит»** — файл `/tmp/cj.txt` не создался или не тот путь передан в `-b`; сверь, что оба вызова используют один и тот же файл.
- **`Cookie` не пришла на сервер** — у cookie есть домен/путь по умолчанию; при ручном тестировании через `curl` с файлом cookie-jar этого обычно не видно, в браузере — смотри DevTools → Application → Cookies.

### quiz
- Чем отличаются заголовки `Set-Cookie` и `Cookie` — кто и когда их отправляет?
- Что даёт флаг `HttpOnly` и от чего он защищает?
- Когда сервер использует `Transfer-Encoding: chunked` вместо `Content-Length`?

### links
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies | справочник по cookies | MDN: Using HTTP cookies
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Transfer-Encoding | Transfer-Encoding | MDN: Transfer-Encoding

## 3.5 curl построчно, HTTPS, HTTP/2 и HTTP/3 | short: curl и HTTPS | est: ~25 мин
### intro
**Слова шага:** `-v` — показать весь диалог curl с сервером построчно; `>`/`<` в выводе `-v` — что curl отправил / что получил; *TLS* — шифрование транспорта, на котором построен HTTPS; HTTP/2 и HTTP/3 — более новые версии протокола, быстрее на множестве запросов, тот же смысл заголовков и методов.

`-v` показывает **весь** диалог — не только тело ответа, как обычный `curl`, а что именно ушло на сервер и что пришло обратно, строка за строкой:

```bash run
curl -s -v http://example.com 2>&1 | head -20
```

**Разбор.** Строки с `>` — то, что curl **отправил** (стартовая строка запроса и заголовки); строки с `<` — то, что **пришёл** в ответе. Это ровно то же самое, что мы печатали руками через `node:net` в шаге 3.1, только теперь — настоящий внешний сервер.

Теперь то же самое, но по HTTPS, и посмотрим, какую версию протокола согласовал сервер:

```bash run
curl -s -o /dev/null -w 'версия протокола: HTTP/%{http_version}, код: %{http_code}\n' https://example.com
```

### result
```out auto
```

### why
**HTTPS** — тот же HTTP, но внутри TLS-туннеля: заголовки и методы не меняются, меняется то, что происходит *до* первого байта HTTP (рукопожатие TLS, сертификат сервера). **HTTP/2** — тот же смысл сообщений, но бинарный формат и параллельные потоки запросов в одном TCP-соединении (быстрее для страницы с десятками ресурсов, каждый из которых раньше ждал своей очереди). **HTTP/3** — то же самое поверх QUIC (UDP) вместо TCP — быстрее восстанавливается после потери пакета. Для ShareBox ничего из этого не нужно писать руками — HTTPS и выбор версии протокола берёт на себя reverse proxy перед сервером (Caddy, сессия 18), а код ShareBox остаётся тем же.

### deep Как ещё можно
`curl -I` — только заголовки ответа, без тела (быстрая проверка, что сервер жив и что он отвечает без скачивания всего содержимого). `curl --http1.1` — принудительно откатиться на HTTP/1.1, если нужно сравнить с HTTP/2 на одном и том же сервере.

### deep Если не получилось
- **Нет сети из песочницы/контейнера** — `curl: (6) Could not resolve host` или `(7) Failed to connect`: сверь, что контейнер лабы имеет доступ в интернет (у тебя на Mac — обычно есть).
- **Версия протокола не HTTP/2** — не все серверы поддерживают HTTP/2 одинаково; это не ошибка лабы, просто конкретный сервер ответил по HTTP/1.1.

### quiz
- Что означают строки с `>` и `<` в выводе `curl -v`?
- Что добавляет HTTPS к обычному HTTP и что в заголовках/методах при этом меняется?
- Кто в архитектуре ShareBox будет отвечать за HTTPS и выбор версии протокола — сам Node-процесс или что-то перед ним?

### links
- https://curl.se/docs/manpage.html | справочник по curl | curl: man page
- https://developer.mozilla.org/en-US/docs/Glossary/HTTP_2 | HTTP/2 коротко | MDN: HTTP/2

## 3.6 node:crypto: хеши и случайные токены | short: node:crypto | est: ~25 мин
### intro
**Слова шага:** `createHash` — посчитать хеш (например, sha256) от данных; `randomBytes`/`randomUUID` — криптографически стойкая случайность, годится для токенов и ключей (в отличие от `Math.random()`); *хеш* — короткий «отпечаток» данных: те же данные → тот же хеш, разные данные → почти наверняка разный.

`node:crypto` — то, чем ShareBox дальше посчитает `sha256` каждого загруженного файла (сессия 15) и сгенерирует код share-ссылки (сессия 16). Дату не меняем — используем сразу настоящие данные:

**Файл:** `crypto-demo.js`.

```bash run
cat > crypto-demo.js <<'EOF'
import { createHash, randomBytes, randomUUID } from 'node:crypto'

const data = 'содержимое файла (условно)'
const hash = createHash('sha256').update(data).digest('hex')
console.log('sha256:', hash)
console.log('тот же текст → тот же хеш:', createHash('sha256').update(data).digest('hex') === hash)

console.log('случайные байты (hex):', randomBytes(4).toString('hex'))
console.log('UUID:', randomUUID())
EOF
node crypto-demo.js
```

**Разбор.** `createHash('sha256').update(data).digest('hex')` — цепочка: создать хешер → скормить данные → получить результат в виде hex-строки. Хеш детерминирован (одни и те же данные всегда дают один и тот же результат) — это и позволит ShareBox в сессии 15 проверять, что скачанный файл не повреждён, сверяя `sha256`. `randomBytes`/`randomUUID` — криптографически стойкая случайность: `Math.random()` для токенов и ключей **не подходит**, она предсказуема при желании атакующего.

### result
```out auto
```

### why
Код share-ссылки ShareBox (сессия 16) и обычный числовой счётчик — разные вещи: счётчик предсказуем (`1, 2, 3...`), а код должен быть непредсказуем, чтобы его нельзя было подобрать перебором. `randomBytes`/`randomUUID` дают именно такую случайность; `Math.random()` — для игр и визуальных эффектов, не для безопасности.

### deep Если не получилось
- **`createHash is not a function`** — опечатка в импорте, сверь `import { createHash } from 'node:crypto'` (с `node:` в начале).
- **Хеш каждый раз разный на одних и тех же данных** — не может быть при `sha256`; проверь, что `data` действительно не меняется между вызовами (например, не содержит `Date.now()` или случайности внутри).

### quiz
- Почему `sha256` от одних и тех же данных всегда даёт один и тот же результат, а `randomBytes` — нет?
- Почему для кода share-ссылки нельзя использовать `Math.random()`?
- Как ShareBox (сессия 15) сможет проверить, что скачанный файл не повреждён, используя `sha256`?

### outro
:::tip Приёмка сессии 3
Ты можешь: объяснить структуру сырого HTTP-запроса и ответа построчно; различать методы по смыслу (идемпотентность, безопасность) и возвращать подходящие коды состояния; прочитать `application/x-www-form-urlencoded` и отличить его от `multipart/form-data` по сырому виду; выставить и прочитать cookie, объяснить `HttpOnly`; прочитать вывод `curl -v` и сказать, что изменилось бы с HTTPS/HTTP2; посчитать `sha256` и сгенерировать криптографически стойкий токен. В `/work/sharebox`: обновлённый `server.js` (методы, статусы, query), `raw-tcp-server.js`, `cookie-demo.js`, `crypto-demo.js`.
:::

### links
- https://nodejs.org/api/crypto.html | справочник по node:crypto | Node.js: Crypto
