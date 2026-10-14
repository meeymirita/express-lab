# Сессия 17 · Админ и надёжность
dur: ~4 ч

## 17.1 Роль admin и middleware по роли | short: Роль admin | est: ~25 мин
### intro
**Слова шага:** *роль (role)* — поле пользователя (например, `"admin"`), по которому решают доступ; `requireRole` — middleware, пропускающее только пользователей с нужной ролью; *композиция middleware* — несколько проверок подряд, каждая отвечает за одно (`requireAuth` + `requireRole`).

Добавим пользователям роль и middleware, который проверяет не только «есть токен» (`requireAuth`, сессия 14), но и «эта роль разрешена»:

Добавить поле в модель `User` — точечная правка текстового файла; надёжнее не угадывать `sed`-выражением, а явным скриптом, который ищет строку и вставляет рядом (тот же приём, что в сессии 13.5):

**Файлы:** `add-role-field.js`, `lib/role-middleware.js`.

```bash run
cd /work/sharebox
cat > add-role-field.js <<'EOF'
import { readFileSync, writeFileSync } from 'node:fs'
let schema = readFileSync('prisma/schema.prisma', 'utf8')
if (!schema.includes('role ')) {
  schema = schema.replace(
    'passwordHash String   @map("password_hash")',
    'passwordHash String   @map("password_hash")\n  role         String   @default("user")'
  )
  writeFileSync('prisma/schema.prisma', schema)
}
console.log('готово')
EOF
node add-role-field.js
npx prisma migrate dev --name add_user_role
cat > lib/role-middleware.js <<'EOF'
import { AppError } from './errors.js'
import { prisma } from '../src/prisma.js'

export function requireRole(role) {
  return async (req, res, next) => {
    const user = await prisma.user.findUnique({ where: { id: req.user.id } })
    if (!user || user.role !== role) return next(new AppError('недостаточно прав', 403))
    next()
  }
}
EOF
```

### result
```out auto
```

### why
`requireRole('admin')` — пример **композиции** middleware: `requireAuth` узнаёт, кто это, `requireRole('admin')` после него проверяет, что роль подходит — две независимые проверки, каждая делает одно дело (принцип единственной ответственности, пригодится и за пределами этой лабы).

### deep Если не получилось
- **`role` не появилось в базе** — `add-role-field.js` меняет только файл схемы; `npx prisma migrate dev` сразу следом применяет это к реальным таблицам.
- **Скрипт ничего не изменил при повторном запуске** — так и задумано: проверка `if (!schema.includes('role '))` делает правку безопасной для повторного выполнения (идемпотентной) — не продублирует поле, если оно уже есть.

### quiz
- В каком порядке должны стоять `requireAuth` и `requireRole('admin')` в цепочке middleware и почему именно в этом?
- Что произойдёт, если `requireRole('admin')` стоит на роуте без `requireAuth` перед ним?
- Как добавить новую роль, например `'moderator'`, если понадобится позже?

### links
- https://www.prisma.io/docs/orm/prisma-migrate/workflows/schema-evolution | эволюция схемы | Prisma Docs: Schema evolution

## 17.2 Админ-роуты | short: /admin/* | est: ~25 мин
### intro
**Слова шага:** `/admin/*` — префикс админских роутов, защищённых `requireRole('admin')`; *список всех файлов* — файлы всех пользователей, не только своих; *принудительное удаление* — удаление чужого файла без проверки владельца.

Соберём пару админ-роутов: список всех файлов в системе (не только своих) и удаление любого файла.

**Файлы:** `src/services/admin.service.js`, `src/controllers/admin.controller.js`, `src/routes/admin.routes.js`.

```bash run
cat > src/services/admin.service.js <<'EOF'
import { prisma } from '../prisma.js'

export async function listAllFiles() {
  const files = await prisma.file.findMany({ include: { owner: { select: { email: true } } } })
  return files.map((f) => ({ id: f.id, name: f.name, owner: f.owner.email, size: Number(f.sizeBytes) }))
}

export async function forceDeleteFile(fileId) {
  await prisma.file.delete({ where: { id: fileId } })
  return { deleted: true }
}
EOF
cat > src/controllers/admin.controller.js <<'EOF'
import { listAllFiles, forceDeleteFile } from '../services/admin.service.js'

export async function getAllFiles(req, res) {
  res.json(await listAllFiles())
}

export async function adminDeleteFile(req, res) {
  res.json(await forceDeleteFile(Number(req.params.id)))
}
EOF
cat > src/routes/admin.routes.js <<'EOF'
import { Router } from 'express'
import { getAllFiles, adminDeleteFile } from '../controllers/admin.controller.js'
import { requireAuth } from '../../lib/auth-middleware.js'
import { requireRole } from '../../lib/role-middleware.js'

const router = Router()
router.use('/admin', requireAuth, requireRole('admin'))
router.get('/admin/files', getAllFiles)
router.delete('/admin/files/:id', adminDeleteFile)
export default router
EOF
echo "роуты готовы; подключим к server.js и проверим в шаге 17.6 вместе с остальным"
```

### result
```out
(файлы подготовлены; подключение к server.js и проверка запуском — в шаге 17.6)
```

### why
`router.use('/admin', requireAuth, requireRole('admin'))` — применяет обе проверки **ко всем** роутам, начинающимся с `/admin`, одной строкой, вместо повторения в каждом роуте отдельно — Express позволяет вешать middleware на префикс пути, не только глобально (сессия 9.4) или на конкретный роут (сессия 14.4).

### deep Если не получилось
- **`requireRole` не определён** — модуль создан в предыдущем шаге 17.1; если шаги выполнялись не по порядку, вернись туда.
- **Хочется проверить роут сейчас** — он подключится к `server.js` в 10.6 вместе с остальными темами сессии, чтобы не переписывать `server.js` пять раз подряд.

### quiz
- Что делает `router.use('/admin', ...)` в отличие от `router.get('/admin/files', ...)`?
- Какие два middleware применяются ко всем `/admin/*`-роутам и в каком порядке?
- Почему `forceDeleteFile` не проверяет владельца, в отличие от `deleteOwnedFile` из сессии 14?

### links
- https://expressjs.com/en/api.html#router.use | router.use с префиксом | Express: router.use

## 17.3 Rate limit на публичные ссылки | short: Rate limit | est: ~25 мин
### intro
**Слова шага:** *rate limit* — ограничение числа запросов с одного источника за промежуток времени; `express-rate-limit` — пакет, реализующий это ограничение как middleware; `429 Too Many Requests` — код ответа при превышении лимита.

`/s/:code` (сессия 16) доступен без авторизации — значит, его может дёргать скрипт тысячи раз в секунду, перебирая коды или просто нагружая сервер. **Rate limit** — ограничение числа запросов с одного источника за промежуток времени.

**Файл:** `rate-limit-demo.js`.

```bash run
npm install express-rate-limit
cat > rate-limit-demo.js <<'EOF'
import express from 'express'
import rateLimit from 'express-rate-limit'

const app = express()
const limiter = rateLimit({ windowMs: 10_000, limit: 3, standardHeaders: true, legacyHeaders: false })
app.use('/s', limiter)
app.get('/s/:code', (req, res) => res.json({ code: req.params.code }))
app.listen(3000, () => console.log('демо-сервер слушает 3000'))
EOF
node rate-limit-demo.js &
SERVER_PID=$!
sleep 1
for i in 1 2 3 4 5; do
  curl -s -o /dev/null -w "запрос $i: %{http_code}\n" http://localhost:3000/s/anycode
done
kill $SERVER_PID
```

**Разбор.** `windowMs: 10_000, limit: 3` — не больше 3 запросов за 10 секунд с одного IP. `standardHeaders: true` — отдаёт заголовки `RateLimit-*` с остатком лимита (клиент может их читать и не дёргать сервер зря); `legacyHeaders: false` — отключает старый вариант этих же заголовков (`X-RateLimit-*`), чтобы не дублировать.

### result
```out auto
```

### why
Без rate limit один скрипт может перебирать коды share-ссылок (сессия 16.1: `nanoid(8)` — большое, но не бесконечное пространство) или просто забить сервер запросами. Лимит не останавливает атаку полностью, но делает перебор на порядки медленнее и заметнее в логах.

### deep Если не получилось
- **Все 5 запросов вернули `200`** — лимит считается по IP; если тесты запускаются через `--network host` или похожую настройку, все запросы могут идти с одного и того же адреса, что и ожидается — тогда 4-й и 5-й должны были дать `429`; если нет, проверь, что `limiter` подключён именно к `/s`, а не к другому пути.
- **Лимит слишком строгий для реальной работы** — `windowMs`/`limit` настраиваются под ожидаемую нагрузку; значения в примере — учебные, для демонстрации за секунды, не прод-значения.

### quiz
- Что означают `windowMs: 10_000, limit: 3` вместе?
- Какой код ответа получит четвёртый запрос за 10 секунд при этом лимите?
- От какого класса проблем rate limit защищает, а от какого — нет (например, от атаки с тысяч разных IP)?

### links
- https://express-rate-limit.mintlify.app/overview | документация express-rate-limit | express-rate-limit: Overview

## 17.4 helmet, CORS, pino-логи | short: helmet, CORS, логи | est: ~25 мин
### intro
**Слова шага:** `helmet` — middleware, выставляющее защитные HTTP-заголовки по умолчанию; `cors` — middleware, разрешающее запросы с других доменов; *структурированные логи* — записи лога в машиночитаемом формате (JSON); `pino` — быстрый логгер, который их пишет.

Три независимых middleware для надёжности прода: **helmet** выставляет защитные HTTP-заголовки по умолчанию; **cors** разрешает запросы с других доменов (нужно, если фронтенд ShareBox когда-нибудь будет жить отдельно); **pino** — быстрый структурированный логгер (JSON вместо `console.log`-строк — такие логи удобно fильтровать и парсить).

**Файл:** `security-demo.js`.

```bash run
npm install helmet cors pino pino-http
cat > security-demo.js <<'EOF'
import express from 'express'
import helmet from 'helmet'
import cors from 'cors'
import pinoHttp from 'pino-http'

const app = express()
app.use(helmet())
app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }))
app.use(pinoHttp())

app.get('/check', (req, res) => res.json({ ok: true }))
app.listen(3000, () => console.log('демо-сервер слушает 3000'))
EOF
node security-demo.js &
SERVER_PID=$!
sleep 1
curl -s -D - http://localhost:3000/check -o /dev/null | grep -iE 'x-content-type-options|x-frame-options|access-control'
kill $SERVER_PID
```

### result
```out auto
```

### why
`helmet()` закрывает несколько известных классов атак одной строкой (например, `X-Content-Type-Options: nosniff` мешает браузеру угадывать тип файла не по заголовку, а по содержимому — источник части XSS-уязвимостей). `pino-http` автоматически логирует каждый запрос структурированной JSON-строкой — в проде такие логи уходят в систему агрегации логов и по ним ищут, а не читают глазами построчно, как `console.log`.

### deep Если не получилось
- **`cors` блокирует запросы, хотя `origin: '*'`** — `*` разрешает все источники, но **не** работает вместе с `credentials: true` (куки/авторизация) — браузер такое сочетание отклоняет по спецификации; для ShareBox с токенами в заголовке (не в куках) это не проблема.
- **Логи pino выглядят как «нечитаемый JSON»** — это ожидаемо и правильно для прода; при разработке к `pino-http` добавляют `pino-pretty` для читаемого вывода в терминале (за пределами паспорта этой лабы, но легко гуглится при желании).

### quiz
- Что делает `helmet()` одной строкой вместо ручной настройки заголовков?
- Чем структурированный лог (JSON) удобнее для прода, чем `console.log`-строка?
- Почему `cors({ origin: '*' })` не сочетается с куки-авторизацией?

### links
- https://helmetjs.github.io/ | документация helmet | Helmet.js
- https://getpino.io/ | документация pino | Pino: Documentation

## 17.5 Graceful shutdown, health/ready | short: Graceful shutdown | est: ~25 мин
### intro
**Слова шага:** *graceful shutdown* — корректная остановка: доделать начатые запросы, потом выйти; `SIGTERM` — сигнал операционной системы «пора завершиться»; `/health` vs `/ready` — жив ли процесс vs готов ли принимать трафик (например, подключена ли база); *in-flight запрос* — запрос, который уже обрабатывается в момент остановки.

Когда процесс ShareBox останавливают (деплой новой версии, перезапуск контейнера), ему присылают сигнал `SIGTERM`. Без обработки Node завершится немедленно, оборвав запросы, которые как раз были в процессе (**in-flight**). **Graceful shutdown** — поймать сигнал, перестать принимать новые запросы, доделать уже начатые, потом выйти.

Заодно добавим в ShareBox настоящий `/ready`: `/health` (сессия 9.6) отвечает всегда, пока жив процесс, а `/ready` — только если приложение реально готово обслуживать трафик (здесь — подключена база):

**Файлы:** `src/services/health.service.js`, `src/controllers/health.controller.js`, `src/routes/health.routes.js`, `shutdown-demo.js`.

```bash run
cat > src/services/health.service.js <<'EOF'
import { prisma } from '../prisma.js'

export function getHealthStatus() {
  return { status: 'ok', uptime: process.uptime() }
}

export async function getReadyStatus() {
  await prisma.$queryRaw`SELECT 1`
  return { status: 'ready' }
}
EOF
cat > src/controllers/health.controller.js <<'EOF'
import { getHealthStatus, getReadyStatus } from '../services/health.service.js'

export function healthCheck(req, res) {
  res.json(getHealthStatus())
}

export async function readyCheck(req, res) {
  await getReadyStatus()
  res.json({ status: 'ready' })
}
EOF
cat > src/routes/health.routes.js <<'EOF'
import { Router } from 'express'
import { healthCheck, readyCheck } from '../controllers/health.controller.js'

const router = Router()
router.get('/health', healthCheck)
router.get('/ready', readyCheck)
export default router
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/health
echo
curl -s http://localhost:3000/ready
echo
kill $SERVER_PID
cat > shutdown-demo.js <<'EOF'
import express from 'express'

const app = express()
app.get('/slow', async (req, res) => {
  await new Promise((resolve) => setTimeout(resolve, 2000))
  res.json({ done: true })
})

const server = app.listen(3000, () => console.log('демо-сервер слушает 3000'))

process.on('SIGTERM', () => {
  console.log('получен SIGTERM, перестаю принимать новые запросы')
  server.close(() => {
    console.log('все активные запросы завершены, выхожу')
    process.exit(0)
  })
})
EOF
node shutdown-demo.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/slow &
sleep 0.3
kill -TERM $SERVER_PID
wait $SERVER_PID 2>/dev/null
echo "процесс завершился кодом: $?"
```

### result
```out auto
```

### why
`getReadyStatus` делает реальный запрос к базе (`SELECT 1`) — если Postgres недоступна, запрос упадёт исключением, которое долетит до единого error handler (сессия 11) и вернёт `500`, а не `200`: оркестратор (Kubernetes, Docker Swarm) использует именно такую проверку, чтобы не присылать трафик на инстанс, у которого ещё не поднялось соединение с базой при старте. Отдельно от этого — graceful shutdown: без `server.close()` в обработчике `SIGTERM`, запрос `/slow`, стартовавший перед остановкой, получил бы оборванное соединение вместо ответа — для скачивания файла (сессия 15) это означало бы повреждённый файл у получателя в момент каждого деплоя. `server.close()` перестаёт принимать **новые** соединения, но ждёт, пока текущие доделаются.

### deep Если не получилось
- **`/ready` всегда отвечает `200`, даже если явно оборвать Postgres** — проверь, что `getReadyStatus` реально ждёт (`await`) результат запроса, а не просто вызывает `prisma.$queryRaw` без `await` (тогда ошибка никуда не долетит до ответа).
- **Процесс не завершается, зависает** — `server.close(callback)` ждёт завершения **всех** активных соединений; если где-то остался незакрытый долгоживущий запрос (например, зависший `fetch` без таймаута), `close` будет ждать его бесконечно — в проде для этого добавляют таймаут на принудительное завершение.
- **`$?` показывает не `0`** — проверь, что `process.exit(0)` действительно вызван внутри колбэка `server.close(...)`, а не сразу после (это привело бы к выходу до завершения запроса).

### quiz
- Что произойдёт с активным запросом `/slow`, если не обрабатывать `SIGTERM` вообще?
- В чём разница между `/health` (жив ли процесс) и `/ready` (готов ли принимать трафик, например — подключена ли база)?
- Почему `server.close()` не обрывает уже начатые запросы, а только блокирует новые?

### links
- https://nodejs.org/api/net.html#serverclosecallback | server.close | Node.js: net.Server

## 17.6 Чистка просроченного, сборка сессии | short: Чистка и сборка | est: ~25 мин
### intro
**Слова шага:** *фоновая задача* — код, который выполняется сам по расписанию, а не по запросу клиента; `setInterval` — запустить функцию повторно через равные промежутки времени; *чистка просроченных данных* — удаление истёкших share-ссылок, которые больше не нужны.

Истёкшие share-ссылки (сессия 16.2) и их файлы со временем копятся. Напишем периодическую задачу и соберём всю сессию 17 в `server.js`:

**Файлы:** `src/services/cleanup.service.js`, `server.js`.

```bash run
cat > src/services/cleanup.service.js <<'EOF'
import { prisma } from '../prisma.js'

export async function cleanupExpiredShares() {
  const result = await prisma.share.deleteMany({ where: { expiresAt: { lt: new Date() } } })
  if (result.count) console.log(`очищено просроченных ссылок: ${result.count}`)
  return result.count
}
EOF
cat > server.js <<'EOF'
import express from 'express'
import helmet from 'helmet'
import cors from 'cors'
import pinoHttp from 'pino-http'
import rateLimit from 'express-rate-limit'
import healthRoutes from './src/routes/health.routes.js'
import filesRoutes from './src/routes/files.routes.js'
import authRoutes from './src/routes/auth.routes.js'
import sharesRoutes from './src/routes/shares.routes.js'
import adminRoutes from './src/routes/admin.routes.js'
import { migrate } from './src/migrate.js'
import { cleanupExpiredShares } from './src/services/cleanup.service.js'

await migrate()

const app = express()
app.use(helmet())
app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }))
app.use(pinoHttp())
app.use(express.json())
app.use('/s', rateLimit({ windowMs: 60_000, limit: 30 }))

app.use(healthRoutes)
app.use(filesRoutes)
app.use(authRoutes)
app.use(sharesRoutes)
app.use(adminRoutes)

app.use((req, res) => res.status(404).json({ error: 'not_found' }))
app.use((err, req, res, next) => {
  console.error('поймано:', err.message)
  res.status(err.status || 500).json({ error: err.message || 'internal' })
})

const PORT = process.env.PORT || 3000
const server = app.listen(PORT, () => console.log(`ShareBox слушает порт ${PORT}`))

const cleanupTimer = setInterval(cleanupExpiredShares, 60 * 60 * 1000)

process.on('SIGTERM', () => {
  clearInterval(cleanupTimer)
  server.close(() => process.exit(0))
})
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/health
echo
curl -s -o /dev/null -w 'admin без токена: %{http_code}\n' http://localhost:3000/admin/files
kill $SERVER_PID
```

### result
```out auto
```

### why
`setInterval(cleanupExpiredShares, 60 * 60 * 1000)` — раз в час, а не на каждый запрос: чистка — фоновая задача, не связанная с конкретным пользователем. `clearInterval` в обработчике `SIGTERM` — тоже часть graceful shutdown: без него процесс мог бы не завершиться, пока таймер жив.

### deep Если не получилось
- **`admin/files` вернул `404`, а не `401`** — `adminRoutes` не подключён в `server.js`, или путь в `admin.routes.js` не совпадает; `404` значит, что Express вообще не нашёл такой роут.
- **Сервер стартует медленнее обычного** — несколько `npm install` за сессию (`express-rate-limit`, `helmet`, `cors`, `pino`, `pino-http`) — это ожидаемо, не ошибка.

### quiz
- Почему чистку просроченных ссылок запускают по таймеру, а не на каждый входящий запрос?
- Что произойдёт при `SIGTERM`, если убрать `clearInterval(cleanupTimer)` из обработчика?
- Что означает `admin без токена: 401` и какой middleware за это отвечает?

### outro
:::tip Приёмка сессии 17
Ты можешь: добавить роль пользователю и защитить роут по роли; собрать админ-роуты с общим middleware на префикс; поставить rate limit и объяснить `429`; подключить `helmet`, `cors`, структурированные логи `pino`; реализовать graceful shutdown на `SIGTERM`; запустить периодическую фоновую задачу. ShareBox готов почти полностью — осталось сессия 18: тесты, Docker, финал.
:::

### links
- https://expressjs.com/en/advanced/best-practice-performance.html | best practices Express для прода | Express: Production best practices
