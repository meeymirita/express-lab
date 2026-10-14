# 1 · Шпаргалка: команды и конструкции | short: Шпаргалка | kind: ref
**Файлы, Buffer, Streams (часть I)**

| Конструкция | Что значит |
|---|---|
| `readFile`/`writeFile`/`mkdir`/`readdir` из `node:fs/promises` | файловые операции, возвращают `Promise` |
| `join(a, b)`, `resolve(p)`, `extname(p)`, `basename(p)`, `dirname(p)` из `node:path` | склейка и разбор путей кроссплатформенно |
| `new EventEmitter()`, `.on('имя', fn)`, `.emit('имя', ...)` | подписка на событие и его вызов |
| `createReadStream(path)`, `createWriteStream(path)`, `.pipe(dst)` | потоковое чтение/запись, `pipe` сам управляет backpressure |
| `Buffer.from('текст', 'utf8')` | кусок байтов из строки |

**Протокол HTTP руками (часть I)**

| Конструкция | Что значит |
|---|---|
| `curl -v URL` | показать весь диалог (`>` — отправлено, `<` — получено) |
| `curl -d 'a=1&b=2' URL` | тело `application/x-www-form-urlencoded` |
| `curl -F 'name=Mira' -F 'file=@путь' URL` | тело `multipart/form-data` |
| `curl -c jar.txt URL`, `curl -b jar.txt URL` | сохранить/отправить cookie как в браузере |
| `curl -s -o /dev/null -w '%{http_code} %{http_version}\n' URL` | только код ответа и версия протокола, без тела |
| `new URL(req.url, 'http://' + req.headers.host)` | разобрать путь и query-строку из `req.url` в `node:http` |

**Процессы и параллелизм (часть I)**

| Конструкция | Что значит |
|---|---|
| `spawn('cmd', [args])`, `.stdout.on('data', ...)`, `.on('close', code)` | запустить внешнюю программу, читать её вывод потоком |
| `new Worker(url, { workerData })`, `parentPort.postMessage(x)` | вынести тяжёлое вычисление в отдельный поток |
| `cluster.isPrimary`, `cluster.fork()` | несколько процессов-копий на одном порту |
| `createHash('sha256').update(data).digest('hex')` | посчитать хеш |
| `randomBytes(n)`, `randomUUID()` | криптографически стойкая случайность (не `Math.random()`) |

**Node: запуск и модули**

| Команда / конструкция | Что делает |
|---|---|
| `node файл.js`, `node` (без файла — REPL) | запустить файл, интерактивная консоль |
| `node --version`, `node --test`, `node --watch файл.js` | версия Node, встроенный тест-раннер (без аргумента!), перезапуск при изменении файла |
| `nodemon файл.js` (`npm install --save-dev nodemon`) | то же, что `node --watch`, но пакетом — старше и гибче в настройке |
| `require('./модуль')`, `module.exports` | CommonJS: подключить, отдать наружу |
| `import x from './модуль.js'`, `export default x`, `export { x }` | ES Modules: нужно расширение `.js`, нужен `"type": "module"` в `package.json` |
| `process.argv`, `process.env.X`, `process.exit(1)` | аргументы командной строки, переменные окружения, выход с кодом |

**npm**

| Команда | Что делает |
|---|---|
| `npm init -y` | создать `package.json` с настройками по умолчанию |
| `npm install пакет`, `npm install --save-dev пакет` | поставить зависимость (прод / только для разработки) |
| `npm run имя-скрипта` | запустить скрипт из `"scripts"` в `package.json` |

**Express: роутер и middleware**

| Конструкция | Что значит |
|---|---|
| `const router = Router(); router.get('/x', h)` | создать роутер, повесить обработчик на `GET /x` |
| `req.params.id`, `req.query.page`, `req.body` | параметр пути, query-строка, тело запроса (после `express.json()`) |
| `app.use(express.json())` | middleware: разобрать JSON-тело в `req.body` |
| `app.use((req, res, next) => { …; next() })` | свой middleware: `next()` — передать дальше, без него запрос «зависнет» |
| `app.use((err, req, res, next) => {...})` | обработчик ошибок — **четыре** аргумента, регистрируется последним |
| `res.status(404).json({ error: 'not_found' })` | код ответа + тело JSON |

**Слои и ошибки**

| Конструкция | Что значит |
|---|---|
| `routes → controllers → services` | роут читает `req`/`res`, контроллер связывает роут и сервис, сервис не знает про HTTP |
| `class AppError extends Error { constructor(msg, status=500) {...} }` | своя ошибка со статус-кодом |
| `throw new NotFoundError(...)`, обработка в едином error handler'е | бросить — поймать один раз, а не в каждом роуте |
| `Schema.safeParse(req.body)` (zod) | валидация без исключений: `{ success, data }` или `{ success: false, error }` |
| `process.env.X` + `dotenv` / `--env-file=.env` | конфигурация вне кода |

**REST и контракт API**

| Конструкция | Что значит |
|---|---|
| `GET /files`, `POST /files`, `GET /files/:id` | ресурс — существительное в URL, действие — в методе |
| `{ "error": "<код>", "message": "<текст>" }` | единый контракт ошибки на всё API |
| `Idempotency-Key` заголовком + `Map`/таблица уже обработанных ключей | повтор `POST` с тем же ключом не создаёт вторую сущность |
| `/v1/...` | версия API в пути |

**PostgreSQL: `pg` и Prisma**

| Конструкция | Что значит |
|---|---|
| `docker compose up -d`, `docker compose ps` | поднять сервисы из `compose.yaml`, посмотреть статус |
| `new pg.Pool({ connectionString: process.env.DATABASE_URL })` | пул соединений с базой |
| `pool.query('SELECT * FROM t WHERE id = $1', [id])` | параметризованный запрос — защита от SQL-инъекций |
| `BEGIN` / `COMMIT` / `ROLLBACK` (или `client.query` с явным клиентом) | транзакция: всё или ничего |
| `npx prisma init`, `npx prisma generate`, `npx prisma migrate dev --name x` | создать проект Prisma, сгенерировать клиент, создать и применить миграцию |
| `prisma.user.findUnique({ where: { id } })`, `.create({ data })`, `.update(...)`, `include: { file: true }` | типовые операции клиента, `include` — подтянуть связанную запись |

**Аутентификация**

| Конструкция | Что значит |
|---|---|
| `await argon2.hash(pwd)`, `await argon2.verify(hash, pwd)` | захешировать пароль, проверить при входе |
| `jwt.sign({ sub: id }, secret, { expiresIn: '15m' })`, `jwt.verify(token, secret)` | выдать токен, проверить и раскодировать |
| `Authorization: Bearer <токен>` | заголовок, в котором клиент присылает access-токен |
| access + refresh, ротация refresh | короткоживущий токен для запросов + долгоживущий для обновления; каждый refresh выдаёт новую пару |

**Файлы**

| Конструкция | Что значит |
|---|---|
| `multer({ storage, limits: { fileSize } })` | middleware загрузки: куда класть файл и лимит размера |
| `createReadStream(path).pipe(res)` | отдать файл потоком, не читая целиком в память |
| `res.setHeader('Content-Disposition', 'attachment; filename="..."')` | подсказать браузеру/curl имя файла при скачивании |
| заголовок `Range: bytes=1000-` → ответ `206 Partial Content` | докачка файла с места обрыва |

**Надёжность и инфраструктура**

| Конструкция | Что значит |
|---|---|
| `rateLimit({ windowMs: 60_000, limit: 30 })` | ограничение частоты запросов, иначе `429` |
| `app.use(helmet())`, `app.use(cors({ origin }))` | заголовки безопасности, разрешённые источники для браузера |
| `pino-http`, `pino()` | структурированные (JSON) логи вместо `console.log` |
| `process.on('SIGTERM', () => { server.close(() => process.exit(0)) })` | graceful shutdown: доделать текущие запросы перед выходом |
| `setInterval(fn, ms)` + `clearInterval` в обработчике сигнала | периодическая фоновая задача, которую можно корректно остановить |

**Тесты и Docker**

| Команда / конструкция | Что значит |
|---|---|
| `node --test` (без пути — сам найдёт `*.test.js` в `test/`) | встроенный тест-раннер Node |
| `test('имя', () => { assert.equal(a, b) })` | один тест; `assert.equal`/`assert.ok` — проверки |
| `request(app).get('/x')` (supertest) | HTTP-запрос прямо в приложение, без реального порта |
| `FROM node:24-alpine`, `COPY`, `RUN npm ci`, `CMD ["node", "server.js"]` | минимальный `Dockerfile` для Node-приложения |
| `docker compose up -d --build` | пересобрать образ и поднять всё описанное в `compose.yaml` |
