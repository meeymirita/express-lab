# Сессия 2 · Файлы, Buffer, Streams
dur: ~4 ч

## 2.1 fs/promises: читаем и пишем файлы | short: fs/promises | est: ~20 мин
### intro
**Слова шага:** `node:fs/promises` — версия модуля `fs`, где функции возвращают `Promise` вместо приёма колбэка; `readFile`/`writeFile` — прочитать/записать файл целиком; `readdir` — список файлов в папке; *кодировка (encoding)* — как байты превращаются в текст (`'utf8'`).

`async`/`await` и `Promise` ты уже знаешь из `js-lab` — здесь только API, которым Node даёт доступ к файловой системе. **`node:fs/promises`** — промис-версия `fs`: `readFile`, `writeFile`, `readdir`, `mkdir` и другие возвращают `Promise`, так что с ними работает обычный `await`, без колбэков.

**Файл:** `fs-demo.js`.

```bash run
cd /work/sharebox
cat > fs-demo.js <<'EOF'
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises'

await mkdir('data', { recursive: true })
await writeFile('data/note.txt', 'первая заметка\n', 'utf8')
await writeFile('data/note2.txt', 'вторая заметка\n', 'utf8')

const text = await readFile('data/note.txt', 'utf8')
console.log('прочитано:', text.trim())

const files = await readdir('data')
console.log('файлы в data/:', files)
EOF
node fs-demo.js
```

**Разбор.** `mkdir(..., { recursive: true })` — создать папку и все недостающие родительские, не падая, если она уже есть (без этого флага `mkdir` на существующей папке бросит `EEXIST`). `readdir` возвращает простой массив имён файлов — без размеров и дат, за ними отдельно (`stat`, см. «Если не получилось»). Top-level `await` работает прямо в файле без обёртки в `async function`, потому что `package.json` задаёт `"type": "module"` (сессия 1).

### result
```out auto
```

### why
ShareBox дальше хранит загруженные файлы на диске (сессия 15) — те же `writeFile`/`readFile`/`mkdir`, только с потоками вместо целого файла в памяти (этот же шаг, но следующий). Здесь — база: как Node вообще читает и пишет файлы, без Express и без базы данных.

### deep Как ещё можно
`fs.stat(path)` (тоже в `fs/promises`) возвращает объект с `size`, `mtime` и методами `isFile()`/`isDirectory()` — пригодится, когда нужно не просто имя файла, а его размер (сессия 15, метаданные загруженного файла).

### deep Если не получилось
- **`ENOENT: no such file or directory`** — путь относительный и зависит от того, откуда запущен `node`; проверь `pwd`, все команды сессии выполняются из `/work/sharebox`.
- **`EEXIST` на `mkdir`** — забыт `{ recursive: true }`, или уже есть файл (не папка) с таким именем.

### quiz
- Чем `node:fs/promises` отличается от обычного `node:fs` с колбэками?
- Что делает `{ recursive: true }` у `mkdir` и что будет без него при повторном запуске?
- Что вернёт `readdir` — только имена или ещё размеры и даты?

### links
- https://nodejs.org/api/fs.html#promises-api | fs/promises | Node.js: fs (Promises API)

## 2.2 node:path: пути без боли | short: node:path | est: ~20 мин
### intro
**Слова шага:** `node:path` — модуль для работы с путями файлов кроссплатформенно; `join` — склеить части пути правильным разделителем; `resolve` — превратить в абсолютный путь; `extname`/`basename`/`dirname` — расширение, имя файла, папка из пути.

Склеивать пути строками (`dir + '/' + name`) ломается на Windows (там `\`, а не `/`) и плодит двойные слэши. **`node:path`** решает это за тебя.

**Файл:** `path-demo.js`.

```bash run
cat > path-demo.js <<'EOF'
import { join, resolve, extname, basename, dirname } from 'node:path'

const p = join('data', 'uploads', 'photo.PNG')
console.log('join:', p)
console.log('resolve:', resolve(p))
console.log('extname:', extname(p))
console.log('basename:', basename(p))
console.log('dirname:', dirname(p))
EOF
node path-demo.js
```

**Разбор.** `join` склеивает части через правильный разделитель для текущей ОС и убирает лишние слэши; `resolve` достраивает путь до абсолютного от текущей рабочей папки (`process.cwd()`), если путь не абсолютный. `extname` возвращает расширение **как есть**, с учётом регистра (`.PNG`, а не `.png`) — сравнивать расширения нужно через `.toLowerCase()`.

### result
```out auto
```

### why
ShareBox принимает файлы с любым расширением и регистром (`.PNG`, `.png`, `.Png`) и должен работать на любой ОС, где запущен Node — ровно то, что даёт `path` вместо ручной склейки строк. В сессии 15 `extname` и `join` понадобятся, чтобы собрать путь для сохранения загруженного файла.

### deep Если не получилось
- **Двойной слэш или `undefined` в пути** — где-то путь собран строкой через `+ '/' +` вместо `join`; замени на `join(...)`.
- **Расширение не совпало при сравнении** — забыли `.toLowerCase()`: `'.PNG' !== '.png'`.

### quiz
- Чем `join('a', 'b')` отличается от `'a' + '/' + 'b'`, если `'a'` уже заканчивается на `/`?
- Что делает `resolve`, если путь уже абсолютный?
- Почему `extname` не приводит расширение к нижнему регистру сам?

### links
- https://nodejs.org/api/path.html | справочник по node:path | Node.js: Path

## 2.3 EventEmitter | short: EventEmitter | est: ~20 мин
### intro
**Слова шага:** `EventEmitter` — объект, который умеет испускать именованные события; `on` — подписаться на событие; `emit` — вызвать событие, оповестив подписчиков; *подписчик (listener)* — функция, которая сработает при событии.

Промисы годятся для «результат один раз». Но что, если событий много и заранее неизвестно сколько (новые данные из сети, прогресс загрузки)? Для этого в Node — **`EventEmitter`**: объект, на котором можно подписаться (`on`) на именованное событие, и позже кто угодно может его вызвать (`emit`) — сработают все подписчики по очереди.

**Файл:** `events-demo.js`.

```bash run
cat > events-demo.js <<'EOF'
import { EventEmitter } from 'node:events'

const uploads = new EventEmitter()

uploads.on('done', (name) => console.log('загрузка завершена:', name))
uploads.on('done', (name) => console.log('→ отправить письмо про', name))

uploads.emit('done', 'photo.png')
uploads.emit('done', 'report.pdf')
EOF
node events-demo.js
```

### result
```out auto
```

### why
`EventEmitter` — это не экзотика, а фундамент: `req`/`res` в `node:http` (шаг 1.6) — тоже `EventEmitter` (события `'data'`, `'end'`, `'error'`), и потоки (следующий шаг) построены на нём же. Понимание `on`/`emit` объясняет, почему у объектов вроде `req` можно писать `req.on('data', ...)`.

### deep Под капотом
`emit` вызывает подписчиков **синхронно** и **по порядку подписки** — в примере выше сначала «загрузка завершена», потом «отправить письмо», для каждого файла. Если подписчиков нет, `emit` просто ничего не делает (кроме особого события `'error'` — без подписчика на него Node уронит процесс).

### deep Если не получилось
- **Обработчик не сработал** — проверь точное совпадение имени события (`'done'` ≠ `'Done'`, регистр важен) и что `on` стоит в коде раньше `emit`.
- **`Unhandled 'error' event'`** — особый случай: если возникло событие `'error'` без своего `on('error', ...)`, Node считает это необработанным исключением и завершает процесс.

### quiz
- В каком порядке вызываются два подписчика на одно и то же событие?
- Чем событие `'error'` у `EventEmitter` отличается от остальных?
- Назови один объект из шага 1.6, который на самом деле тоже `EventEmitter`.

### links
- https://nodejs.org/api/events.html | справочник по EventEmitter | Node.js: Events

## 2.4 Buffer и потоки: копируем файл | short: Streams и Buffer | est: ~30 мин
### intro
**Слова шага:** `Buffer` — кусок памяти с сырыми байтами; *поток (stream)* — чтение/запись данных по частям, не всё сразу; `Readable` — поток, из которого читают; `Writable` — поток, в который пишут; `pipe` — соединить читающий поток с пишущим; *обратное давление (backpressure)* — автоматическое торможение чтения, если запись не успевает.

Строки в JS — это текст в определённой кодировке. Но файлы, сеть, картинки — это **байты**, и для них в Node есть `Buffer` — кусок памяти с сырыми байтами:

```bash run
node -e "console.log(Buffer.from('ok', 'utf8'))"
```

Для больших файлов читать их целиком в память (как `readFile` в шаге 2.1) — плохая идея: файл 200 МБ (лимит ShareBox, сессия 15) съест 200 МБ оперативной памяти разом. **Поток (stream)** читает и пишет **кусками (chunks)**, не дожидаясь, пока весь файл будет готов. Скопируем файл потоком:

**Файл:** `copy-stream.js`.

```bash run
head -c 200000 /dev/urandom > big.bin
cat > copy-stream.js <<'EOF'
import { createReadStream, createWriteStream } from 'node:fs'

const src = createReadStream('big.bin')
const dst = createWriteStream('big-copy.bin')

let chunks = 0
src.on('data', (chunk) => { chunks += 1 })
src.pipe(dst)
dst.on('finish', () => console.log('скопировано чанков:', chunks))
EOF
node copy-stream.js
```

Проверим, что копия точно того же размера:

```bash run
wc -c big.bin big-copy.bin
```

**Разбор.** `createReadStream`/`createWriteStream` — читающий и пишущий поток, оба `EventEmitter` (шаг 2.3): событие `'data'` на каждый кусок, `'finish'` — когда запись закончена. `.pipe(dst)` — соединяет читающий поток с пишущим и сам управляет скоростью (**backpressure**): если `dst` пишет на диск медленнее, чем `src` читает, `pipe` сам притормозит чтение, чтобы память не росла бесконтрольно.

### result
```out auto
```

### why
Это ровно то, что в сессии 15 позволит принимать файлы до 200 МБ без роста памяти процесса: `multer` и скачивание с `Range` построены на тех же `Readable`/`Writable` и том же `pipe`. Без понимания потоков непонятно, почему «просто прочитать файл в память» (как в шаге 2.1) для ShareBox — неправильный путь.

### deep Если не получилось
- **Размеры `big.bin` и `big-copy.bin` разные** — копирование не завершилось до `wc -c`; в реальном коде (не в тестовом скрипте) жди событие `'finish'`, прежде чем считать файл готовым — как и сделано в примере через `console.log` внутри `'finish'`.
- **Процесс «висит»** — обычно значит, что `'finish'` не наступил (поток не закрылся); проверь, что `.pipe()` вызван, а не только `.on('data', ...)` — без `.pipe()` или ручной записи данные читаются, но никуда не пишутся.

### quiz
- Почему читать файл в 200 МБ через `readFile` целиком — плохая идея для сервера?
- Что делает `backpressure` и зачем он нужен, если запись на диск медленнее чтения?
- Какое событие сигналит, что поток дочитан/дозаписан, и почему просто `pipe()` без ожидания этого события — ошибка?

### links
- https://nodejs.org/api/stream.html | справочник по потокам | Node.js: Stream
- https://nodejs.org/api/buffer.html | справочник по Buffer | Node.js: Buffer

## 2.5 🔨 Сломать → починить: readFile на большом файле | short: Сломать → починить | est: ~25 мин
### intro
:::trap Сломать → починить
Прочитай файл 200 МБ целиком через `readFile` вместо потока и посмотри на потребление памяти процесса. Потом почини — перепиши на поток из шага 2.4.
:::

**Файл:** `mem-demo.js`.

```bash run
head -c 50000000 /dev/urandom > huge.bin
cat > mem-demo.js <<'EOF'
import { readFile } from 'node:fs/promises'

const before = process.memoryUsage().rss
const data = await readFile('huge.bin')
const after = process.memoryUsage().rss
console.log('файл:', data.length, 'байт')
console.log('RSS до:', Math.round(before / 1024 / 1024), 'МБ, после:', Math.round(after / 1024 / 1024), 'МБ')
EOF
node mem-demo.js
```

**Почини** — перепиши на поток, который только считает байты, не копя их в памяти:

**Файл:** `mem-demo-stream.js`.

```bash run
cat > mem-demo-stream.js <<'EOF'
import { createReadStream } from 'node:fs'

const before = process.memoryUsage().rss
const src = createReadStream('huge.bin')
let total = 0
src.on('data', (chunk) => { total += chunk.length })
src.on('end', () => {
  const after = process.memoryUsage().rss
  console.log('файл:', total, 'байт')
  console.log('RSS до:', Math.round(before / 1024 / 1024), 'МБ, после:', Math.round(after / 1024 / 1024), 'МБ')
})
EOF
node mem-demo-stream.js
```

### result
```out auto
```

### why
`process.memoryUsage().rss` — сколько реальной памяти занимает процесс Node целиком. На файле 50 МБ `readFile` добавляет к RSS примерно размер файла целиком — вся копия лежит в памяти разом одним `Buffer`; поток добавляет заметно меньше — он читает кусками по умолчанию (~64 КБ за раз) и не держит в памяти весь файл одновременно, хотя RSS у Node и не падает сразу до нуля (операционная система не спешит забирать страницы памяти обратно, даже если сам `Buffer` уже не нужен — поэтому цифра не «почти ноль», но она **не растёт вместе с размером файла**). Увеличь `huge.bin` в несколько раз и сравни: у `readFile` добавка к RSS вырастет пропорционально, у потока — нет. Это и есть ответ на вопрос «зачем вообще нужны потоки», который в сессии 15 станет требованием ТЗ (файлы до 200 МБ, память не растёт).

### deep Если не получилось
- **Разница в памяти не очевидна на маленьком файле** — 50 МБ выбраны специально заметными; на файле 1 КБ разницу не увидишь, оба способа занимают почти ничего.
- **`RSS до` уже большой** — это нормально: сам процесс Node (V8, стандартная библиотека) занимает десятки мегабайт ещё до чтения файла; сравнивай разницу «до/после», а не абсолютное число.

### quiz
- Почему RSS заметно растёт после `readFile`, но почти не растёт после потокового чтения?
- Что означает «читает кусками по умолчанию ~64 КБ» для файла в 1 ГБ?
- Как это же рассуждение применится к ShareBox в сессии 15?

### outro
:::tip Приёмка сессии 2
Ты можешь: прочитать и записать файл через `fs/promises`; собрать путь через `node:path`, не склеивая строки руками; подписаться на событие через `EventEmitter` и вызвать его; скопировать файл потоком, не загружая его целиком в память; показать разницу в потреблении памяти между `readFile` и потоковым чтением на большом файле. В `/work/sharebox` лежит: `data/` с файлами из 2.1, `fs-demo.js`, `path-demo.js`, `events-demo.js`, `copy-stream.js`, `mem-demo.js`, `mem-demo-stream.js`.
:::

### links
- https://nodejs.org/api/process.html#processmemoryusage | process.memoryUsage() | Node.js: process
