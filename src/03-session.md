# Сессия 3 · Express 5
dur: ~4 ч

## 3.1 Зачем Express, если есть node:http | short: Зачем Express | est: ~15 мин
### intro
**Слова шага:** *фреймворк* — готовый каркас поверх `node:http`, берёт на себя рутину; *роутер (router)* — сопоставление «метод + адрес → функция»; *middleware* — функция, встраиваемая в цепочку обработки запроса (кратко, подробно в 3.4).

В сессии 1 ты написала сервер на `node:http` целиком руками: один обработчик, внутри — `if` на каждый адрес. На десять адресов это превратится в нечитаемую стену `if`. **Express** — не замена `node:http`, а надстройка над ним: он сам создаёт `http`-сервер внутри, а тебе даёт **роутер** (сопоставление «метод + адрес → функция») и **middleware** — функции, которые можно вставить в цепочку обработки запроса.

Поставим Express 5 и посмотрим на его версию:

```bash run
cd /work/sharebox
npm install express@5
node -e "console.log(require('express/package.json').version)"
```

### result
```out auto
```

### why
Эта сессия — главная причина, зачем в принципе существует эта лаба: дальше 9 сессий (авторизация, файлы, share-ссылки, админка) — это всё middleware и роуты поверх одного и того же `app`, созданного сегодня.

### deep Как ещё можно
Альтернативы Express — `Fastify` (быстрее, строже со схемами) и `Koa` (от тех же авторов, что и Express, но async-first). Express выбран для лабы, потому что он до сих пор самый распространённый и на нём держится NestJS изнутри (режим `platform-express`).

### deep Если не получилось
- **`npm error code ERESOLVE`** — конфликт версий зависимостей; обычно помогает `npm install express@5 --save-exact`, чтобы зафиксировать точную версию.
- **`Cannot find module 'express'`** — `npm install` выполнен не в папке `/work/sharebox` (где `package.json`); сверь `pwd`.

### quiz
- Express заменяет `node:http` или работает поверх него?
- Что из написанного в сессии 1 руками (роутинг через `if`) возьмёт на себя Express?
- Почему версия зафиксирована как `express@5`, а не просто `express`?

### links
- https://expressjs.com/en/guide/routing.html | роутинг в Express | Express: Routing

## 3.2 Роутер: req, res, параметры, query | short: Роутер | est: ~30 мин
### intro
**Слова шага:** `app.get`/`app.post` — зарегистрировать обработчик на метод и путь; `req` — объект запроса (что прислал клиент); `res` — объект ответа (что отправить клиенту); *параметр пути* — часть адреса вида `:id`; *query-строка* — часть адреса после `?`.

Каркас приложения — объект `app`, у него методы `.get()`, `.post()` и т. д. по HTTP-методам; у каждого — путь и функция-обработчик `(req, res) => {...}`. Соберём каркас ShareBox поверх вчерашнего `server.js`:

**Файл:** `server.js`.

```bash run
cat > server.js <<'EOF'
import express from 'express'

const app = express()

app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() })
})

app.get('/files/:id', (req, res) => {
  res.json({ id: req.params.id, note: 'заглушка — файл появится в сессии 8' })
})

app.get('/search', (req, res) => {
  res.json({ query: req.query.q || null, page: Number(req.query.page) || 1 })
})

const PORT = process.env.PORT || 3000
app.listen(PORT, () => console.log(`ShareBox (Express) слушает порт ${PORT}`))
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/health
echo
curl -s http://localhost:3000/files/abc123
echo
curl -s "http://localhost:3000/search?q=report&page=2"
echo
kill $SERVER_PID
```

**Разбор.** `:id` в пути — **параметр**: кусок адреса попадает в `req.params.id`. `?q=report&page=2` — **query-строка**, доступна целиком в `req.query` как объект. `res.json(...)` сам выставляет заголовок `Content-Type: application/json` и сериализует объект — в сессии 1 это делалось руками через `JSON.stringify` и `writeHead`.

### result
```out auto
```

### why
`req.params` и `req.query` — это 90% того, откуда роут берёт входные данные (третий источник — тело запроса, следующий шаг). Share-ссылка в сессии 9 будет устроена ровно так: `/s/:code` — код из `req.params`.

### deep Если не получилось
- **`Cannot GET /files/abc123`** — путь не совпал: Express ищет точное совпадение метода и шаблона; сверь, что не перепутаны `/files/:id` и `/file/:id`.
- **`req.query.page` — строка, а не число** — всё в query всегда строка; `Number(...)` в примере — обязательное приведение типа, иначе `page + 1` даст `'21'`, а не `3`.

### quiz
- Чем `req.params` отличается от `req.query`?
- Что вернёт `req.params.id` для запроса `GET /files/xyz`?
- Почему `req.query.page` нужно оборачивать в `Number(...)`?

### links
- https://expressjs.com/en/api.html#req | справочник по req | Express: Request
- https://expressjs.com/en/api.html#res | справочник по res | Express: Response

## 3.3 Тело запроса: express.json() | short: express.json() | est: ~20 мин
### intro
**Слова шага:** *тело запроса (body)* — данные, которые клиент присылает вместе с запросом; `express.json()` — middleware, которое разбирает JSON-тело в `req.body`; `Content-Type` — заголовок, которым клиент объявляет формат тела; `POST` — метод, которым обычно присылают тело.

`GET`-запрос обычно без тела — все данные в пути и query. `POST`/`PUT` присылают **тело** — например, JSON с данными формы. Но Express **не читает** его сам: тело приходит как поток байтов (сессия 2!), и нужен встроенный middleware `express.json()`, который этот поток дочитает и положит готовый объект в `req.body`.

**Файл:** `server.js` (дописать).

```bash run
cat >> server.js <<'EOF'

app.use(express.json())

app.post('/echo', (req, res) => {
  res.json({ получено: req.body })
})
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s -X POST http://localhost:3000/echo -H 'Content-Type: application/json' -d '{"name":"ShareBox"}'
echo
curl -s -X POST http://localhost:3000/echo -d '{"name":"без заголовка"}'
echo
kill $SERVER_PID
```

### result
```out auto
```

### why
Второй `curl` без заголовка `Content-Type: application/json` показывает, почему заголовок обязателен: `express.json()` смотрит именно на него, чтобы понять, что тело — JSON, а не что-то другое (файл, форма); без него `req.body` останется пустым объектом. Регистрация формы и загрузка файлов (сессии 7–8) — это `POST`/`PUT` с телом, тот же механизм.

### deep Если не получилось
- **`req.body` — `undefined`** — `app.use(express.json())` не вызван, или вызван **после** роута, который его использует; порядок `app.use(...)` важен — разберём в следующем шаге.
- **`SyntaxError: Unexpected token`** — невалидный JSON в `-d`; экранирование кавычек в терминале — частый источник ошибки, сверь с примером дословно.

### quiz
- Почему Express не читает тело запроса сам по себе, без `express.json()`?
- Что произойдёт с `req.body`, если не прислать заголовок `Content-Type: application/json`?
- Какой запрос обычно присылает тело — `GET` или `POST`?

### links
- https://expressjs.com/en/api.html#express.json | справочник по express.json() | Express: express.json()

## 3.4 Middleware и порядок | short: Middleware | est: ~30 мин
### intro
**Слова шага:** *middleware* — функция `(req, res, next)`, которая выполняется до или вместо роута; `app.use` — подключить middleware; `next()` — передать управление дальше по цепочке; *цепочка обработки* — порядок, в котором Express вызывает middleware и роуты.

**Middleware** — функция `(req, res, next) => {...}`, которую Express вызывает **до** (или вместо) обработчика роута. `express.json()` из прошлого шага — middleware. Напишем свою — счётчик запросов и лог:

**Файл:** `server.js`.

```bash run
cat > server.js <<'EOF'
import express from 'express'

const app = express()
app.use(express.json())

let requestCount = 0
app.use((req, res, next) => {
  requestCount += 1
  console.log(`#${requestCount} ${req.method} ${req.url}`)
  next()
})

app.get('/health', (req, res) => {
  res.json({ status: 'ok', requests: requestCount })
})

app.get('/no-next', (req, res, next) => {
  console.log('этот обработчик ничего не ответил и не вызвал next()')
})

const PORT = process.env.PORT || 3000
app.listen(PORT, () => console.log(`ShareBox слушает порт ${PORT}`))
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/health
echo
curl -s http://localhost:3000/health
echo
timeout 2 curl -s http://localhost:3000/no-next; echo "код выхода curl: $?"
kill $SERVER_PID
```

**Разбор.** `app.use(...)` без пути — выполняется на **каждый** запрос, в порядке объявления. `next()` — «передай управление дальше по цепочке»; забыл вызвать — запрос зависнет без ответа (последний `curl` с `timeout 2` это показывает). Счётчик `requestCount` растёт между запросами — переменная модуля живёт, пока жив процесс.

### result
```out auto
```

### why
Middleware — это то, как в сессию 4 встанет единый обработчик ошибок, в сессию 7 — проверка JWT-токена перед защищёнными роутами, в сессию 10 — rate limit и логирование. Все они — функции вида `(req, res, next)`, и порядок `app.use()` определяет, что выполнится раньше: проверка токена обязана стоять **до** роута, который требует авторизации.

### deep Под капотом
У middleware с четырьмя аргументами — `(err, req, res, next)` — особый смысл: Express распознаёт их как обработчики ошибок и вызывает только при `next(err)` или брошенном исключении внутри `async`-роута. Это и есть единый error handler сессии 4.

### deep Если не получилось
- **Запрос зависает и не отвечает** — обработчик не вызвал ни `res.send()`/`res.json()`, ни `next()` (как в `/no-next`); проверь, что каждая ветка кода либо отвечает, либо передаёт дальше.
- **Middleware «не видит» `req.body`** — стоит раньше `express.json()` в списке `app.use()`; порядок регистрации — это и есть порядок выполнения.

### quiz
- Что произойдёт, если middleware не вызовет ни `res.send()`, ни `next()`?
- В каком порядке выполняются несколько `app.use()` — в порядке объявления или как-то иначе?
- Чем обычный middleware отличается по сигнатуре от обработчика ошибок?

### links
- https://expressjs.com/en/guide/using-middleware.html | middleware подробно | Express: Using middleware

## 3.5 Статика и структура ответа | short: Статика | est: ~20 мин
### intro
**Слова шага:** `express.static` — middleware, отдающее файлы из папки напрямую; *статический файл* — файл, который отдают как есть (картинка, HTML); *код ответа (status code)* — число вроде 200 или 404, которое сервер шлёт вместе с ответом.

Кроме JSON, серверу иногда нужно отдавать обычные файлы — картинку, HTML-страницу (в сессии 9 это будет страница скачивания share-ссылки). `express.static(папка)` — готовый middleware: отдаёт файлы из папки по их имени, без отдельного роута на каждый файл.

**Файлы:** `public/hello.html`, `server.js` (дописать).

```bash run
mkdir -p public
cat > public/hello.html <<'EOF'
<!doctype html>
<meta charset="utf-8">
<h1>ShareBox</h1>
EOF
cat >> server.js <<'EOF'

app.use('/static', express.static('public'))

app.get('/status-demo', (req, res) => {
  res.status(201).json({ created: true })
})
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/static/hello.html
echo
curl -s -o /dev/null -w 'код: %{http_code}\n' http://localhost:3000/status-demo
curl -s -o /dev/null -w 'код: %{http_code}\n' http://localhost:3000/static/нет-такого.html
kill $SERVER_PID
```

### result
```out auto
```

### why
`express.static` избавляет от того, чтобы вручную читать файл с диска и писать заголовки для каждой картинки или HTML-страницы — Express сам выставляет `Content-Type` по расширению, кеш-заголовки и обрабатывает `404`, если файла нет. `res.status(код)` — явное управление кодом ответа, пригодится для `201 Created` при регистрации (сессия 7) и `404`/`410` для share-ссылок (сессия 9).

### deep Если не получилось
- **`Cannot GET /static/hello.html`** — обращение идёт не через префикс `/static`, который задан в `app.use('/static', express.static('public'))`; без префикса Express не знает, что путь ведёт в эту папку.
- **Старое содержимое после правки файла** — `express.static` может кешировать на уровне заголовков для браузера, но сам сервер каждый раз читает файл заново; если не видно изменений, проверь, что сервер перезапущен после правки `server.js`.

### quiz
- Что делает `express.static('public')` и зачем ему нужен префикс `/static` при подключении?
- Чем `res.status(201).json(...)` отличается от простого `res.json(...)`?
- Какой код ответа Express сам выставит для `/static/несуществующий.html`?

### links
- https://expressjs.com/en/starter/static-files.html | статические файлы | Express: Serving static files

## 3.6 Каркас ShareBox: GET /health | short: Каркас проекта | est: ~20 мин
### intro
**Слова шага:** *структура проекта* — файлы и папки, из которых собран ShareBox; `npm install` — поставить зависимости из `package.json`; `.gitignore` — список того, что никогда не попадает в git.

Соберём всё из этой сессии в постоянный каркас ShareBox — он останется на весь курс, следующие сессии будут дописывать в него, не переписывая заново.

**Файлы:** `server.js`, `package.json`, `.gitignore`.

```bash run
cat > server.js <<'EOF'
import express from 'express'

const app = express()
app.use(express.json())
app.use('/static', express.static('public'))

app.use((req, res, next) => {
  console.log(`${req.method} ${req.url}`)
  next()
})

app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() })
})

const PORT = process.env.PORT || 3000
app.listen(PORT, () => console.log(`ShareBox слушает порт ${PORT}`))
EOF
cat > package.json <<'EOF'
{
  "name": "sharebox",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^5.0.0"
  }
}
EOF
cat > .gitignore <<'EOF'
node_modules/
.env
uploads/
EOF
npm install
npm start &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/health
echo
kill $SERVER_PID
```

### result
```out auto
```

### why
С этого момента `server.js` + `package.json` — постоянная точка входа ShareBox. `.gitignore` заранее учитывает то, что появится позже: `.env` (секреты, сессия 4) и `uploads/` (загруженные файлы, сессия 8) — их никогда не кладут в git.

### deep Как ещё можно
- **Не перезапускать сервер руками.** В этой методичке каждый пример останавливает и заново запускает сервер явно (`node server.js & … kill $SERVER_PID`) — так каждый блок воспроизводим и его может проверить скрипт. У себя в терминале так возиться не нужно: `node --watch server.js` (Node 24, без пакетов) сам перезапускает процесс при каждом сохранении файла. То же самое делает пакет `nodemon` (`npm install --save-dev nodemon`, затем `npx nodemon server.js` или скрипт `"dev": "nodemon server.js"` в `package.json`) — он старше и настраивается гибче (например, следит только за нужными папками), но по сути обёртка над `node` с тем же эффектом.

### deep Если не получилось
- **`npm start` не находит скрипт `start`** — сверь `"scripts"` в `package.json`, имя должно быть ровно `start` (зарезервированное — без `run`).
- **Порт занят от прошлого шага** — останови предыдущий `node server.js`/`npm start` (`kill <pid>`) перед новым запуском.

### quiz
- Что произойдёт с `.env` и `uploads/`, если их не внести в `.gitignore` до того, как они появятся?
- Почему `package.json` фиксирует зависимость как `express: "^5.0.0"`, а не просто ставит последнюю версию без ограничений?
- Какую команду теперь использовать для старта ShareBox вместо `node server.js`?

### outro
:::tip Приёмка сессии 3
Ты можешь: поднять Express-приложение и объяснить, что оно даёт поверх `node:http`; прочитать параметр пути и query-строку; получить JSON-тело `POST`-запроса через `express.json()`; написать свой middleware и объяснить роль `next()` и порядок `app.use()`; отдать статический файл и явно задать код ответа. В `/work/sharebox` — постоянный каркас: `server.js`, `package.json` с Express 5, `public/hello.html`, `.gitignore`.
:::

### links
- https://expressjs.com/en/starter/hello-world.html | минимальное приложение Express | Express: Hello world example
