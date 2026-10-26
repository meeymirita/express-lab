# Сессия 4 · Процессы и параллелизм
dur: ~4 ч

## 4.1 child_process: запускаем внешнюю команду | short: child_process | est: ~25 мин
### intro
**Слова шага:** `child_process` — модуль для запуска других программ из Node; `spawn` — запустить процесс и получить его вывод потоком (сессия 2); `exec` — запустить и получить весь вывод целиком, когда он короткий; *код выхода (exit code)* — число, которым процесс сообщает «ОК» (0) или «ошибка» (не 0).

Node не обязан делать всё сам — иногда проще вызвать готовую программу. **`spawn`** возвращает процесс как поток (для длинного или большого вывода), **`exec`** — удобнее для короткой команды, чей вывод нужен целиком:

**Файл:** `spawn-demo.js`.

```bash run
cd /work/sharebox
cat > spawn-demo.js <<'EOF'
import { spawn } from 'node:child_process'

const child = spawn('ls', ['-la', 'lib'])

child.stdout.on('data', (chunk) => process.stdout.write(chunk))
child.stderr.on('data', (chunk) => process.stderr.write(chunk))
child.on('close', (code) => console.log('процесс завершился с кодом:', code))
EOF
node spawn-demo.js
```

**Разбор.** `child.stdout`/`child.stderr` — читаемые потоки (сессия 2), `close` — событие завершения с кодом выхода. Если программа не найдена или упала — код выхода не `0`, и это надо проверять, а не считать, что раз `spawn` не бросил исключение, значит всё прошло успешно.

### result
```out auto
```

### why
`sha256sum`, `tar`, системные утилиты для PDF или картинок — всё это проще вызвать `spawn`, чем переписывать на JS. ShareBox этим не пользуется напрямую, но то же самое API — у `docker`, `git` и любых CLI-обёрток на Node.

### deep Если не получилось
- **`ENOENT`** — команда не найдена (в `node:24-alpine` минимальный набор утилит; `ls` есть, экзотических команд может не быть).
- **Вывод не появляется** — `spawn` асинхронный; вывод приходит по мере готовности, а не сразу всей пачкой.

### quiz
- Чем `spawn` отличается от `exec` с точки зрения того, как возвращается вывод?
- Что означает код выхода `0` и что означает любой другой?
- Через какие объекты можно прочитать stdout и stderr дочернего процесса?

### links
- https://nodejs.org/api/child_process.html | справочник по child_process | Node.js: Child Process

## 4.2 Event loop и тяжёлые вычисления | short: Блокировка event loop | est: ~25 мин
### intro
**Слова шага:** *блокировка event loop* — синхронный код, который долго не отдаёт управление, из-за чего Node не может обработать другие запросы; *CPU-bound* — задача, упирающаяся в процессор, а не в ожидание сети/диска.

Node однопоточный (`js-lab`): пока выполняется **синхронный** код, event loop не может заняться ничем другим — даже ответить на другой HTTP-запрос. Покажем это на сервере с одним медленным обработчиком:

**Файл:** `blocking-server.js`.

```bash run
cat > blocking-server.js <<'EOF'
import { createServer } from 'node:http'

function slowSum(n) {
  let total = 0
  for (let i = 0; i < n; i++) total += i
  return total
}

const server = createServer((req, res) => {
  if (req.url === '/slow') {
    const result = slowSum(5_000_000_000)
    res.end(`сумма: ${result}\n`)
    return
  }
  res.end('быстрый ответ\n')
})
server.listen(3300, () => console.log('blocking-server на 3300'))
EOF
node blocking-server.js &
SERVER_PID=$!
sleep 1
(curl -s http://localhost:3300/slow &)
sleep 0.3
time curl -s http://localhost:3300/
kill $SERVER_PID
```

### result
```out auto
```

### why
Второй запрос (`/`, обычно мгновенный) ждёт столько же, сколько считается `/slow` — event loop занят одним синхронным циклом и физически не может переключиться на другой запрос, пока цикл не закончится. Для ShareBox это значит: тяжёлые вычисления (например, хеширование очень большого файла, сессия 15) синхронным кодом в обработчике запроса **заблокируют всех остальных пользователей**.

### deep Если не получилось
- **Второй `curl` не выглядит медленным** — число `5_000_000_000` подобрано для заметной задержки (секунды); если машина быстрая, увеличь его на порядок.
- **`time` не печатает результат** — `time` в примере меряет именно `curl`, а не весь скрипт; проверь, что он стоит отдельной командой перед `curl`, как в примере.

### quiz
- Почему второй запрос ждёт столько же, сколько считается первый, хотя они не связаны логикой?
- Чем CPU-bound задача отличается от ожидания сети или диска с точки зрения event loop?
- Что произойдёт с остальными пользователями ShareBox, если один обработчик считает что-то синхронно и долго?

### links
- https://nodejs.org/en/learn/asynchronous-work/dont-block-the-event-loop | Don't Block the Event Loop | Node.js: Don't Block the Event Loop

## 4.3 worker_threads: выносим вычисление в отдельный поток | short: worker_threads | est: ~30 мин
### intro
**Слова шага:** `worker_threads` — модуль для настоящих параллельных потоков внутри одного процесса Node; `Worker` — отдельный поток со своим event loop; `postMessage`/`on('message')` — обмен сообщениями между главным потоком и воркером; *копирование, а не общая память* — сообщения между потоками копируются (кроме специальных `SharedArrayBuffer`), это безопаснее, но не бесплатно.

**`worker_threads`** даёт настоящий параллелизм: тяжёлое вычисление уходит в отдельный поток со своим собственным event loop, а главный поток продолжает принимать запросы. Вынесем `slowSum` из шага 4.2:

**Файлы:** `sum-worker.js`, `worker-server.js`.

```bash run
cat > sum-worker.js <<'EOF'
import { parentPort, workerData } from 'node:worker_threads'

let total = 0
for (let i = 0; i < workerData.n; i++) total += i
parentPort.postMessage(total)
EOF
cat > worker-server.js <<'EOF'
import { createServer } from 'node:http'
import { Worker } from 'node:worker_threads'

function sumInWorker(n) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL('./sum-worker.js', import.meta.url), { workerData: { n } })
    worker.on('message', resolve)
    worker.on('error', reject)
  })
}

const server = createServer(async (req, res) => {
  if (req.url === '/slow') {
    const result = await sumInWorker(5_000_000_000)
    res.end(`сумма из воркера: ${result}\n`)
    return
  }
  res.end('быстрый ответ\n')
})
server.listen(3301, () => console.log('worker-server на 3301'))
EOF
node worker-server.js &
SERVER_PID=$!
sleep 1
(curl -s http://localhost:3301/slow &)
sleep 0.3
time curl -s http://localhost:3301/
kill $SERVER_PID
```

**Разбор.** `new Worker(путь, { workerData })` — запускает файл в отдельном потоке и передаёт ему данные (`workerData`, доступен внутри воркера сразу, без сообщения). `parentPort.postMessage(result)` — воркер отправляет результат обратно; `worker.on('message', ...)` в главном потоке его получает. Между потоками данные **копируются** — воркер не может напрямую трогать переменные главного потока, и наоборот.

### result
```out auto
```

### why
Сравни время второго `curl` здесь и в шаге 4.2: главный поток свободен принимать `/` сразу же, пока воркер считает `/slow` отдельно. Это и есть ответ на вопрос «что делать с тяжёлыми вычислениями в Node» — не синхронный цикл в обработчике, а `worker_threads` (для вычислений в процессе) или отдельный сервис (для совсем тяжёлого — вне рамок этой лабы).

### deep Как ещё можно
Пул воркеров (создавать не новый `Worker` на каждый запрос, а заранее несколько и раздавать им задачи) эффективнее при частых вызовах — создание потока не бесплатно; библиотека `piscina` на npm делает это за тебя. В этой лабе — один `Worker` на вызов, этого достаточно, чтобы понять механизм.

### deep Если не получилось
- **`ERR_WORKER_PATH`** — путь к файлу воркера неверный; `new URL('./sum-worker.js', import.meta.url)` работает только если оба файла в одной папке.
- **Второй `curl` всё равно медленный** — проверь, что сервер перезапущен (`worker-server.js`, а не старый `blocking-server.js` на другом порту — 3301, не 3300).

### quiz
- Чем `worker_threads` отличается от простого `async`/`await` — почему `await slowSum(...)` само по себе не решило бы проблему блокировки?
- Как главный поток получает результат от воркера?
- Что не может воркер напрямую, в отличие от обычной функции в том же потоке?

### links
- https://nodejs.org/api/worker_threads.html | справочник по worker_threads | Node.js: Worker threads

## 4.4 cluster: несколько процессов на одном порту | short: cluster | est: ~25 мин
### intro
**Слова шага:** `cluster` — модуль для запуска нескольких копий (воркеров-процессов, не потоков) одной программы, слушающих один порт; *master-процесс* — тот, что порождает и перезапускает воркеров; *round-robin* — ОС/Node по очереди раздаёт новые соединения воркерам.

`worker_threads` — потоки **внутри одного процесса** (общий процесс, своя память на поток). **`cluster`** — наоборот, несколько **процессов**, каждый со своей полной копией памяти, слушающих один и тот же порт:

**Файл:** `cluster-demo.js`.

```bash run
cat > cluster-demo.js <<'EOF'
import cluster from 'node:cluster'
import { createServer } from 'node:http'
import { cpus } from 'node:os'

if (cluster.isPrimary) {
  console.log('мастер-процесс, pid:', process.pid)
  const n = Math.min(2, cpus().length)
  for (let i = 0; i < n; i++) cluster.fork()
  cluster.on('exit', (worker) => console.log('воркер завершился, pid:', worker.process.pid))
} else {
  createServer((req, res) => res.end(`ответил воркер, pid: ${process.pid}\n`)).listen(3302)
}
EOF
timeout 3 node cluster-demo.js &
sleep 1
curl -s http://localhost:3302/
curl -s http://localhost:3302/
curl -s http://localhost:3302/
wait
```

**Разбор.** `cluster.isPrimary` — true только в главном (master) процессе; он сам ничего не слушает, а порождает воркеров через `cluster.fork()` — каждый воркер выполняет этот же файл заново, но попадает в ветку `else`. Node и ОС сами распределяют входящие соединения между воркерами — три запроса подряд вполне могут попасть на разные `pid`.

### result
Три запроса подряд приходят на два разных процесса-воркера (мастер печатает свой pid в начале):

```out
мастер-процесс, pid: 11
ответил воркер, pid: 19
ответил воркер, pid: 20
ответил воркер, pid: 19
```

Номера `pid` у тебя будут другими, и порядок ответов тоже может отличаться: между воркерами соединения распределяет ОС. Строки «воркер завершился» не появятся: `timeout` останавливает мастер сигналом, и он выходит, не дожидаясь воркеров.

### why
`cluster` — то, как Node использует несколько ядер процессора: один процесс Node — один поток для JS (не считая `worker_threads`), но несколько *процессов* `cluster` — это несколько независимых event loop на разных ядрах, за одним портом. Для ShareBox в учебных масштабах не нужен, но важно понимать разницу: `worker_threads` — для одной тяжёлой задачи, `cluster` — чтобы использовать все ядра сервера сразу под обычную нагрузку (ближе к тому, что в проде под капотом делает Node-оркестрация или сам процесс-менеджер).

### deep Если не получилось
- **Все ответы с одним и тем же `pid`** — при малом числе запросов распределение не обязано быть идеально равномерным; это не ошибка, увеличь число `curl`-вызовов.
- **`timeout 3` не найден** — на части систем нет `timeout`; тогда убери его и останавливай процесс `kill %1` после проверки.

### quiz
- Чем процесс `cluster`-воркера отличается от потока `worker_threads` — что у них общее, а что раздельное (память)?
- Что делает `cluster.isPrimary` и что происходит в ветке `else`?
- Если нужно разогнать одну тяжёлую CPU-задачу — `cluster` или `worker_threads`? А если нужно использовать все ядра сервера под обычный поток запросов?

### links
- https://nodejs.org/api/cluster.html | справочник по cluster | Node.js: Cluster

## 4.5 🔨 Сломать → починить: хеш большого файла блокирует сервер | short: Сломать → починить | est: ~30 мин
### intro
:::trap Сломать → починить
Посчитай `sha256` большого файла синхронным циклом прямо в обработчике запроса (сессия 3 уже умеет считать хеш, но не на 100 МБ разом) — и увидь, как это блокирует остальной сервер. Почини через `worker_threads`.
:::

**Файлы:** `hash-blocking-server.js`.

```bash run
head -c 100000000 /dev/urandom > upload-demo.bin
cat > hash-blocking-server.js <<'EOF'
import { createServer } from 'node:http'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'

const server = createServer((req, res) => {
  if (req.url === '/hash') {
    const data = readFileSync('upload-demo.bin')
    const hash = createHash('sha256').update(data).digest('hex')
    res.end(hash + '\n')
    return
  }
  res.end('быстрый ответ\n')
})
server.listen(3303, () => console.log('hash-blocking-server на 3303'))
EOF
node hash-blocking-server.js &
SERVER_PID=$!
sleep 1
(curl -s http://localhost:3303/hash &)
sleep 0.2
time curl -s http://localhost:3303/
kill $SERVER_PID
```

**Почини** — вынеси хеширование в `worker_threads` (тот же приём, что в шаге 4.3):

**Файлы:** `hash-worker.js`, `hash-worker-server.js`.

```bash run
cat > hash-worker.js <<'EOF'
import { parentPort, workerData } from 'node:worker_threads'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'

const data = readFileSync(workerData.path)
parentPort.postMessage(createHash('sha256').update(data).digest('hex'))
EOF
cat > hash-worker-server.js <<'EOF'
import { createServer } from 'node:http'
import { Worker } from 'node:worker_threads'

function hashInWorker(path) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL('./hash-worker.js', import.meta.url), { workerData: { path } })
    worker.on('message', resolve)
    worker.on('error', reject)
  })
}

const server = createServer(async (req, res) => {
  if (req.url === '/hash') {
    const hash = await hashInWorker('upload-demo.bin')
    res.end(hash + '\n')
    return
  }
  res.end('быстрый ответ\n')
})
server.listen(3304, () => console.log('hash-worker-server на 3304'))
EOF
node hash-worker-server.js &
SERVER_PID=$!
sleep 1
(curl -s http://localhost:3304/hash &)
sleep 0.2
time curl -s http://localhost:3304/
kill $SERVER_PID
```

### result
```out auto
```

### why
ShareBox считает `sha256` каждого загруженного файла (сессия 15, до 200 МБ) — если делать это синхронным `createHash(...).update(readFileSync(...))` прямо в обработчике, сервер замрёт для всех на время хеширования. Вынос в `worker_threads` — то самое решение, которое ляжет в реальный код ShareBox.

### quiz
- Что именно блокировало сервер в первом варианте — чтение файла или сам хеш, и как это проверить?
- Почему вынос хеширования в воркер не ускоряет сам хеш, но решает проблему?
- Какой ещё способ из шага 4.1 (`child_process`) мог бы справиться с этой же задачей, вызвав системную утилиту `sha256sum`?

### outro
:::tip Приёмка сессии 4
Ты можешь: запустить внешнюю команду через `child_process` и прочитать её вывод и код выхода; показать и объяснить, как синхронный CPU-bound код блокирует event loop для всех запросов; вынести тяжёлое вычисление в `worker_threads` и получить результат через сообщения; объяснить разницу между `worker_threads` (потоки, один процесс) и `cluster` (несколько процессов на одном порту); починить реальный случай блокировки — хеширование файла. В `/work/sharebox`: `spawn-demo.js`, `blocking-server.js`, `sum-worker.js` + `worker-server.js`, `cluster-demo.js`, `hash-worker.js` + `hash-worker-server.js`.
:::

### links
- https://nodejs.org/learn/asynchronous-work/dont-block-the-event-loop | развёрнутый гайд по CPU-bound задачам | Node.js: CPU-bound tasks
