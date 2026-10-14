# Сессия 18 · Тесты, Docker, прод-стенд
dur: ~4 ч

## 18.1 node:test: первый тест сервиса | short: node:test | est: ~25 мин
### intro
**Слова шага:** `node:test` — тестовый фреймворк, встроенный прямо в Node; `test()` — объявить один тест с описанием; `assert` — модуль проверок, падает исключением, если условие неверно; *встроенный тест-раннер* — `node --test`, не требует отдельного пакета.

Node 24 включает тест-раннер прямо в себя — не нужен отдельный пакет для базовых тестов. Протестируем чистую функцию без Express и без базы — ровно то, ради чего в сессии 11 слой `services` не знал про `req`/`res`:

**Файл:** `test/errors.test.js`.

```bash run
cd /work/sharebox
mkdir -p test
cat > test/errors.test.js <<'EOF'
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { NotFoundError, AppError } from '../lib/errors.js'

test('NotFoundError имеет статус 404', () => {
  const err = new NotFoundError('нет файла')
  assert.equal(err.status, 404)
  assert.ok(err instanceof AppError)
})

test('AppError по умолчанию — 500', () => {
  const err = new AppError('что-то не так')
  assert.equal(err.status, 500)
})
EOF
node --test
```

**Разбор.** `test('описание', () => {...})` регистрирует один тест; `assert.equal`/`assert.ok` падают исключением, если условие неверно — тест-раннер ловит это и считает тест упавшим. `node --test` без аргументов сам находит все файлы `*.test.js` в папке `test/` и запускает; если передать ему путь к папке явно (`node --test test/`), в Node 24 это, наоборот, ломается — он пытается подключить `test/` как обычный модуль.

### result
```out auto
```

### why
Чистые функции (без `req`/`res`, без сети) — самые дешёвые для теста: не нужно поднимать сервер, не нужна база. Структура routes/controllers/services из сессии 11 не просто «красивая архитектура» — она напрямую определяет, что можно протестировать быстро, а что только через настоящий HTTP-запрос (следующий шаг).

### deep Если не получилось
- **`Cannot find module '../lib/errors.js'`** — путь считается от `test/errors.test.js`; `lib/` на один уровень выше `test/`, поэтому `../lib/...`.
- **Тест «висит», не завершается** — обычно значит, что где-то остался открытый ресурс (соединение с базой, таймер); для чистых функций без побочных эффектов этого не должно происходить.
- **`Cannot find module '/work/sharebox/test'`, если набрать `node --test test/` явно** — не опечатка в пути: в Node 24 аргумент после `--test` ломает автопоиск, Node пытается подключить `test/` как обычный модуль, а не как папку с тестами. Запускай `node --test` без аргументов (или указывай конкретный файл, например `node --test test/errors.test.js`).

### quiz
- Почему `errors.test.js` не требует ни Express, ни базы данных для запуска?
- Что делает `assert.equal`, если переданные значения не совпадают?
- Как `node --test` без аргументов находит, какие файлы запускать?

### links
- https://nodejs.org/api/test.html | справочник по node:test | Node.js: Test runner

## 18.2 supertest: тест HTTP-роута | short: supertest | est: ~30 мин
### intro
**Слова шага:** `supertest` — библиотека для тестирования HTTP-роутов без поднятия сервера; *тест без реального порта* — запрос идёт прямо в приложение, порт не занимается; `request(app)` — отправить тестовый запрос в объект приложения Express.

Для роутов нужен настоящий HTTP-запрос, но поднимать сервер на реальном порту для теста избыточно — **supertest** умеет посылать запрос прямо в Express-приложение, без `app.listen()`.

**Файл:** `test/health.test.js`.

```bash run
npm install --save-dev supertest
cat > test/health.test.js <<'EOF'
import { test } from 'node:test'
import assert from 'node:assert/strict'
import request from 'supertest'
import express from 'express'
import healthRoutes from '../src/routes/health.routes.js'

const app = express()
app.use(healthRoutes)

test('GET /health отвечает 200 и status ok', async () => {
  const res = await request(app).get('/health')
  assert.equal(res.status, 200)
  assert.equal(res.body.status, 'ok')
})

test('GET /nope отвечает 404 (нет такого роута)', async () => {
  const res = await request(app).get('/nope')
  assert.equal(res.status, 404)
})
EOF
node --test
```

**Разбор.** `request(app)` — не `request('http://localhost:3000')`: supertest сам поднимает `app` на случайном свободном порту только на время одного запроса и закрывает — тесты можно гонять параллельно, не беспокоясь о занятых портах. `.get('/health')` возвращает промис с полным ответом — `res.status`, `res.body` (уже распарсенный JSON), `res.headers`.

### result
```out auto
```

### why
Это даёт уверенность не только в том, что функция `getHealthStatus()` возвращает правильный объект (как в 11.1), но и что весь путь — роутинг, middleware, сериализация в JSON — работает вместе. В сессии 11 `/nope` обрабатывал общий 404-middleware — этот тест проверяет именно это поведение, не детали реализации.

### deep Если не получилось
- **`ECONNREFUSED` в тесте** — проверь, что в тест передан `request(app)` (сам объект приложения), а не URL строкой; с URL supertest пытался бы стучаться в реальный порт.
- **Тест ломается на реальной базе** — тесты роутов, которые трогают Prisma (следующий шаг), требуют поднятой PostgreSQL (сессия 12); для `health` она не нужна — поэтому с него и начали.

### quiz
- Чем `request(app)` отличается от обычного `fetch('http://localhost:3000/health')`?
- Что проверяет второй тест (`/nope`) и какая часть кода за это отвечает?
- Зачем вообще нужен supertest, если можно вручную поднять сервер и сделать `fetch`?

### links
- https://www.npmjs.com/package/supertest | документация supertest | npm: supertest

## 18.3 Тест с базой: регистрация и вход | short: Тест с базой | est: ~25 мин
### intro
**Слова шага:** *тестовая база* — та же PostgreSQL, что и для разработки (отдельной тестовой базы в этой лабе нет); *изоляция теста* — тесты не мешают друг другу при повторных запусках; `uniqueEmail()` — свой помощник, который и даёт эту изоляцию: у каждого теста — новый email.

Тест роута авторизации (сессия 14) не обойтись без настоящей базы — регистрация пишет в неё. Используем ту же Postgres из сессии 12, но заботимся об **изоляции**: каждый тест работает со своим уникальным email, чтобы тесты не мешали друг другу при повторном запуске.

**Файл:** `test/auth.test.js`.

```bash run
cat > test/auth.test.js <<'EOF'
import { test } from 'node:test'
import assert from 'node:assert/strict'
import request from 'supertest'
import express from 'express'
import authRoutes from '../src/routes/auth.routes.js'

const app = express()
app.use(express.json())
app.use(authRoutes)
app.use((err, req, res, next) => res.status(err.status || 500).json({ error: err.message }))

function uniqueEmail() {
  return `test-${Date.now()}-${Math.random().toString(36).slice(2, 6)}@mail.com`
}

test('регистрация нового пользователя возвращает 201', async () => {
  const res = await request(app)
    .post('/auth/register')
    .send({ email: uniqueEmail(), password: 'supersecret123' })
  assert.equal(res.status, 201)
})

test('повторная регистрация того же email возвращает 409', async () => {
  const email = uniqueEmail()
  await request(app).post('/auth/register').send({ email, password: 'supersecret123' })
  const res = await request(app).post('/auth/register').send({ email, password: 'supersecret123' })
  assert.equal(res.status, 409)
})

test('вход с неверным паролем возвращает 401', async () => {
  const email = uniqueEmail()
  await request(app).post('/auth/register').send({ email, password: 'supersecret123' })
  const res = await request(app).post('/auth/login').send({ email, password: 'wrong' })
  assert.equal(res.status, 401)
})
EOF
node --test test/auth.test.js
```

### result
```out
(требует базу из сессии 12; у тебя — три прошедших теста, 0 упавших)
```

### why
`uniqueEmail()` — простое решение для изоляции без отдельной тестовой базы (за пределами паспорта лабы, но легко добавить: отдельный `DATABASE_URL` для тестов, очистка таблиц между тестами). Без уникальности второй запуск тестов упал бы на `409 email уже занят`, хотя код на самом деле рабочий — тест был бы «мигающим» (flaky), а это хуже отсутствия теста вообще.

### deep Если не получилось
- **Второй и третий тест падают с `500`, а не ожидаемым кодом** — error handler в тестовом `app` должен быть зарегистрирован **после** `authRoutes`, как в примере; без него Express отдаёт стандартную страницу ошибки вместо JSON с нужным статусом.
- **Тесты накапливают пользователей в базе на каждый запуск** — ожидаемо при этом подходе (без очистки); для реальной работы это стоит дополнить очисткой таблиц между прогонами — за пределами паспорта этой лабы.

### quiz
- Зачем каждому тесту нужен свой уникальный email?
- Что такое «мигающий» (flaky) тест и как в этом примере его избежали?
- Чего не хватает этому подходу для полностью чистого прогона тестов (ответь своими словами)?

### links
- https://nodejs.org/api/test.html#testname-options-fn | опции node:test, включая hooks | Node.js: test runner hooks

## 18.4 Dockerfile для ShareBox | short: Dockerfile | est: ~30 мин
### intro
**Слова шага:** *многоэтапная сборка (multi-stage build)* — `Dockerfile` в несколько стадий, в финальный образ попадает только нужное; `COPY` — скопировать файлы в образ; `EXPOSE` — какой порт слушает контейнер (документирующая директива); *production-зависимости* — пакеты для работы приложения, без dev-инструментов вроде `supertest`.

Соберём ShareBox в образ — не образ лабы (`express/Dockerfile`, который ты использовала для прогона примеров), а образ **самого приложения**:

**Файлы:** `Dockerfile`, `.dockerignore`.

```bash run
cat > Dockerfile <<'EOF'
FROM node:24-alpine AS base
WORKDIR /app

FROM base AS deps
COPY package*.json ./
RUN npm ci --omit=dev

FROM base AS runtime
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npx prisma generate
EXPOSE 3000
USER node
CMD ["node", "server.js"]
EOF
cat > .dockerignore <<'EOF'
node_modules
.env
uploads
test
EOF
docker build -t sharebox:dev .
docker images sharebox
```

**Разбор.** Три стадии (`base`/`deps`/`runtime`) — `deps` ставит **только** production-зависимости (`npm ci --omit=dev`, без `supertest` и прочего, что нужно лишь для разработки) в отдельном слое, а `runtime` копирует уже готовые `node_modules`, не весь `npm install` заново. `USER node` — образ `node` уже содержит непривилегированного пользователя `node`; процесс ShareBox работает не от `root` — меньше вреда при компрометации контейнера.

### result
```out
(требует Docker; у тебя — образ sharebox:dev в списке docker images)
```

### why
`npm ci` (а не `npm install`) в образе — ставит **точно** то, что зафиксировано в `package-lock.json`, без права обновить что-то «на всякий случай»: воспроизводимая сборка. `.dockerignore` — та же идея, что `.gitignore` (сессия 9.6), но для контекста сборки: без него `node_modules` с хоста попал бы в образ поверх уже поставленных внутри, раздувая его и, возможно, принося несовместимые нативные бинарники (argon2, сессия 14 — нативный модуль).

### deep Если не получилось
- **`npm ci` падает с ошибкой о `package-lock.json`** — файл должен существовать и быть закоммичен; он появляется автоматически после любого `npm install` в проекте.
- **Образ собирается очень долго** — `COPY . .` без `.dockerignore` копирует и `node_modules` с хоста (десятки МБ); проверь, что `.dockerignore` создан **до** `docker build`.

### quiz
- Зачем разделять установку зависимостей (`deps`) и финальный образ (`runtime`) на разные стадии?
- Чем `npm ci` отличается от `npm install` и почему это важнее для Docker-образа?
- Зачем нужен `USER node` в конце Dockerfile?

### links
- https://docs.docker.com/build/building/multi-stage/ | многоэтапная сборка | Docker: Multi-stage builds

## 18.5 Compose всего ShareBox и Caddy перед ним | short: Compose + Caddy | est: ~30 мин
### intro
**Слова шага:** *сеть Compose (service discovery)* — сервисы Compose видят друг друга по имени, без IP; *reverse proxy* — сервер-посредник перед приложением (здесь — Caddy); `depends_on` — порядок запуска контейнеров (но не ожидание готовности).

Соберём `compose.yaml`, который поднимает **весь** ShareBox: саму базу (сессия 12) и приложение (прошлый шаг) вместе, плюс Caddy перед ними — если ты уже проходишь Caddy Lab, это узнаваемая картина.

```text
services:
  db:
    image: postgres:18
    environment:
      POSTGRES_USER: sharebox
      POSTGRES_PASSWORD: sharebox
      POSTGRES_DB: sharebox
    volumes:
      - db-data:/var/lib/postgresql

  app:
    build: .
    environment:
      DATABASE_URL: postgresql://sharebox:sharebox@db:5432/sharebox
      JWT_SECRET: change-me-in-production
    depends_on:
      - db
    volumes:
      - uploads-data:/app/uploads

  caddy:
    image: caddy:2
    ports:
      - '80:80'
    volumes:
      - ./Caddyfile:/etc/caddyfile
    command: caddy run --config /etc/caddyfile
    depends_on:
      - app

volumes:
  db-data:
  uploads-data:
```

```text
sharebox.localhost {
  reverse_proxy app:3000
}
```

**Разбор.** `DATABASE_URL` внутри `app` указывает на хост `db`, не `localhost` — в сети Docker Compose каждый сервис виден остальным **по имени сервиса** (service discovery), без IP-адресов. `depends_on` задаёт порядок запуска контейнеров, но **не** ждёт, пока Postgres реально будет готова принимать подключения (`migrate()` в `server.js`, сессия 12.6, сама переживёт пару неудачных попыток при старте — за пределами паспорта лабы можно добавить `healthcheck` и `condition: service_healthy`). Caddy перед `app` — тот же reverse proxy из Caddy Lab, но теперь не демонстрация, а настоящая точка входа ShareBox.

### why
Три сервиса, одна команда `docker compose up`, вся система поднимается по имени сервисов, без ручной настройки сети — это и есть то, ради чего существует Compose: описать систему целиком одним файлом и повторяемо её поднимать, хоть у тебя на Mac, хоть на сервере.

### deep Как ещё можно
Без Caddy можно пробросить порт `app` напрямую (`ports: ['3000:3000']`) и обращаться по `localhost:3000` — для разработки этого достаточно; Caddy добавлен, чтобы показать, как ShareBox встанет в ту же схему, что остальные лабы на сервере владельца.

### deep Если не получилось
- **`app` не может подключиться к `db` — `ECONNREFUSED`** — Postgres может быть ещё не готова принимать соединения в момент первого старта `app`; `depends_on` без `condition: service_healthy` не решает это полностью — в проде добавляют `healthcheck` у `db` и ожидание в `app`.
- **Caddy отдаёт `502 Bad Gateway`** — `app` ещё не поднялся или упал при старте; `docker compose logs app` покажет причину.

### quiz
- Как сервис `app` находит сервис `db` в сети Compose, не зная его IP?
- Что `depends_on` гарантирует, а что — нет?
- Что меняется в `compose.yaml`, если нужно добавить Caddy перед приложением?

### links
- https://docs.docker.com/compose/how-tos/networking/ | сеть в Docker Compose | Docker: Networking in Compose

## 18.6 🔨 Production Hell и сравнение: Express → NestJS | short: Production Hell | est: ~30 мин
### intro
:::trap Production Hell
Без подсказок: в собранном ShareBox (весь код курса) специально внесена одна проблема, типичная для «работает у разработчика, ломается в проде». Найди её по симптому, используя всё, что узнала за курс — логи, код ответа, чтение кода слоями routes → controllers → services.
:::

Симптом: после деплоя (пересборка образа, шаг 18.4, и перезапуск через `docker compose up -d --build`) `POST /files` стабильно отвечает `500`, хотя локально (`npm start` прямо на Mac, без Docker) всё работает.

Подсказки, которые дала бы себе любая опытная разработчица — не ответ, а **направление поиска**: разница между «локально» и «в контейнере» почти всегда в путях, правах или переменных окружения, не в самом коде. Сравни: что видно в `docker compose logs app` в момент ошибки; какой пользователь запускает процесс внутри контейнера (шаг 18.4 — `USER node`); существует ли и доступна ли на запись папка `uploads/` внутри контейнера (сессия 15 — `multer({ dest: 'uploads/' })` пишет относительно рабочей директории процесса).

### why
Это не теоретическое упражнение: ровно такие расхождения — права на папку, несуществующий путь при смене пользователя в контейнере — самая частая причина «работает у меня, не работает в проде» на практике. Диагностика «сверху вниз» (сначала логи, потом код, который в логах упомянут) — тот же навык, что уже тренировался в 🔨-шагах сессий 1 и 4.

### deep Если не получилось
- Если за 20–30 минут решение не нашлось — открой `lib/upload.js` (сессия 15.3) и `Dockerfile` (шаг 18.4) рядом и сравни: какой пользователь создаёт `uploads/` на Mac (твой), и какой пытается писать в неё внутри контейнера (`node`, непривилегированный) — и была ли папка вообще создана **до** `USER node` и с правильными правами.

### deep Express → NestJS: что дальше скрывает фреймворк
Всё, что собрано в ShareBox к этому моменту, — то, что NestJS (следующая лаба после TypeScript) берёт на себя через декораторы и внедрение зависимостей. Таблица — что ты написала руками и чем это станет:

| ShareBox (эта лаба) | NestJS |
|---|---|
| `Router()` + `router.get(...)` (сессия 9) | `@Controller()` + `@Get()` |
| Middleware `(req, res, next)` (сессия 9.4) | `@Injectable()` Guard / Interceptor |
| `routes → controllers → services` руками (сессия 11) | те же слои, но с DI-контейнером, который сам создаёт и передаёт сервисы |
| `zod`-схема и ручная проверка (сессия 11.2) | `class-validator` + Pipe, встроенные в декоратор роута |
| `PrismaClient` с адаптером (сессия 13) | тот же Prisma, обычно через модуль `nestjs-prisma` |
| `requireAuth`/`requireRole` (сессия 14, 17) | Guard с `@UseGuards()` |
| единый error handler (сессия 11.1) | Exception Filter |

Ты не узнаёшь NestJS с нуля — узнаёшь **названия** для вещей, которые уже написала руками и знаешь, зачем они нужны. Это и было целью лабы с самого начала (паспорт: «что потом автоматизирует NestJS»).

### quiz
- Какой лог ты смотришь первым при `500` в проде, но не локально?
- Почему `USER node` в Dockerfile может быть причиной ошибки записи файла, которой не было до его добавления?
- Чему в NestJS соответствует связка `routes → controllers → services`, написанная руками в сессии 11?

### outro
:::tip Приёмка сессии 18 — ShareBox v1 готов
Ты можешь: написать тест чистой функции и тест HTTP-роута через supertest, в том числе с базой; собрать production-образ многоэтапным Dockerfile; поднять весь ShareBox (база + приложение + Caddy) одной командой Compose; найти проблему по логам и коду без прямой подсказки. ShareBox сейчас — рабочий, протестированный, контейнеризованный файлообменник: регистрация, вход, JWT, загрузка и скачивание файлов потоком, share-ссылки с паролем и сроком жизни, админка, rate limit, graceful shutdown. Сессия 19 расширяет его до командного пространства — это ещё не конец курса.
:::

### links
- https://docs.nestjs.com/ | документация NestJS, для следующего шага пути | NestJS: Documentation
