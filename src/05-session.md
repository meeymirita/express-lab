# Сессия 5 · Архитектура серверного кода
dur: ~4 ч

## 5.1 Зачем слои: routes → controllers → services | short: Зачем слои | est: ~25 мин
### intro
**Слова шага:** *слой (layer)* — часть кода с одной обязанностью; *route* — знает про HTTP (что пришло, что ответить); *controller* — связывает route и бизнес-логику; *service* — сама логика, ничего не знает про `req`/`res`; *разделение ответственности* — причина, по которой это всё не один файл.

Сервер из сессии 3 — один файл с `if (url.pathname === ...)`. Это нормально для демо, но на 20 роутах превращается в нечитаемую простыню. **Слои** решают это, разделяя по обязанности:

```text
route       — что за HTTP-запрос пришёл, что вернуть (коды, заголовки)
controller  — читает запрос, вызывает service, формирует ответ
service     — сама логика (бизнес-правила), ничего не знает про HTTP
```

Проверка «ничего не знает про HTTP» — не формальность: **service можно вызвать из теста** (сессия 6) без поднятия сервера вообще, а controller — нельзя (ему всегда нужны `req`/`res`).

**Файлы:** `src/services/files.service.js`, `src/controllers/files.controller.js`.

```bash run
cd /work/sharebox
mkdir -p src/services src/controllers
cat > src/services/files.service.js <<'EOF'
const files = new Map()
let nextId = 1

export function listFiles() {
  return [...files.values()]
}

export function addFile(name, size) {
  const id = nextId++
  const file = { id, name, size, createdAt: new Date().toISOString() }
  files.set(id, file)
  return file
}

export function getFile(id) {
  return files.get(id) || null
}
EOF
cat > src/controllers/files.controller.js <<'EOF'
import { listFiles, addFile, getFile } from '../services/files.service.js'

export function listFilesController(req, res) {
  res.writeHead(200, { 'Content-Type': 'application/json' })
  res.end(JSON.stringify(listFiles()))
}

export function getFileController(req, res, id) {
  const file = getFile(Number(id))
  if (!file) {
    res.writeHead(404, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ error: 'not_found' }))
    return
  }
  res.writeHead(200, { 'Content-Type': 'application/json' })
  res.end(JSON.stringify(file))
}
EOF
node -e "
import('./src/services/files.service.js').then(({ addFile, listFiles }) => {
  addFile('report.pdf', 1024)
  addFile('photo.png', 2048)
  console.log(listFiles())
})
"
```

### result
```out auto
```

### why
`files.service.js` сейчас хранит данные в `Map` — заглушка вместо базы (появится в сессии 12), но **контроллеры и роуты не изменятся**, когда `Map` заменится на Prisma: сервис снаружи выглядит так же (те же функции, тот же их смысл), меняется только то, что внутри него. Это и есть цель слоёв — менять один слой, не трогая остальные.

### deep Если не получилось
- **`Cannot find module '../services/...'`** — проверь, что команда выполняется из `/work/sharebox` и структура папок совпадает (`src/services/`, `src/controllers/` — рядом, не вложены друг в друга).
- **Хочется сразу добавить `req`/`res` в service** — это и есть типичная ошибка, которую слои должны предотвратить; если тесту (сессия 6) нужен будет поддельный `req`, значит, что-то не туда положили.

### quiz
- Какой слой можно протестировать без поднятого HTTP-сервера, и почему именно он?
- Что меняется в `files.service.js`, когда данные переедут в PostgreSQL (сессия 12), а что не должно поменяться в контроллере?
- Почему `controller` не стоит превращать в место, где лежит вся бизнес-логика?

### links
- https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html | идея слоёв шире, чем Node | The Clean Architecture

## 5.2 Свои классы ошибок | short: Классы ошибок | est: ~25 мин
### intro
**Слова шага:** *своя ошибка* — класс, наследующий `Error`, с дополнительными полями (например, HTTP-статус); `instanceof` — проверить, какого именно типа ошибка; `cause` — стандартное поле `Error` для «из-за чего» (исходная ошибка, которую мы обернули).

`throw new Error('не найдено')` — работает, но не говорит **какой** код ответа нужен и не отличим от любой другой ошибки без разбора текста. Свои классы решают это:

**Файл:** `lib/errors.js`.

```bash run
cat > lib/errors.js <<'EOF'
export class AppError extends Error {
  constructor(message, status = 500, options = {}) {
    super(message, options)
    this.status = status
  }
}

export class NotFoundError extends AppError {
  constructor(message = 'не найдено') {
    super(message, 404)
  }
}

export class ValidationError extends AppError {
  constructor(message, details = []) {
    super(message, 422)
    this.details = details
  }
}
EOF
node -e "
import('./lib/errors.js').then(({ NotFoundError, ValidationError, AppError }) => {
  const e = new NotFoundError('файл не найден')
  console.log(e.message, e.status, e instanceof AppError, e instanceof Error)
  const v = new ValidationError('плохие данные', ['name обязателен'])
  console.log(v.message, v.status, v.details)
})
"
```

**Разбор.** `extends Error` — своя ошибка остаётся настоящей ошибкой (`instanceof Error` — true, стек вызовов есть), но несёт дополнительные поля. `super(message, options)` с полем `cause` внутри `options` — стандартный способ (ES2022) обернуть исходную ошибку, не потеряв её: `new AppError('не удалось сохранить', 500, { cause: originalErr })`.

### result
```out auto
```

### why
Контроллер (следующий шаг) сможет написать один общий обработчик: `catch (err) { res.writeHead(err.status || 500); ... }` — вместо `if/else` по тексту сообщения. В сессии 9 (Express) это же `status` подхватит общий error handler — тот же класс ошибок, без переписывания.

### deep Если не получилось
- **`e.status` равен `undefined`** — не передан второй аргумент в `super()`/конструктор, или используется базовый `Error` вместо `AppError`.
- **`instanceof NotFoundError` — false там, где ожидала true** — сверь, что класс действительно импортирован из того же файла (два разных файла с одинаковым именем класса — разные классы для JS).

### quiz
- Зачем своей ошибке нужно поле `status`, если можно просто писать `if (err.message === '...')`?
- Что делает `cause` и когда он полезен?
- Что останется true для любой ошибки, унаследованной от `Error`, независимо от доп. полей?

### links
- https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Error/cause | справочник по Error.cause | MDN: Error: cause

## 5.3 Валидация на границе: zod | short: zod | est: ~25 мин
### intro
**Слова шага:** *граница (boundary)* — место, где в систему входят внешние данные (тело запроса, файл, аргументы CLI); `zod` — библиотека схем: описываешь форму данных один раз, получаешь и проверку, и типизированный результат; `safeParse` — проверить данные, не бросая исключение, с объектом `{ success, data | error }`.

Проверять данные `if (!body.name) throw ...` для каждого поля вручную — долго и легко забыть одно поле. **`zod`** описывает форму данных один раз:

**Файл:** `src/schemas/file.schema.js`.

```bash run
npm install zod
mkdir -p src/schemas
cat > src/schemas/file.schema.js <<'EOF'
import { z } from 'zod'

export const createFileSchema = z.object({
  name: z.string().min(1, 'имя обязательно'),
  size: z.number().int().positive('размер должен быть положительным'),
})
EOF
node -e "
import('./src/schemas/file.schema.js').then(({ createFileSchema }) => {
  const ok = createFileSchema.safeParse({ name: 'report.pdf', size: 1024 })
  console.log('валидно:', ok.success, ok.data)
  const bad = createFileSchema.safeParse({ name: '', size: -5 })
  console.log('валидно:', bad.success)
  console.log(bad.error.issues.map((i) => i.message))
})
"
```

**Разбор.** `safeParse` **не бросает** исключение — возвращает объект с `success` и либо `data` (уже проверенные и приведённые к нужным типам значения), либо `error.issues` (список, что именно не так, по каждому полю отдельно). Это удобнее `parse` (который бросает) там, где ошибку нужно аккуратно превратить в ответ 422, а не в падение процесса.

### result
```out auto
```

### why
Граница — единственное место, где данные **нельзя доверять**: они пришли от клиента, который может прислать что угодно. `createFileSchema` дальше (сессия 9) встанет в контроллер ShareBox перед тем, как данные попадут в `files.service.js` — сервис может быть уверен, что получил уже проверенные `name`/`size`, и не должен сам ничего перепроверять.

### deep Если не получилось
- **`npm install zod` долго или не находит пакет** — проверь сеть контейнера; если это временная недоступность реестра, повтори команду.
- **`bad.error` — `undefined`** — поле результата `safeParse` называется `error` только когда `success: false`; при `success: true` его нет, есть `data`.

### quiz
- Чем `safeParse` отличается от `parse` с точки зрения обработки ошибки?
- Почему валидировать нужно именно на границе, а не внутри `files.service.js`?
- Что будет в `ok.data`, если прислать `size: "1024"` (строку, а не число)? Проверь сама.

### links
- https://zod.dev/ | документация zod | zod: Introduction

## 5.4 Собираем сервер на слоях | short: Сервер на слоях | est: ~30 мин
### intro
**Слова шага:** *DI (Dependency Injection) руками* — передавать зависимости (например, функции сервиса) как аргументы, а не брать их из глобального импорта внутри каждого файла — упрощает подмену в тестах (сессия 6).

Соберём всё вместе: роут из сессии 3 вызывает контроллер, контроллер — сервис, ошибки — через классы из шага 5.2, тело запроса — через схему из шага 5.3:

**Файл:** `layered-server.js`, обновлённый `src/controllers/files.controller.js`.

```bash run
cat > src/controllers/files.controller.js <<'EOF'
import { listFiles, addFile, getFile } from '../services/files.service.js'
import { createFileSchema } from '../schemas/file.schema.js'
import { NotFoundError, ValidationError } from '../../lib/errors.js'

export function listFilesController(req, res) {
  res.writeHead(200, { 'Content-Type': 'application/json' })
  res.end(JSON.stringify(listFiles()))
}

export function getFileController(req, res, id) {
  const file = getFile(Number(id))
  if (!file) throw new NotFoundError(`файл ${id} не найден`)
  res.writeHead(200, { 'Content-Type': 'application/json' })
  res.end(JSON.stringify(file))
}

export async function createFileController(req, res) {
  let body = ''
  for await (const chunk of req) body += chunk
  const parsed = createFileSchema.safeParse(JSON.parse(body || '{}'))
  if (!parsed.success) throw new ValidationError('плохие данные', parsed.error.issues.map((i) => i.message))
  const file = addFile(parsed.data.name, parsed.data.size)
  res.writeHead(201, { 'Content-Type': 'application/json' })
  res.end(JSON.stringify(file))
}
EOF
cat > layered-server.js <<'EOF'
import { createServer } from 'node:http'
import { listFilesController, getFileController, createFileController } from './src/controllers/files.controller.js'
import { AppError } from './lib/errors.js'

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`)
    if (url.pathname === '/files' && req.method === 'GET') return listFilesController(req, res)
    if (url.pathname === '/files' && req.method === 'POST') return await createFileController(req, res)
    const m = url.pathname.match(/^\/files\/(\d+)$/)
    if (m && req.method === 'GET') return getFileController(req, res, m[1])
    res.writeHead(404, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ error: 'not_found' }))
  } catch (err) {
    const status = err instanceof AppError ? err.status : 500
    console.error('поймано:', err.message)
    res.writeHead(status, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ error: err.name, message: err.message, details: err.details }))
  }
})
server.listen(3400, () => console.log('layered-server на 3400'))
EOF
node layered-server.js &
SERVER_PID=$!
sleep 1
curl -s -X POST -H 'Content-Type: application/json' -d '{"name":"a.pdf","size":100}' http://localhost:3400/files
echo
curl -s http://localhost:3400/files/1
echo
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3400/files/999
curl -s -X POST -H 'Content-Type: application/json' -d '{"name":"","size":-1}' http://localhost:3400/files
echo
kill $SERVER_PID
```

**Разбор.** `for await (const chunk of req)` — `req` сам асинхронно итерируемый поток (сессия 2 + `js-lab`: `for await` — то же, что `.on('data')`, но без ручной сборки через `Promise`); `try/catch` вокруг всего обработчика — единая точка, куда долетают ошибки любого слоя, и `err.status` (из шага 5.2) решает код ответа.

### result
```out auto
```

### why
Это ровно тот код (минус сам транспорт — в сессии 9 его возьмёт на себя Express), который переедет в ShareBox без переписывания: `files.service.js`, `files.controller.js`, `errors.js`, `file.schema.js` останутся теми же файлами, Express просто подключит их через свой роутинг и свой `(err, req, res, next)` вместо ручного `try/catch`.

### deep Если не получилось
- **`JSON.parse(body || '{}')` падает** — тело не валидный JSON; добавь свой `try/catch` вокруг `JSON.parse`, если хочешь вернуть 400 вместо 500 на кривой JSON (входит в «что дальше»).
- **404 вместо 422 на плохих данных** — проверь регулярку `^\/files\/(\d+)$` — она ловит только числовой `id`, нетиповой путь уйдёт в общий 404 раньше, чем до валидации дойдёт очередь.

### quiz
- Где именно в этом коде происходит валидация, и что случится с данными, если её убрать?
- Как единый `catch` в `layered-server.js` использует `err.status` из шага 5.2?
- Какие из четырёх файлов (`service`, `controller`, `errors`, `schema`) не изменятся, когда в сессии 9 появится Express?

### outro
:::tip Приёмка сессии 5
Ты можешь: объяснить, зачем нужны слои routes/controllers/services и что от них выигрывает тестирование; написать свой класс ошибки со статусом и `cause`; описать форму данных схемой zod и получить понятные ошибки по полям; собрать HTTP-обработчик, который использует все слои вместе через один `try/catch`. В `/work/sharebox`: `src/services/files.service.js`, `src/controllers/files.controller.js`, `lib/errors.js`, `src/schemas/file.schema.js`, `layered-server.js`.
:::

### links
- https://nodejs.org/api/stream.html#async-iterators | `for await` на потоках | Node.js: Streams (async iterators)
