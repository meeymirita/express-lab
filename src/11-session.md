# Сессия 11 · Ошибки, валидация, структура
dur: ~4 ч

## 11.1 Единый обработчик ошибок | short: Error handler | est: ~25 мин
### intro
**Слова шага:** *обработчик ошибок (error handler)* — единое место, куда стекаются все ошибки приложения; `next(err)` — передать ошибку в этот обработчик; *четырёхаргументный middleware* — `(err, req, res, next)` — так Express узнаёт обработчик ошибок.

Сейчас, если внутри роута бросить исключение, Express 5 сам его поймает (в отличие от Express 4, где `async`-ошибки без `try/catch` роняли процесс) и покажет стандартную страницу с HTML-трейсом — некрасиво и небезопасно для продакшена. Нужен **свой** обработчик — middleware с четырьмя аргументами `(err, req, res, next)`, единственный в приложении. Используем классы ошибок из сессии 5.2 (`lib/errors.js`) — они уже готовы, просто подключим их:

**Файл:** `server.js`.

```bash run
cd /work/sharebox
cat > server.js <<'EOF'
import express from 'express'
import { AppError } from './lib/errors.js'

const app = express()
app.use(express.json())

app.get('/boom', (req, res) => {
  throw new Error('что-то сломалось')
})

app.get('/boom-async', async (req, res) => {
  await Promise.resolve()
  throw new Error('сломалось асинхронно')
})

app.use((req, res) => {
  res.status(404).json({ error: 'not_found', message: 'такого адреса нет' })
})

app.use((err, req, res, next) => {
  console.error('поймано:', err.message)
  const status = err instanceof AppError ? err.status : 500
  res.status(status).json({ error: err instanceof AppError ? err.constructor.name : 'internal', message: err.message })
})

const PORT = process.env.PORT || 3000
app.listen(PORT, () => console.log(`ShareBox слушает порт ${PORT}`))
EOF
node server.js &
SERVER_PID=$!
sleep 2
curl -s -o /dev/null -w 'boom: %{http_code}\n' http://localhost:3000/boom
curl -s -o /dev/null -w 'boom-async: %{http_code}\n' http://localhost:3000/boom-async
curl -s -o /dev/null -w 'нет такого пути: %{http_code}\n' http://localhost:3000/nope
kill $SERVER_PID
```

### result
```out auto
```

### why
Без единого обработчика клиент ShareBox получил бы либо HTML-страницу с деталями исключения (утечка информации о структуре кода), либо, в старых версиях Express, сервер падал бы целиком. `err instanceof AppError` (сессия 5.2) отличает ожидаемую ошибку (знаем статус) от неожиданной (всегда `500`, без утечки деталей) — ровно та же проверка, что в сессии 5.4 стояла в ручном `try/catch`, здесь её делает Express за тебя через `next(err)`.

### deep Под капотом
Express 5 (в отличие от 4) сам оборачивает `async`-обработчики и передаёт отклонённый промис в `next(err)` — поэтому `throw` внутри `async (req, res) => {...}` и долетает до error handler без ручного `try/catch` в каждом роуте. Это одно из главных отличий версии 5 от 4.

### deep Если не получилось
- **404-обработчик сработал и для `/boom`** — порядок важен: `app.use(404-обработчик)` должен стоять **после** всех настоящих роутов, но **до** error handler'а с 4 аргументами.
- **Ошибка не поймана, видна стандартная HTML-страница Express** — error handler определён не последним или у него не 4 аргумента (3 или меньше — Express не распознает его как обработчик ошибок).

### quiz
- По какому признаку Express понимает, что middleware — это именно обработчик ошибок?
- Почему в Express 5 `throw` внутри `async`-роута долетает до error handler без `try/catch`?
- Чем `err instanceof AppError` здесь полезнее, чем было бы сравнение `err.message` с конкретным текстом?

### links
- https://expressjs.com/en/guide/error-handling.html | обработка ошибок | Express: Error Handling

## 11.2 Валидация как middleware | short: Валидация-middleware | est: ~25 мин
### intro
**Слова шага:** *middleware-валидатор* — функция, которая проверяет `req.body` по схеме **до** контроллера и либо пропускает дальше, либо сразу отвечает `422`; `req.body` — Express уже разобрал тело за тебя через `express.json()` (сессия 9), в отличие от ручного `for await` в сессии 5.4.

zod-схему для файла ты уже написала в сессии 5.3 (`src/schemas/file.schema.js`). В Express её не нужно переписывать — нужно **обернуть** в middleware, который применяется к любому роуту одной строкой:

**Файл:** `src/middleware/validate.js`.

```bash run
mkdir -p src/middleware
cat > src/middleware/validate.js <<'EOF'
import { ValidationError } from '../../lib/errors.js'

export function validate(schema) {
  return (req, res, next) => {
    const parsed = schema.safeParse(req.body)
    if (!parsed.success) {
      return next(new ValidationError('плохие данные', parsed.error.issues.map((i) => i.message)))
    }
    req.body = parsed.data // уже проверенные и приведённые к типам значения
    next()
  }
}
EOF
cat >> server.js <<'EOF'

import { createFileSchema } from './src/schemas/file.schema.js'
import { validate } from './src/middleware/validate.js'

app.post('/files', validate(createFileSchema), (req, res) => {
  res.status(201).json({ id: 1, ...req.body })
})
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s -X POST -H 'Content-Type: application/json' -d '{"name":"a.pdf","size":100}' http://localhost:3000/files
echo
curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -d '{"name":"","size":-1}' http://localhost:3000/files
kill $SERVER_PID
```

**Разбор.** `validate(schema)` — фабрика middleware: принимает схему **аргументом** (DI, сессия 5.4) и возвращает готовую функцию `(req, res, next)`. `next(new ValidationError(...))` передаёт ошибку в error handler из шага 11.1 — тот же путь, что и для `throw` в обычном роуте. `req.body = parsed.data` — подменяет сырые данные на уже проверенные: следующий обработчик получает гарантированно верную форму.

### result
```out auto
```

### why
Одна функция `validate(schema)` работает для любой схемы — регистрации (сессия 14), создания файла, создания share-ссылки (сессия 16): не нужно в каждом роуте писать `safeParse` и `if` заново, как в сессии 5.4 на голом Node.

### deep Если не получилось
- **Валидные данные тоже возвращают 422** — проверь, что `Content-Type: application/json` передан в запросе: без него `express.json()` не распарсит тело, и `req.body` окажется пустым объектом.
- **`ValidationError is not defined`** — забыт импорт `ValidationError` из `../../lib/errors.js` в `src/middleware/validate.js`.

### quiz
- Что делает `validate(schema)` до того, как запрос попадёт в обработчик роута?
- Чем `req.body` после `validate(schema)` отличается от того, что прислал клиент?
- Почему одну и ту же функцию `validate` можно использовать для разных схем, не копируя её?

### links
- https://expressjs.com/en/guide/writing-middleware.html | своё middleware в Express | Express: Writing middleware

## 11.3 Переносим слои в Express | short: Слои в Express | est: ~30 мин
### intro
**Слова шага:** `Router()` — мини-приложение Express со своим набором роутов, которое потом «вшивается» в главный `app`; *перенос без переписывания* — `services` и классы ошибок остаются теми же файлами, меняется только то, как к ним обращается транспортный слой.

Слои `services`/`controllers` из сессии 5 были написаны на голом `node:http`. Разница с Express — только в том, как контроллер читает вход и пишет ответ; сам `files.service.js` не меняется вообще. Заодно вынесем в те же слои и `/health` (сейчас — инлайн в `server.js`, шаг 9.6):

**Файлы:** `src/services/health.service.js`, `src/controllers/health.controller.js`, `src/routes/health.routes.js`, `src/routes/files.routes.js`, обновлённый `src/controllers/files.controller.js`.

```bash run
mkdir -p src/routes src/services
cat > src/services/health.service.js <<'EOF'
export function getHealthStatus() {
  return { status: 'ok', uptime: process.uptime() }
}
EOF
cat > src/controllers/health.controller.js <<'EOF'
import { getHealthStatus } from '../services/health.service.js'

export function healthCheck(req, res) {
  res.json(getHealthStatus())
}
EOF
cat > src/routes/health.routes.js <<'EOF'
import { Router } from 'express'
import { healthCheck } from '../controllers/health.controller.js'

const router = Router()
router.get('/health', healthCheck)
export default router
EOF
cat > src/controllers/files.controller.js <<'EOF'
import { getFile as findFile } from '../services/files.service.js'
import { NotFoundError } from '../../lib/errors.js'

export function getFile(req, res) {
  const file = findFile(Number(req.params.id))
  if (!file) throw new NotFoundError(`файл ${req.params.id} не найден`)
  res.json(file)
}
EOF
cat > src/routes/files.routes.js <<'EOF'
import { Router } from 'express'
import { getFile } from '../controllers/files.controller.js'

const router = Router()
router.get('/files/:id', getFile)
export default router
EOF
cat >> server.js <<'EOF'

import healthRoutes from './src/routes/health.routes.js'
import filesRoutes from './src/routes/files.routes.js'
import { addFile } from './src/services/files.service.js'
addFile('seed.pdf', 10) // чтобы было что получить по id ниже
app.use(healthRoutes)
app.use(filesRoutes)
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/health
echo
curl -s http://localhost:3000/files/1
echo
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/files/999
kill $SERVER_PID
```

**Разбор.** `getFile as findFile` при импорте — сервис и контроллер по соглашению называются одинаково (`getFile`), поэтому сервисную функцию переименовываем на входе, чтобы не столкнуться с собственным экспортом контроллера. Сравни этот контроллер с версией из сессии 5.4: там `res.writeHead(200, {...}); res.end(JSON.stringify(...))` и ручной `try/catch` вокруг всего обработчика — здесь `res.json(...)` и `throw` без обёртки, потому что Express 5 сам отправит исключение в error handler (шаг 11.1). `files.service.js` — **тот же файл**, не тронут вообще; именно это и обещал слой `service` в сессии 5.1, не знающий про HTTP (список и создание файла остаются на стороне голого `node:http` из сессии 5 — здесь для переноса взят один роут, остальное ShareBox получит заново, уже на реальной базе, в сессии 12).

### result
```out auto
```

### why
Это главный вывод части I → часть II: слои, спроектированные без фреймворка, не выбрасываются при переходе на фреймворк — Express берёт на себя транспорт (парсинг тела, роутинг по regex-параметрам пути, отправку ошибки в error handler), а бизнес-логика и её проверка остаются ровно тем кодом, что был написан раньше.

### deep Если не получилось
- **`Cannot find module '../services/files.service.js'`** — проверь, что сессия 5 действительно оставила этот файл в `/work/sharebox/src/services/` (не удалён, не переименован).
- **`req.params.id` — строка, а не число** — это нормально, параметры пути в Express всегда строки; `Number(...)` в контроллере переводит явно, как и раньше в сессии 3.2.

### quiz
- Какой файл не изменился при переносе на Express, а какой пришлось переписать и почему?
- Чем `throw new NotFoundError(...)` в Express-контроллере отличается от того же `throw` в обработчике голого `node:http` (сессия 5.4) с точки зрения того, что дальше его ловит?
- Что делает `Router()` и как он попадает в основной `app`?

### links
- https://expressjs.com/en/guide/routing.html#express-router | Router в Express | Express: express.Router

## 11.4 🔨 Сломать → починить: забытый порядок middleware | short: Сломать → починить | est: ~25 мин
### intro
:::trap Сломать → починить
Порядок `app.use()` в Express не случаен: поставь error handler **до** роутов — и он никогда не сработает, роуты просто не дойдут до него по цепочке. Воспроизведи и почини.
:::

```bash run
cat > broken-order.js <<'EOF'
import express from 'express'
import { AppError, NotFoundError } from './lib/errors.js'

const app = express()

// ОШИБКА: error handler стоит до роута
app.use((err, req, res, next) => {
  res.status(err instanceof AppError ? err.status : 500).json({ error: 'caught', message: err.message })
})

app.get('/boom', (req, res) => {
  throw new NotFoundError('специально для примера')
})

app.listen(3600, () => console.log('broken-order на 3600'))
EOF
node broken-order.js &
SERVER_PID=$!
sleep 1
curl -s -o /dev/null -w 'до починки: %{http_code}\n' http://localhost:3600/boom
kill $SERVER_PID
```

**Почини** — error handler переезжает в конец, после всех роутов:

```bash run
cat > fixed-order.js <<'EOF'
import express from 'express'
import { AppError, NotFoundError } from './lib/errors.js'

const app = express()

app.get('/boom', (req, res) => {
  throw new NotFoundError('специально для примера')
})

// error handler — последним
app.use((err, req, res, next) => {
  res.status(err instanceof AppError ? err.status : 500).json({ error: 'caught', message: err.message })
})

app.listen(3601, () => console.log('fixed-order на 3601'))
EOF
node fixed-order.js &
SERVER_PID=$!
sleep 1
curl -s -o /dev/null -w 'после починки: %{http_code}\n' http://localhost:3601/boom
kill $SERVER_PID
```

### result
```out auto
```

### why
Express проходит middleware и роуты **по порядку регистрации**, сверху вниз — это не похоже на обычный JS, где порядок объявления функций обычно не важен, и легко забыть, когда в проекте уже десяток `app.use()`. Error handler, зарегистрированный раньше роута, который бросает ошибку, просто никогда до неё не доходит — она улетает дальше, во встроенный обработчик Express по умолчанию.

### quiz
- Почему `/boom` до починки не получает `404` от своего собственного error handler?
- В каком порядке Express проверяет middleware и роуты — по типу (сначала все роуты, потом все error handler'ы) или по порядку регистрации в коде?
- Если в проекте несколько роутов в разных файлах (как в шаге 11.3), где физически должен стоять `app.use(errorHandler)` относительно всех `app.use(routes)`?

### outro
:::tip Приёмка сессии 11
Ты можешь: написать единый обработчик ошибок, использующий классы из сессии 5, и объяснить, по какому признаку Express его находит; обернуть zod-схему в переиспользуемое middleware для валидации; перенести слои routes/controllers/services на Express, не переписывая `service`; объяснить, почему порядок `app.use()` критичен. В `/work/sharebox`: `src/middleware/validate.js`, `src/routes/files.routes.js`, обновлённые `src/controllers/files.controller.js` и `server.js`.
:::

### links
- https://expressjs.com/en/guide/using-middleware.html | порядок middleware | Express: Using middleware
