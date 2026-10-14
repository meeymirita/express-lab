# 2 · Справочник ошибок: симптом → причина → что делать | short: Справочник ошибок | kind: ref
| Симптом | Причина | Что делать |
|---|---|---|
| `node: command not found` | Node не установлен | `brew install node@24` (Mac) или установщик с nodejs.org |
| `Cannot find module './x'` | опечатка в пути или забыли `./` — без него Node ищет пакет в `node_modules`, а не файл рядом | сверь путь; `./` перед именем файла |
| `ERR_MODULE_NOT_FOUND` | в ESM забыли расширение `.js` в пути импорта — Node, в отличие от CommonJS, его не дописывает | добавь `.js` в конце пути импорта |
| `Cannot use import statement outside a module` | нет `"type": "module"` в ближайшем `package.json` | добавь `"type": "module"` или переименуй файл в `.mjs` |
| `await is only valid in async functions` | `await` вне `async function` и не на верхнем уровне ESM | оберни в `async function`, или проверь `"type": "module"` для top-level await |
| `instanceof` даёт `false` для своего класса | модуль импортирован по двум разным путям — Node считает их разными модулями с разными классами | сверь путь импорта, он должен быть один и тот же символ |
| `EADDRINUSE` | порт уже занят предыдущим незакрытым `server.js` | найди процесс (`ps aux \| grep server.js`) и `kill <pid>` |
| `curl: (7) Failed to connect` | сервер не успел подняться до запроса | `sleep` перед запросом, или сервер и curl — в разных окнах терминала |
| `Cannot find module 'express'` (или другого пакета) | `npm install` выполнен не в той папке | сверь `pwd`, в ней должен быть нужный `package.json` |
| `req.body` — `undefined` | `express.json()` не подключён или подключён **после** роута | `app.use(express.json())` до роутов, которые читают `req.body` |
| `req.query.page` — строка, а не число | все значения query всегда строки | `Number(req.query.page)` перед арифметикой |
| `Cannot GET /путь` | не совпали метод или шаблон роута | сверь метод (`GET`/`POST`) и точное написание пути |
| `config.x` не видит `.env` | `import 'dotenv/config'` не первая строка входного файла | перенеси импорт dotenv в самое начало |
| `err.status` — `undefined` | создан обычный `new Error(...)` вместо своего класса ошибки | используй `AppError`/`NotFoundError` с полем `status` |
| `Cannot find module 'zod'` (или другого пакета) | `npm install` для него не выполнялся | `npm install <пакет>` в папке проекта |
| `req.file` — `undefined` после загрузки | имя поля в форме/`curl -F` не совпадает с `upload.single('имя')` | имя в `-F "имя=@путь"` должно быть тем же, что в `upload.single(...)` |
| `ENOENT` при сохранении загруженного файла | целевая папка не существует — `multer` не создаёт её сам | создай папку (`mkdir -p uploads`) заранее |
| `206` не приходит, всегда `200` | заголовок `Range` не дошёл до сервера | добавь `-H 'Range: bytes=...'` явно в `curl` |
| `ERR_WORKER_PATH` | путь к файлу воркера неверный — `new URL('./x.js', import.meta.url)` работает только из той же папки | сверь, что оба файла (главный и воркера) рядом |
| процесс завершается без объяснений, код выхода не `0` | необработанный `unhandledRejection` — Node с 15+ версии завершает процесс | подпишись на `process.on('unhandledRejection', ...)` и залогируй причину |
| `SIGKILL` «не перехватывается» обработчиком | так и должно быть — `SIGKILL` нельзя перехватить никаким кодом | используй `SIGTERM` для graceful shutdown, `SIGKILL` — только как аварийный таймаут оркестратора |
| процесс не падает без обязательной переменной окружения | валидация конфига при старте не вызвана или не завершает процесс | `envSchema.safeParse(process.env)` + `process.exit(1)` при `!success` |
| повторный `POST` создал вторую сущность вместо одной | идемпотентный ключ не проверен **до** вычисления/записи | `if (seen.has(key)) return seen.get(key)` — раньше, чем сама операция |
| `Error validating datasource` / `URL is no longer supported` (Prisma 7) | в `schema.prisma` остался `url = env(...)` в `datasource` | убери `url` из схемы — он теперь только в `prisma7.config.ts` |
| `Unknown arg 'include' in ...` (Prisma) | связь не описана в схеме под этим именем | сверь имя связи точно как в `schema.prisma` |
| `Drift detected` при `prisma migrate dev` | таблицы уже существуют (созданы сырым SQL), а история миграций Prisma пустая | для учебной базы: `npx prisma migrate reset --force` |
| `PrismaClientValidationError` при поиске по `id` | `id` из `req.params` — строка, а поле в схеме — `Int` | приведи тип: `Number(id)` |
| `JsonWebTokenError: invalid signature` | токен подписан другим `JWT_SECRET` | ожидаемо для «чужого» токена; для «своего» — сверь секрет |
| `401` на защищённом роуте с токеном | заголовок не в формате `Bearer <токен>` (с пробелом) | `Authorization: Bearer ${TOKEN}` |
| `ReferenceError: x is not defined` при старте сервера | функция используется в роуте, но не добавлена в импорт из контроллера | добавь имя в фигурные скобки импорта |
| `port is already allocated` (Docker) | на этом порту хоста уже что-то слушает | останови конфликтующий контейнер или смени левую часть `host:container` |
| `ECONNREFUSED 127.0.0.1:5432` | Postgres не запущена | `docker compose up -d`, проверь `docker compose ps` |
| `password authentication failed` (Postgres) | пользователь/пароль в `DATABASE_URL` не совпадают с `POSTGRES_USER`/`PASSWORD` | сверь оба места дословно |
| `relation "x" already exists` | схема уже создавалась раньше — нормально при повторном прохождении (том пережил перезапуск) | для чистого листа: `docker compose down -v` |
| `relation "x" does not exist` при старте сервера | миграция/создание схемы не вызвано до роутов | проверь, что `migrate()` вызывается первым в `server.js` |
| пул соединений «кончился», запросы зависают (`pg`) | `client.release()` не вызван после запроса, особенно при ошибке | оборачивай `release()` в `finally` |
| `Cannot find module '/work/x/test'` при `node --test test/` | в Node 24 аргумент-путь после `--test` ломает автопоиск тестов | запускай `node --test` без аргумента, или укажи конкретный файл |
| `ECONNREFUSED` внутри теста (supertest) | в тест передан URL строкой вместо объекта приложения | `request(app)`, а не `request('http://localhost:3000')` |
| `npm ci` падает из-за `package-lock.json` | файла нет или он не закоммичен | закоммить `package-lock.json`, он должен лежать рядом с `package.json` |
| `app` не может подключиться к `db` сразу после `docker compose up` | Postgres ещё не готова принимать соединения на первом старте | добавь `healthcheck` у `db` и подожди его в `depends_on` |
| `node-gyp` ошибка при установке `argon2` | пакет содержит нативный код, нужны инструменты сборки | в контейнере лабы они уже есть; на чистом Mac — `xcode-select --install` |
