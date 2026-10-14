# Сессия 7 · Эксплуатационная граница
dur: ~4 ч

## 7.1 .env, dotenv и падать сразу | short: Валидация конфига | est: ~25 мин
### intro
**Слова шага:** `.env` — файл с переменными окружения построчно, не попадающий в git; `dotenv` — пакет, который читает `.env` в `process.env` при старте; *fail fast* — упасть сразу при старте с понятной причиной, а не позже, посреди обработки случайного запроса; *обязательная переменная окружения* — без неё приложение не должно вообще подниматься.

Хранить `PORT=4000` в терминале перед каждым запуском неудобно, а пароль от базы (сессия 12) в коде — вообще нельзя: код уходит в git, пароль — нет. Решение — файл **`.env`** и пакет **`dotenv`**, который читает его в `process.env` при старте. Но мало прочитать переменные — если не задан, например, `REQUIRED_SECRET`, тихо продолжать работать нельзя: первый же запрос к базе или проверке подписи упадёт с непонятной ошибкой у случайного пользователя. Правильно — **упасть сразу при старте**, с понятным сообщением. Используем `zod` (сессия 5) и для этого:

**Файлы:** `.env`, `config.js`.

```bash run
cd /work/sharebox
npm install dotenv
cat > .env <<'EOF'
PORT=3000
REQUIRED_SECRET=abc123
EOF
cat > config.js <<'EOF'
import 'dotenv/config'
import { z } from 'zod'

const envSchema = z.object({
  PORT: z.string().default('3000'),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  REQUIRED_SECRET: z.string().min(1, 'REQUIRED_SECRET обязателен'),
})

const parsed = envSchema.safeParse(process.env)
if (!parsed.success) {
  console.error('Неверная конфигурация:')
  for (const issue of parsed.error.issues) console.error(` - ${issue.path.join('.')}: ${issue.message}`)
  process.exit(1)
}

export const config = { ...parsed.data, port: Number(parsed.data.PORT) }
EOF
node -e "import('./config.js').then(({ config }) => console.log(config))"
echo "--- .env без REQUIRED_SECRET ---"
mv .env .env.bak
echo "PORT=3000" > .env
node -e "import('./config.js').then(({ config }) => console.log(config))"; echo "код выхода: $?"
mv .env.bak .env
```

**Разбор.** `import 'dotenv/config'` — импорт ради побочного эффекта (без `from ...`): просто читает `.env` и заполняет `process.env`, до того как остальной код до него обратится — обязан стоять **первой** строкой файла. Первый запуск поднимается (оба поля в `.env`); второй — без `REQUIRED_SECRET` в `.env` — падает с конкретным сообщением, какая переменная и почему. `process.exit(1)` — код выхода, отличный от 0, чтобы внешний оркестратор (Docker, systemd) знал: это не штатное завершение.

### result
```out auto
```

### why
ShareBox в сессии 12 получит `DATABASE_URL`, в сессии 14 — секрет для подписи JWT: оба обязательны и попадут в тот же `.env`, оба должны проверяться этим же способом при старте, а не давать о себе знать первым же сломанным запросом пользователя. На продакшене `.env`-файла может не быть вовсе — переменные задаёт сама система или оркестратор, и `dotenv` тогда просто ничего не находит и не мешает: `process.env` уже заполнен снаружи.

### deep Если не получилось
- **Процесс не падает без `REQUIRED_SECRET`** — проверь, что `.env` на этот момент действительно его не содержит (`cat .env`), а не только переименован файл.
- **`config.port` не видит `.env`** — `import 'dotenv/config'` должен быть **первой** строкой `config.js`, до любого кода, который читает `process.env`.
- **Хочется положить секреты прямо в `config.js`** — так нельзя: `.env` никогда не должен попадать в git (добавим в `.gitignore` в сессии 9, как только появится репозиторий), а любой секрет в коде рано или поздно туда попадёт.

### quiz
- Что делает `import 'dotenv/config'` без `from` и почему он должен стоять первой строкой?
- Чем «упасть сразу при старте» лучше, чем упасть на первом запросе пользователя?
- Что произойдёт с `dotenv`, если `.env`-файла вообще нет, а переменные заданы другим способом (например, оркестратором)?

### links
- https://12factor.net/ru/config | конфигурация через окружение, 12-factor app | The Twelve-Factor App: Config

## 7.2 Graceful shutdown: закончить, а не оборвать | short: Graceful shutdown | est: ~25 мин
### intro
**Слова шага:** `SIGTERM` — сигнал «пожалуйста, завершись» (его шлёт Docker/оркестратор перед остановкой контейнера, в отличие от немедленного `SIGKILL`); *graceful shutdown* — на сигнал перестать принимать новые запросы, но доделать уже начатые, и только потом выйти; `server.close()` — у `node:http`-сервера: перестать принимать новые соединения.

Если просто оборвать процесс по `SIGTERM`, запрос, который был на середине (например, скачивание файла, сессия 15), оборвётся у пользователя на середине. Правильный порядок: перестать принимать **новые** соединения, но не трогать уже идущие:

**Файл:** `graceful-server.js`.

```bash run
cat > graceful-server.js <<'EOF'
import { createServer } from 'node:http'

const server = createServer((req, res) => {
  console.log('начат запрос:', req.url)
  setTimeout(() => {
    res.end('готово\n')
    console.log('закончен запрос:', req.url)
  }, 2000)
})

server.listen(3500, () => console.log('graceful-server на 3500, pid', process.pid))

process.on('SIGTERM', () => {
  console.log('получен SIGTERM, перестаю принимать новые соединения...')
  server.close(() => {
    console.log('все соединения завершены, выхожу')
    process.exit(0)
  })
})
EOF
node graceful-server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3500/slow &
sleep 0.3
echo "отправляю SIGTERM..."
kill -TERM $SERVER_PID
wait
```

**Разбор.** `server.close(callback)` не обрывает уже открытые соединения — он перестаёт принимать **новые** и вызывает `callback`, когда последнее активное соединение закрылось само. В примере запрос, начатый до `SIGTERM`, долетает до конца (`setTimeout` на 2 секунды) — лог покажет «начат» раньше сигнала и «закончен»/«выхожу» уже после него.

### result
```out auto
```

### why
ShareBox в финале части II (сессия 18) запускается в Docker Compose — Docker при остановке контейнера шлёт именно `SIGTERM` (и по таймауту — `SIGKILL`, если процесс не завершился сам). Без обработки `SIGTERM` каждый деплой или рестарт будет обрывать случайные скачивания файлов на середине.

### deep Если не получилось
- **Лог «закончен» не появляется** — проверь, что `wait` в конце блока действительно дожидается фонового `curl`; без него скрипт может завершиться раньше, чем Node напечатает последний лог.
- **Процесс не завершается сам** — в реальном коде (не в тестовом скрипте) добавляют таймаут на принудительный `process.exit(1)`, если `server.close` не управился за разумное время (зависший сокет) — входит в «что дальше».

### quiz
- Чем `SIGTERM` отличается от `SIGKILL` с точки зрения того, может ли процесс на него отреагировать?
- Что делает `server.close()` с уже идущими запросами и с новыми?
- Что увидит пользователь, который в момент остановки сервера на середине скачивает файл — с graceful shutdown и без него?

### links
- https://nodejs.org/api/process.html#signal-events | сигналы процесса | Node.js: process (Signal Events)

## 7.3 /health и /ready | short: Health и ready | est: ~20 мин
### intro
**Слова шага:** `/health` — «процесс жив» (отвечает — значит, event loop не завис); `/ready` — «готов принимать настоящий трафик» (например, база доступна); *liveness vs readiness* — разные вопросы: первый про сам процесс, второй — про его зависимости.

Один `/health` (сессия 1) отвечает на вопрос «процесс вообще жив?». Но что, если процесс жив, а база (появится в сессии 12) ещё не подключилась? Для этого — отдельный `/ready`:

**Файл:** `ready-demo.js`.

```bash run
cat > ready-demo.js <<'EOF'
import { createServer } from 'node:http'

let dbConnected = false
setTimeout(() => { dbConnected = true; console.log('база "подключилась"') }, 1500)

const server = createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200).end('ok')
    return
  }
  if (req.url === '/ready') {
    if (!dbConnected) { res.writeHead(503).end('not ready'); return }
    res.writeHead(200).end('ready')
    return
  }
  res.writeHead(404).end()
})
server.listen(3501, () => console.log('ready-demo на 3501'))
EOF
node ready-demo.js &
SERVER_PID=$!
sleep 0.5
curl -s -o /dev/null -w '/health сразу: %{http_code}\n' http://localhost:3501/health
curl -s -o /dev/null -w '/ready сразу: %{http_code}\n' http://localhost:3501/ready
sleep 2
curl -s -o /dev/null -w '/ready через 2с: %{http_code}\n' http://localhost:3501/ready
kill $SERVER_PID
```

### result
```out auto
```

### why
`/health` сразу `200` — процесс действительно жив с самого старта. `/ready` — `503`, пока «база» не подключилась, и только потом `200`. Оркестратор (Docker Compose `healthcheck`, Kubernetes readiness probe) использует именно `/ready`, чтобы не пускать трафик на под/контейнер, который ещё не готов его обслуживать, даже если сам процесс уже запущен.

### deep Если не получилось
- **`/ready` сразу `200`** — `setTimeout` слишком короткий относительно `sleep` перед первой проверкой; сверь тайминги (0.5с проверка, 1.5с «подключение»).

### quiz
- В чём разница между вопросом `/health` и вопросом `/ready`?
- Что должен вернуть `/ready`, если зависимость (база) недоступна, и какой код?
- Почему недостаточно одного `/health` для настоящего прод-окружения?

### links
- https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ | liveness vs readiness (хотя эта лаба без Kubernetes, идея та же) | Kubernetes: Configure Probes

## 7.4 🔨 Сломать → починить: SIGKILL обрывает скачивание | short: Сломать → починить | est: ~25 мин
### intro
:::trap Сломать → починить
`SIGKILL` (в отличие от `SIGTERM`, шаг 7.2) процесс **не может** перехватить — Node даже не даёт на него подписаться. Убедись в этом и пойми, почему graceful shutdown работает только с `SIGTERM`.
:::

```bash run
cat > unkillable-demo.js <<'EOF'
console.log('пробую подписаться на SIGKILL...')
try {
  process.on('SIGKILL', () => console.log('это никогда не напечатается'))
  console.log('подписка прошла (на этой системе)')
} catch (err) {
  console.log('Node отказался подписывать: ' + err.message)
}
console.log('а теперь SIGTERM — на него подписаться можно:')
process.on('SIGTERM', () => { console.log('SIGTERM поймали, завершаюсь сама'); process.exit(0) })
setInterval(() => {}, 1000) // держим процесс живым, пока не придёт сигнал
EOF
node unkillable-demo.js &
SERVER_PID=$!
sleep 0.5
kill -TERM $SERVER_PID
sleep 0.5
if kill -0 $SERVER_PID 2>/dev/null; then echo "процесс всё ещё жив"; else echo "процесс завершился сам, по SIGTERM"; fi
```

### result
```out auto
```

### why
`process.on('SIGKILL', ...)` либо бросает исключение сразу при попытке подписаться (в этой среде — так), либо, на системах, где подписаться формально разрешено, обработчик всё равно **никогда не вызывается**: `SIGKILL` обрабатывается операционной системой на уровне ниже самого процесса, ему не дают шанса среагировать. `SIGTERM` — другое дело, на него подписка работает и обработчик реально срабатывает. Поэтому graceful shutdown (шаг 7.2) рассчитан именно на `SIGTERM`: оркестратор сначала шлёт его и ждёт (обычно 10–30 секунд), и только если процесс не завершился сам — добивает `SIGKILL`. Если код сервиса долго не завершается после `SIGTERM` (зависший `server.close`), в проде это закончится тем же самым обрывом по таймауту.

### deep Если не получилось
- **«Подписка прошла» вместо отказа** — нормально, поведение зависит от ОС/версии Node; важен вывод ниже про `SIGTERM`, который подписывается и срабатывает в любом случае.
- **`kill -0` не работает так, как ожидалось** — `kill -0` не посылает сигнал, а только проверяет, существует ли процесс с таким PID; это стандартный приём, не ошибка.

### quiz
- Почему обработчик `process.on('SIGKILL', ...)` в примере никогда не вызывается?
- Что оркестратор делает между отправкой `SIGTERM` и `SIGKILL`, и зачем нужна эта пауза?
- Что произойдёт, если код сервиса долго не завершается после `SIGTERM`?

### outro
:::tip Приёмка сессии 7
Ты можешь: заставить приложение падать сразу при старте с понятной причиной, если не хватает обязательной конфигурации; обработать `SIGTERM` и закончить начатые запросы, не принимая новых; объяснить разницу между `/health` и `/ready` и что проверяет каждый; объяснить, почему `SIGKILL` нельзя перехватить и что это значит для таймаутов остановки. В `/work/sharebox`: `config.js`, `graceful-server.js`, `ready-demo.js`, `unkillable-demo.js`.
:::

### links
- https://nodejs.org/api/process.html#signal-events | сигналы процесса (ещё раз, полный список) | Node.js: process (Signal Events)
