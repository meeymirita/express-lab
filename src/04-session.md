# Сессия 4 · Ошибки, валидация, структура
dur: ~4 ч

## 4.1 Единый обработчик ошибок | short: Error handler | est: ~25 мин
### intro
**Слова шага:** *обработчик ошибок (error handler)* — единое место, куда стекаются все ошибки приложения; `next(err)` — передать ошибку в этот обработчик; *четырёхаргументный middleware* — `(err, req, res, next)` — так Express узнаёт обработчик ошибок.

Сейчас, если внутри роута бросить исключение, Express 5 сам его поймает (в отличие от Express 4, где `async`-ошибки без `try/catch` роняли процесс) и покажет стандартную страницу с HTML-трейсом — некрасиво и небезопасно для продакшена. Нужен **свой** обработчик — middleware с четырьмя аргументами `(err, req, res, next)`, единственный в приложении:

**Файл:** `server.js`.

```bash run
cd /work/sharebox
cat > server.js <<'EOF'
import express from 'express'

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
  res.status(500).json({ error: 'internal', message: 'что-то пошло не так' })
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
Без единого обработчика клиент ShareBox получил бы либо HTML-страницу с деталями исключения (утечка информации о структуре кода), либо, в старых версиях Express, сервер падал бы целиком. Четырёхаргументный middleware — последний в цепочке `app.use()`: до него доходят все ошибки, брошенные синхронно или асинхронно в любом роуте.

### deep Под капотом
Express 5 (в отличие от 4) сам оборачивает `async`-обработчики и передаёт отклонённый промис в `next(err)` — поэтому `throw` внутри `async (req, res) => {...}` и долетает до error handler без ручного `try/catch` в каждом роуте. Это одно из главных отличий версии 5 от 4.

### deep Если не получилось
- **404-обработчик сработал и для `/boom`** — порядок важен: `app.use(404-обработчик)` должен стоять **после** всех настоящих роутов, но **до** error handler'а с 4 аргументами.
- **Ошибка не поймана, видна стандартная HTML-страница Express** — error handler определён не последним или у него не 4 аргумента (3 или меньше — Express не распознает его как обработчик ошибок).

### quiz
- По какому признаку Express понимает, что middleware — это именно обработчик ошибок?
- Почему в Express 5 `throw` внутри `async`-роута долетает до error handler без `try/catch`?
- В каком порядке должны идти обычные роуты, 404-обработчик и error handler?

### links
- https://expressjs.com/en/guide/error-handling.html | обработка ошибок | Express: Error Handling

## 4.2 Свои классы ошибок | short: Классы ошибок | est: ~25 мин
### intro
**Слова шага:** *класс ошибки* — свой тип ошибки со статусом вместо обычного `Error`; `extends Error` — наследование от встроенного класса ошибок; `instanceof` — проверка, к какому классу относится объект; *код ошибки (error code)* — например, `status: 404` у своей ошибки.

`new Error('сообщение')` одинаков для всего — непонятно, 404 это или 403. Сделаем свои классы, каждый со своим HTTP-статусом:

**Файлы:** `lib/errors.js`, `errors-demo.js`.

```bash run
mkdir -p lib
cat > lib/errors.js <<'EOF'
export class AppError extends Error {
  constructor(message, status = 500) {
    super(message)
    this.status = status
  }
}

export class NotFoundError extends AppError {
  constructor(message = 'не найдено') {
    super(message, 404)
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'доступ запрещён') {
    super(message, 403)
  }
}
EOF
cat > errors-demo.js <<'EOF'
import { NotFoundError, AppError } from './lib/errors.js'

const err = new NotFoundError('файл abc123 не существует')
console.log(err.message, '| статус:', err.status)
console.log('это AppError:', err instanceof AppError)
console.log('это обычный Error:', err instanceof Error)
EOF
node errors-demo.js
```

**Разбор.** `extends Error` — наследуем всё поведение `Error` (включая `.stack` — трассировку вызова) и добавляем своё поле `status`. `NotFoundError extends AppError` — иерархия: `instanceof AppError` верно для **любой** ошибки семейства, значит error handler сможет обработать их все одним условием.

### result
```out auto
```

### why
В error handler дальше будет одна проверка: `if (err instanceof AppError) { res.status(err.status)... } else { res.status(500)... }` — своя ошибка (файл не найден, доступ запрещён) отдаёт клиенту понятный статус и сообщение, а непредвиденная (баг, сеть, база) — всегда `500` без утечки деталей.

### deep Если не получилось
- **`err.status` — `undefined`** — создан обычный `new Error(...)` вместо `new NotFoundError(...)`; обычный `Error` не знает про `status`, его добавил только `AppError`.
- **`instanceof` возвращает `false`, хотя класс вроде свой** — обычно означает, что `errors.js` импортирован из двух разных файлов с разным путём (опечатка в `./lib/errors.js`), и это на самом деле два разных модуля в кеше (сессия 1.3) — Node считает их разными классами.

### quiz
- Зачем `NotFoundError` наследуется от `AppError`, а не прямо от `Error`?
- Что добавляет `AppError` к встроенному `Error`?
- Как одной проверкой `instanceof` отличить «ожидаемую» ошибку (ошибка пользователя) от «неожиданной» (баг)?

### links
- https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Error | справочник по Error | MDN: Error

## 4.3 Валидация с zod | short: zod | est: ~25 мин
### intro
**Слова шага:** *валидация* — проверка, что данные от клиента имеют нужную форму; `zod` — библиотека для описания и проверки формы данных; *схема* — описание ожидаемых полей и типов; `safeParse` — проверить данные, не бросая исключение.

Данные из `req.body` — это всегда что угодно, что прислал клиент: без проверки `req.body.email` может оказаться числом, массивом или вовсе отсутствовать. **zod** — библиотека для описания формы данных (**схема**) и проверки по ней:

**Файл:** `zod-demo.js`.

```bash run
npm install zod
cat > zod-demo.js <<'EOF'
import { z } from 'zod'

const RegisterSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
})

const good = RegisterSchema.safeParse({ email: 'a@b.com', password: '12345678' })
console.log('валидно:', good.success)

const bad = RegisterSchema.safeParse({ email: 'не-похоже-на-почту', password: '123' })
console.log('валидно:', bad.success)
if (!bad.success) {
  console.log('ошибки:', bad.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`))
}
EOF
node zod-demo.js
```

**Разбор.** `z.object({...})` описывает форму ожидаемых данных декларативно, а не через ручные `if`. `safeParse` **не бросает исключение** — возвращает объект `{ success, data }` или `{ success: false, error }`; есть и `parse`, который бросает — выбор зависит от того, хочешь ли ты `try/catch` или проверку `if`.

### result
```out auto
```

### why
Регистрация ShareBox (сессия 7) и загрузка файла с параметрами (срок жизни ссылки, пароль — сессия 9) — везде данные от клиента проходят через zod-схему **до** того, как попадут в базу: это не даёт заведомо кривым данным пойти дальше по коду и всплыть непонятной ошибкой на три слоя глубже.

### deep Если не получилось
- **`Cannot find module 'zod'`** — `npm install zod` не выполнен или выполнен не в папке проекта.
- **`bad.error.issues` — пусто или не то** — после неуспешного `safeParse` поле данных называется `error`, а не `data`; `data` появляется только при `success: true`.

### quiz
- Чем `safeParse` отличается от `parse` в плане обработки ошибок?
- Что хранится в `bad.error.issues` и как узнать, какое именно поле не прошло проверку?
- Почему проверка формы данных должна идти **до** записи в базу, а не после?

### links
- https://zod.dev/ | официальная документация | Zod: Documentation

## 4.4 Слои: routes → controllers → services | short: Слои приложения | est: ~30 мин
### intro
**Слова шага:** *слой (layer)* — часть кода с одной ролью (роут, контроллер, сервис); `routes` — какой адрес к какой функции ведёт; `controller` — разбирает `req`, вызывает сервис, собирает `res`; `service` — сама логика, без Express и HTTP вообще; *разделение ответственности* — каждый слой делает одно дело.

Весь код ShareBox пока живёт в одном `server.js`. На пару роутов — нормально, на тридцать — нечитаемо. Разложим по **слоям**: `routes` (какой адрес к какой функции ведёт) → `controllers` (разобрать `req`, вызвать нужную логику, собрать `res`) → `services` (сама логика, без Express вообще — её можно было бы вызвать и из консоли, и из теста).

**Файлы:** `src/services/health.service.js`, `src/controllers/health.controller.js`, `src/routes/health.routes.js`, `server.js`.

```bash run
mkdir -p src/routes src/controllers src/services
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
cat > server.js <<'EOF'
import express from 'express'
import healthRoutes from './src/routes/health.routes.js'

const app = express()
app.use(express.json())
app.use(healthRoutes)

const PORT = process.env.PORT || 3000
app.listen(PORT, () => console.log(`ShareBox слушает порт ${PORT}`))
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/health
echo
kill $SERVER_PID
```

**Разбор.** `Router()` — мини-приложение Express: свой набор роутов, который потом «вшивается» в главный `app` через `app.use(router)`. Стрелка зависимости идёт в одну сторону: `routes` знает про `controllers`, `controllers` — про `services`, а `services` **не знает** про Express вообще — в нём нет ни `req`, ни `res`.

### result
```out auto
```

### why
Эта структура — то, во что дальше лягут все сессии: авторизация (сессия 7) — `auth.service.js` + `auth.controller.js` + `auth.routes.js`; файлы (сессия 8) — та же тройка. `services` без Express — именно то, что в сессии 11 будет напрямую вызываться из тестов `node:test`, без поднятия HTTP-сервера.

### deep Если не получилось
- **`Cannot find module '../services/health.service.js'`** — относительный путь считается от файла, где написан `import`, а не от корня проекта; из `src/controllers/` до `src/services/` — именно `../services/...`.
- **Роут не найден (404 на `/health`)** — `app.use(healthRoutes)` не вызван в `server.js`, или `router.get('/health', ...)` написан с опечаткой.

### quiz
- В какую сторону разрешено «знать друг про друга» между routes, controllers и services, и почему не наоборот?
- Почему `services` не должен принимать `req`/`res` напрямую?
- Что делает `Router()` и как он попадает в основной `app`?

### links
- https://expressjs.com/en/guide/routing.html#express-router | Router в Express | Express: express.Router

## 4.5 .env и переменные конфигурации | short: .env | est: ~20 мин
### intro
**Слова шага:** `.env` — файл с переменными окружения, не попадающий в git; `dotenv` — пакет, который читает `.env` в `process.env`; *секрет* — пароль или ключ, который нельзя хранить в коде; `process.env` — объект со всеми переменными окружения.

Из шага 1.5 ты знаешь `process.env`. Хранить `PORT=4000` в терминале перед каждым запуском неудобно, а пароль от базы (сессия 5) в коде — вообще нельзя: код уходит в git, пароль — нет. Решение — файл `.env` (он уже в `.gitignore`, шаг 3.6) и пакет `dotenv`, который читает его в `process.env` при старте:

**Файлы:** `.env`, `src/config.js`.

```bash run
npm install dotenv
cat > .env <<'EOF'
PORT=3000
APP_NAME=ShareBox
EOF
cat > src/config.js <<'EOF'
import 'dotenv/config'

export const config = {
  port: process.env.PORT || 3000,
  appName: process.env.APP_NAME || 'без имени',
}
EOF
node -e "import('./src/config.js').then((m) => console.log(m.config))"
```

### result
```out auto
```

### why
`import 'dotenv/config'` — импорт ради побочного эффекта (без `from ...`): просто читает `.env` и заполняет `process.env`, до того как остальной код до него обратится. На сервере в продакшене `.env`-файла может не быть вовсе — там переменные окружения задаёт сама система или оркестратор (Docker, Kubernetes), и `dotenv` тогда просто ничего не находит и не мешает — `process.env` уже заполнен снаружи.

### deep Если не получилось
- **`config.port` всегда `3000`, хотя `.env` правили** — `import 'dotenv/config'` должен быть **первой** строкой входного файла, до любого кода, который читает `process.env`; иначе переменные ещё не загружены в момент чтения.
- **`.env` случайно закоммичен** — проверь `git status`: если файл попал в индекс, он не должен был (загляни в `.gitignore` из шага 3.6).

### quiz
- Почему пароль от базы данных хранят в `.env`, а не в коде `server.js`?
- Что делает `import 'dotenv/config'` без `from`?
- Что произойдёт с `dotenv`, если `.env`-файла вообще нет на сервере, а переменные заданы другим способом?

### links
- https://www.npmjs.com/package/dotenv | документация dotenv | npm: dotenv

## 4.6 🔨 Сломать → починить: ошибка без обработчика | short: Сломать → починить | est: ~25 мин
### intro
:::trap Сломать → починить
Соберём всё из сессии в постоянный каркас — error handler, свои ошибки, zod, слои, `.env` — и нарочно забудем зарегистрировать error handler, чтобы увидеть разницу.
:::

Сначала — без error handler, роут кидает `NotFoundError`:

**Файлы:** `src/services/files.service.js`, `src/controllers/files.controller.js`, `src/routes/files.routes.js`, `server.js`.

```bash run
cat > src/services/files.service.js <<'EOF'
import { NotFoundError } from '../../lib/errors.js'

const demoFiles = new Map([['abc123', { id: 'abc123', name: 'report.pdf' }]])

export function getFileOrThrow(id) {
  const file = demoFiles.get(id)
  if (!file) throw new NotFoundError(`файл ${id} не найден`)
  return file
}
EOF
cat > src/controllers/files.controller.js <<'EOF'
import { getFileOrThrow } from '../services/files.service.js'

export function getFile(req, res) {
  const file = getFileOrThrow(req.params.id)
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
cat > server.js <<'EOF'
import express from 'express'
import healthRoutes from './src/routes/health.routes.js'
import filesRoutes from './src/routes/files.routes.js'

const app = express()
app.use(express.json())
app.use(healthRoutes)
app.use(filesRoutes)

const PORT = process.env.PORT || 3000
app.listen(PORT, () => console.log(`ShareBox слушает порт ${PORT}`))
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s -o /dev/null -w 'без error handler, нет такого файла: %{http_code}\n' http://localhost:3000/files/нет-такого
kill $SERVER_PID
```

**Почини** — допиши единый error handler с учётом `AppError`, и `.env` для порта:

**Файл:** `server.js` (дописать).

```bash run
cat >> server.js <<'EOF'

app.use((req, res) => {
  res.status(404).json({ error: 'not_found' })
})

app.use((err, req, res, next) => {
  console.error('поймано:', err.message)
  if (err.status) {
    res.status(err.status).json({ error: err.message })
  } else {
    res.status(500).json({ error: 'internal', message: 'что-то пошло не так' })
  }
})
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/files/abc123
echo
curl -s -o /dev/null -w 'после починки, нет такого файла: %{http_code}\n' http://localhost:3000/files/нет-такого
kill $SERVER_PID
```

### result
```out auto
```

### why
До починки `NotFoundError` долетала до встроенного обработчика Express по умолчанию — клиент видел `500` и HTML-страницу вместо понятного `404`. После — `AppError.status` сам решает код ответа, а структура (routes/controllers/services) и `.env` остаются готовым каркасом для всех следующих сессий.

### deep Если не получилось
- **Всё ещё `500` вместо `404` после починки** — error handler добавлен, но не **последним** в `server.js`, или `NotFoundError` создана без `status` (сверь `lib/errors.js` из шага 4.2).
- **`Cannot find module '../../lib/errors.js'`** — считай уровни вложенности от файла: `src/services/files.service.js` до `lib/errors.js` — на два уровня выше (`../../`), а не один.

### quiz
- Что именно изменилось в ответе сервера до и после регистрации error handler?
- Почему `err.status` появляется только у `AppError` и его потомков, а не у любой ошибки?
- Если добавить ещё один роут, который бросает `ForbiddenError`, что нужно поменять в error handler?

### outro
:::tip Приёмка сессии 4
Ты можешь: написать единый обработчик ошибок и объяснить, по какому признаку Express его находит; создать иерархию своих классов ошибок со статусом; проверить данные схемой zod через `safeParse`; разложить код на routes/controllers/services и объяснить направление зависимостей; вынести конфигурацию в `.env` через `dotenv`. В `/work/sharebox` — структура `src/routes`, `src/controllers`, `src/services`, `lib/errors.js`, `.env`, `src/config.js`.
:::

### links
- https://expressjs.com/en/guide/error-handling.html | обработка ошибок, ещё раз с практикой | Express: Error Handling
