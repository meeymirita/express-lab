# Сессия 6 · Тестирование и отладка
dur: ~4 ч

## 6.1 node:test: первый тест сервиса | short: node:test | est: ~25 мин
### intro
**Слова шага:** `node:test` — тестовый фреймворк, встроенный прямо в Node; `test()` — объявить один тест с описанием; `assert` — модуль проверок, падает исключением, если условие неверно; *встроенный тест-раннер* — `node --test`, не требует отдельного пакета.

Node 24 включает тест-раннер прямо в себя — не нужен отдельный пакет для базовых тестов. Протестируем `lib/errors.js` (сессия 5) — чистый код без HTTP и без базы, ровно то, ради чего слой `service`/`errors` не знал про `req`/`res`:

**Файл:** `test/errors.test.js`.

```bash run
cd /work/sharebox
mkdir -p test
cat > test/errors.test.js <<'EOF'
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { NotFoundError, AppError, ValidationError } from '../lib/errors.js'

test('NotFoundError имеет статус 404', () => {
  const err = new NotFoundError('нет файла')
  assert.equal(err.status, 404)
  assert.ok(err instanceof AppError)
})

test('AppError по умолчанию — 500', () => {
  const err = new AppError('что-то не так')
  assert.equal(err.status, 500)
})

test('ValidationError несёт детали по полям', () => {
  const err = new ValidationError('плохие данные', ['name обязателен'])
  assert.equal(err.status, 422)
  assert.deepEqual(err.details, ['name обязателен'])
})
EOF
node --test
```

**Разбор.** `node --test` сам находит файлы `*.test.js` в `test/` (и рядом с кодом) и запускает их — ничего не нужно подключать вручную. `assert.equal` — строгое сравнение (как `===`), `assert.deepEqual` — сравнение по содержимому для объектов/массивов, `assert.ok` — просто «истина».

### result
```out auto
```

### why
Три теста проверяют код из сессии 5 без единого `curl`, без поднятого сервера — доли секунды вместо HTTP-запроса. Это тот самый сервис/ошибки слой, который **можно** тестировать так дёшево именно потому, что он не знает про `req`/`res` (сессия 5.1).

### deep Если не получилось
- **`Cannot find module '../lib/errors.js'`** — тесты лежат в `test/`, а импорт идёт на уровень выше; проверь относительный путь и что `lib/errors.js` существует (сессия 5).
- **`node --test` ничего не нашёл** — по умолчанию ищет файлы с `.test.js`/`.spec.js` в конце имени; сверь точное имя файла.

### quiz
- Почему эти тесты не требуют поднятого HTTP-сервера?
- Чем `assert.equal` отличается от `assert.deepEqual`?
- Как `node --test` находит файлы с тестами без явной конфигурации?

### links
- https://nodejs.org/api/test.html | справочник по node:test | Node.js: Test runner

## 6.2 Моки и стабы: подменяем зависимость | short: Моки и стабы | est: ~30 мин
### intro
**Слова шага:** *мок (mock)* — поддельная версия зависимости, которая запоминает, как её вызвали; *стаб (stub)* — поддельная версия, которая просто возвращает заранее заданный результат, без проверки вызовов; `t.mock.fn()` — встроенный в `node:test` способ создать мок-функцию.

Тестировать код, который реально ходит в сеть или на диск, — медленно и ненадёжно (сеть может быть недоступна прямо во время теста). **Мок/стаб** подменяет такую зависимость на управляемую подделку. Представим сервис, который при создании файла должен отправить уведомление (представим — реальной отправки пока нет):

**Файлы:** `services/notify.service.js`, `test/notify.test.js`.

```bash run
mkdir -p services
cat > services/notify.service.js <<'EOF'
export async function notifyFileCreated(send, file) {
  await send(`новый файл: ${file.name} (${file.size} байт)`)
  return true
}
EOF
cat > test/notify.test.js <<'EOF'
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { notifyFileCreated } from '../services/notify.service.js'

test('notifyFileCreated вызывает send с текстом уведомления', async (t) => {
  const send = t.mock.fn(async () => {})
  await notifyFileCreated(send, { name: 'report.pdf', size: 1024 })

  assert.equal(send.mock.callCount(), 1)
  assert.match(send.mock.calls[0].arguments[0], /report\.pdf/)
})

test('notifyFileCreated возвращает true, даже если send — стаб без проверки', async () => {
  const send = async () => {}
  const result = await notifyFileCreated(send, { name: 'a.pdf', size: 1 })
  assert.equal(result, true)
})
EOF
node --test
```

**Разбор.** `notifyFileCreated` принимает `send` **аргументом** (DI руками, сессия 5.4), а не импортирует конкретную функцию отправки напрямую — поэтому в тесте можно подставить любую функцию вместо настоящей отправки. `t.mock.fn(...)` — мок: оборачивает функцию и запоминает каждый вызов (`callCount()`, `calls[i].arguments`) — так тест проверяет **как именно** вызвали зависимость. Второй тест обходится обычной функцией-заглушкой (стаб) — просто чтобы `await send(...)` не упал, без проверки вызова.

### result
```out auto
```

### why
Это и есть причина, по которой финальный проект части I требует тестов на моках/стабах: обращение к реальной сети в тесте — нестабильность (упадёт при недоступном интернете) и медленность (десятки сетевых тестов — минуты вместо секунд). DI аргументом — цена этой гибкости, и она того стоит.

### deep Если не получилось
- **`send.mock is undefined`** — функция создана не через `t.mock.fn(...)`, а как обычная `async () => {}`; мок-API доступно только у функций, созданных мок-фабрикой.
- **`assert.match` падает на правильной строке** — регулярка содержит `.` без экранирования там, где нужен буквальный символ (здесь `\.` перед `pdf` — буквальная точка).

### quiz
- Чем мок отличается от стаба с точки зрения того, что можно проверить после вызова?
- Почему `notifyFileCreated` принимает `send` аргументом, а не импортирует функцию отправки сама?
- Что произойдёт с тестом, если `send` будет импортирован жёстко внутри `notifyFileCreated`, а не передан аргументом?

### links
- https://nodejs.org/api/test.html#mocking | мокинг в node:test | Node.js: Test runner (mocking)

## 6.3 Измеряем время: простой профайлинг | short: Измерение времени | est: ~20 мин
### intro
**Слова шага:** `performance.now()` — высокоточное время в миллисекундах (точнее, чем `Date.now()`), не зависит от перевода системных часов; `console.time`/`console.timeEnd` — быстрый замер между двумя точками с подписью.

Прежде чем "оптимизировать" код — нужно измерить, что именно медленно. Самый простой способ — `console.time`:

**Файл:** `perf-demo.js`.

```bash run
cat > perf-demo.js <<'EOF'
import { performance } from 'node:perf_hooks'

console.time('sort-10k')
const arr = Array.from({ length: 10_000 }, () => Math.random())
arr.sort((a, b) => a - b)
console.timeEnd('sort-10k')

const t0 = performance.now()
JSON.stringify(arr)
const t1 = performance.now()
console.log('JSON.stringify заняло:', (t1 - t0).toFixed(2), 'мс')
EOF
node perf-demo.js
```

**Разбор.** `console.time('метка')`/`console.timeEnd('метка')` — удобно для быстрой проверки «эта часть кода медленная?» прямо по ходу разработки. `performance.now()` даёт число, которое можно сохранить, сравнить, записать в лог — когда нужно что-то большее, чем просто напечатать в консоль.

### result
```out auto
```

### why
Для серьёзного профилирования (не «сколько миллисекунд», а «какая именно функция съедает процессор») есть `node --cpu-prof` — он пишет файл профиля, который открывается в Chrome DevTools (вкладка Performance) как флейм-график; в учебных масштабах ShareBox хватает `console.time` и логов из `pino` (сессия 17).

### deep Как ещё можно
`node --inspect server.js` открывает порт отладчика, к которому подключается `chrome://inspect` или DevTools в VS Code — можно ставить точки останова и смотреть переменные вживую, а не только логами; за рамками headless-прогона этой методички, попробуй на своей машине.

### deep Если не получилось
- **Числа каждый раз разные** — нормально: зависит от нагрузки на машину прямо сейчас; важен порядок величины и относительное сравнение «было/стало», а не точное число.

### quiz
- Чем `performance.now()` лучше `Date.now()` для измерения коротких интервалов?
- Когда `console.time`/`console.timeEnd` достаточно, а когда нужен `--cpu-prof`?
- Что показывает флейм-график, которого не видно в простом замере времени?

### links
- https://nodejs.org/learn/getting-started/profiling | профилирование Node | Node.js: Simple profiling

## 6.4 Утечка памяти: растущий кеш | short: Утечка памяти | est: ~25 мин
### intro
**Слова шага:** *утечка памяти (memory leak)* — память, на которую никто больше не ссылается в логике программы, но сборщик мусора не может её освободить, потому что на неё всё ещё есть ссылка откуда-то; *неограниченный кеш* — самый частый источник утечки в серверном коде: «запомним результат», но никогда не забываем.

Самая частая утечка на сервере — кеш, который растёт вечно, потому что в него только кладут и никогда не чистят:

**Файл:** `leak-demo.js`.

```bash run
cat > leak-demo.js <<'EOF'
const cache = new Map() // "утечка": сюда только пишут

function handleRequest(id) {
  if (!cache.has(id)) cache.set(id, { id, data: 'x'.repeat(10000) })
  return cache.get(id)
}

for (let i = 0; i < 50000; i++) handleRequest(i) // 50 000 "разных" запросов
console.log('записей в кеше:', cache.size)
console.log('heapUsed:', Math.round(process.memoryUsage().heapUsed / 1024 / 1024), 'МБ')
EOF
node leak-demo.js
```

**Почини** — ограничь размер кеша (простейший вариант: выбрасывать самую старую запись при превышении лимита):

**Файл:** `bounded-cache-demo.js`.

```bash run
cat > bounded-cache-demo.js <<'EOF'
const MAX_SIZE = 1000
const cache = new Map()

function handleRequest(id) {
  if (!cache.has(id)) {
    if (cache.size >= MAX_SIZE) cache.delete(cache.keys().next().value) // выбросить самую старую запись
    cache.set(id, { id, data: 'x'.repeat(10000) })
  }
  return cache.get(id)
}

for (let i = 0; i < 50000; i++) handleRequest(i)
console.log('записей в кеше:', cache.size)
console.log('heapUsed:', Math.round(process.memoryUsage().heapUsed / 1024 / 1024), 'МБ')
EOF
node bounded-cache-demo.js
```

### result
```out auto
```

### why
Сравни `cache.size` и `heapUsed` в обоих запусках: первый кеш растёт вместе с числом **уникальных** запросов (в реальном сервере — пока не кончится память или процесс не перезапустят), второй держит фиксированный потолок. В ShareBox такого неограниченного кеша по умолчанию нет, но тот же паттерн легко завести случайно (например, "кешируя" результаты проверки share-ссылок, сессия 16, по коду ссылки — кодов может быть сколько угодно).

### deep Если не получилось
- **`heapUsed` в обоих случаях похож** — сборщик мусора (GC) запускается не сразу после каждой операции; `heapUsed` показывает, сколько занято *сейчас*, а не пиковое значение; важнее абсолютной цифры здесь — разница в `cache.size` (50000 против 1000).

### quiz
- Почему первый кеш называют утечкой, если технически это просто `Map`, на которую есть ссылка (переменная `cache`)?
- Что делает `cache.keys().next().value` в починенной версии?
- Придумай свой пример места в ShareBox, где неограниченный кеш мог бы незаметно появиться.

### links
- https://nodejs.org/learn/diagnostics/memory | диагностика памяти в Node | Node.js: Memory diagnostics

## 6.5 🔨 Сломать → починить: необработанный reject роняет процесс | short: Сломать → починить | est: ~25 мин
### intro
:::trap Сломать → починить
Необработанный отклонённый промис в современном Node **завершает процесс целиком**, а не тихо логируется, как раньше. Воспроизведи это, затем почини подпиской на `unhandledRejection`.
:::

**Файл:** `unhandled-demo.js`.

```bash run
cat > unhandled-demo.js <<'EOF'
async function loadConfig() {
  throw new Error('конфиг не найден')
}

loadConfig() // забыли await и .catch
console.log('эта строка ещё печатается')
EOF
node unhandled-demo.js; echo "код выхода: $?"
```

**Почини** — подпишись на событие процесса и реши, что делать (залогировать и завершиться контролируемо — для необработанных ошибок это правильнее, чем продолжать работать в неизвестном состоянии):

**Файл:** `unhandled-fixed.js`.

```bash run
cat > unhandled-fixed.js <<'EOF'
process.on('unhandledRejection', (reason) => {
  console.error('необработанный reject:', reason.message)
  process.exitCode = 1
})

async function loadConfig() {
  throw new Error('конфиг не найден')
}

loadConfig()
console.log('эта строка печатается, процесс не падает сразу')
EOF
node unhandled-fixed.js; echo "код выхода: $?"
```

### result
```out auto
```

### why
Код выхода не `0` в обоих случаях — это правильно: необработанная ошибка **должна** считаться провалом процесса. Разница — в первом случае падение происходит без объяснений (просто обрыв), во втором — с понятным логом, что именно пошло не так, и управляемым `process.exitCode` вместо аварийного краша посреди выполнения. `graceful shutdown` (сессия 7) — следующий шаг этой же идеи: не просто не упасть незаметно, а упасть аккуратно.

### deep Если не получилось
- **Код выхода `0` в первом случае** — версия Node старее 24 или изменено поведение флагом; по умолчанию с Node 15+ необработанный reject завершает процесс не-нулевым кодом.
- **`reason` — не объект `Error`** — промис можно отклонить чем угодно (`Promise.reject('строка')`), тогда `reason.message` будет `undefined`; в реальном коде всегда отклоняй `Error`-объектами, не строками.

### quiz
- Почему необработанный `unhandledRejection` в современном Node завершает процесс, а не просто логируется?
- Чем отличается поведение процесса до и после подписки на `process.on('unhandledRejection', ...)`?
- Что произойдёт, если промис отклонить строкой вместо `Error`-объекта?

### outro
:::tip Приёмка сессии 6
Ты можешь: написать unit-тест на `node:test` для чистого кода без HTTP; подменить зависимость моком и проверить, как её вызвали; отличить мок от стаба; измерить время выполнения куска кода; найти и описать утечку памяти на примере растущего кеша и ограничить её; объяснить, почему необработанный reject завершает процесс, и обработать его. В `/work/sharebox`: `test/errors.test.js`, `test/notify.test.js`, `services/notify.service.js`, `perf-demo.js`, `leak-demo.js` + `bounded-cache-demo.js`, `unhandled-demo.js` + `unhandled-fixed.js`.
:::

### links
- https://nodejs.org/api/process.html#event-unhandledrejection | unhandledRejection | Node.js: process
