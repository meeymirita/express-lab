# Сессия 15 · Файлы
dur: ~4 ч

## 15.1 multer: приём файла | short: multer | est: ~25 мин
### intro
**Слова шага:** `multer` — стандартный middleware Express для приёма файлов; `multipart/form-data` — формат тела запроса, в котором передают файлы; `upload.single` — middleware, ожидающее одно поле формы с файлом; `req.file` — метаданные загруженного файла после `multer`.

Файл в HTTP-запросе передаётся не как JSON, а в формате **`multipart/form-data`** — тело запроса разбито на части, у каждой свой заголовок. Парсить это руками неприятно; **multer** — стандартный middleware Express для приёма файлов.

**Файл:** `upload-demo.js`.

```bash run
cd /work/sharebox
npm install multer
mkdir -p uploads
cat > upload-demo.js <<'EOF'
import express from 'express'
import multer from 'multer'

const upload = multer({ dest: 'uploads/' })
const app = express()

app.post('/upload-demo', upload.single('file'), (req, res) => {
  res.json({ originalname: req.file.originalname, size: req.file.size, savedAs: req.file.filename })
})

app.listen(3000, () => console.log('демо-сервер слушает 3000'))
EOF
node upload-demo.js &
SERVER_PID=$!
sleep 1
echo "содержимое тестового файла" > test-upload.txt
curl -s -F "file=@test-upload.txt" http://localhost:3000/upload-demo
echo
ls uploads/
kill $SERVER_PID
```

**Разбор.** `multer({ dest: 'uploads/' })` — куда сохранять временные файлы. `upload.single('file')` — middleware, ожидающий **одно** поле формы с именем `file`; после него `req.file` содержит метаданные (`originalname` — имя у клиента, `filename` — случайное имя на диске, `size`). `-F "file=@test-upload.txt"` в `curl` — отправка файла как `multipart/form-data`, поле `file`.

### result
```out auto
```

### why
`req.file.filename` — случайное имя, а не `req.file.originalname` — это первая защита из следующего шага: чужой файл с именем `../../etc/passwd` или `index.php` не попадёт на диск под своим именем.

### deep Если не получилось
- **`req.file` — `undefined`** — поле формы в `curl` называется не `file`, а как-то иначе; имя в `-F "имя=@путь"` должно совпадать с `upload.single('имя')`.
- **`ENOENT` при сохранении** — папка `uploads/` не существует; `multer` её не создаёт сам, только пишет в существующую.

### quiz
- Почему файлы передают не как JSON, а как `multipart/form-data`?
- Чем `req.file.originalname` отличается от `req.file.filename`?
- Что обязано совпадать в имени поля `curl -F` и в `upload.single(...)`?

### links
- https://www.npmjs.com/package/multer | документация multer | npm: multer

## 15.2 Поток вместо памяти: лимит 200 МБ и 413 | short: Лимит размера | est: ~25 мин
### intro
**Слова шага:** *лимит размера (limits)* — максимально допустимый размер загружаемого файла; `413 Payload Too Large` — код ответа «файл слишком большой»; *обработка ошибки multer* — свой error handler для `LIMIT_FILE_SIZE` и похожих ошибок.

По умолчанию `multer` без лимита примет файл любого размера — сервер с несколькими параллельными большими загрузками рискует съесть всю память диска или оперативку (в зависимости от режима хранения, следующий шаг). Зададим лимит в 200 МБ, как в паспорте ShareBox:

**Файл:** `upload-limit-demo.js`.

```bash run
cat > upload-limit-demo.js <<'EOF'
import express from 'express'
import multer from 'multer'

const upload = multer({ dest: 'uploads/', limits: { fileSize: 200 * 1024 * 1024 } })
const app = express()

app.post('/upload-demo', upload.single('file'), (req, res) => {
  res.json({ originalname: req.file.originalname, size: req.file.size })
})

app.use((err, req, res, next) => {
  if (err.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ error: 'file_too_large', message: 'файл больше 200 МБ' })
  }
  res.status(500).json({ error: 'internal' })
})

app.listen(3000, () => console.log('демо-сервер слушает 3000'))
EOF
node upload-limit-demo.js &
SERVER_PID=$!
sleep 1
head -c $((210 * 1024 * 1024)) /dev/urandom > too-big.bin
curl -s -o /dev/null -w 'файл 210 МБ: %{http_code}\n' -F "file=@too-big.bin" http://localhost:3000/upload-demo
rm -f too-big.bin
kill $SERVER_PID
```

### result
```out auto
```

### why
`limits.fileSize` — проверка **во время** приёма, поток обрывается на 200 МБ, не дожидаясь, пока клиент докачает оставшееся: без этого лимита атака «залить терабайтный файл» положила бы диск сервера. `413` — стандартный код именно для «тело запроса слишком большое», клиент может на него отдельно отреагировать (показать «файл слишком большой», а не общую ошибку).

### deep Если не получилось
- **Процесс долго создаёт `too-big.bin`** — 210 МБ случайных байт из `/dev/urandom` генерируются не мгновенно; это ожидаемо, не зависание.
- **Код ответа `500`, а не `413`** — error handler должен стоять **после** `upload.single(...)` в цепочке; сверь порядок `app.use(...)` (сессия 9.4).

### quiz
- Что произойдёт без `limits.fileSize`, если кто-то пришлёт файл в 50 ГБ?
- Как multer сообщает о превышении лимита — кодом ошибки или исключением другого типа?
- Почему `413`, а не просто `400`, уместнее для этой ситуации?

### links
- https://github.com/expressjs/multer#limits | лимиты multer | multer: Limits (GitHub)

## 15.3 Случайные имена, MIME и path traversal | short: Безопасность имён | est: ~30 мин
### intro
**Слова шага:** *path traversal* — атака через имя файла вида `../../`, пытающаяся выйти за пределы папки; `crypto.randomUUID` — случайное имя файла на диске вместо имени клиента; *проверка MIME-типа* — сверка заявленного типа файла со списком разрешённых; *белый список (allowlist)* — список допустимых типов файлов, всё остальное отклоняется.

Имя файла от клиента (`originalname`) нельзя использовать для сохранения на диск напрямую: имя вроде `../../../etc/passwd` или `../server.js` может попытаться записать файл **вне** папки `uploads/` — это и есть **path traversal**. Решение — никогда не доверять имени клиента: сохранять под своим случайным именем, оригинальное — только в базе как текст.

**Файлы:** `storage-demo.js`, `storage-check.js`.

```bash run
cat > storage-demo.js <<'EOF'
import { randomUUID } from 'node:crypto'
import multer from 'multer'

const ALLOWED_MIME = new Set(['image/png', 'image/jpeg', 'application/pdf', 'text/plain'])

const storage = multer.diskStorage({
  destination: 'uploads/',
  filename: (req, file, cb) => {
    cb(null, randomUUID())
  },
})

export const upload = multer({
  storage,
  limits: { fileSize: 200 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_MIME.has(file.mimetype)) {
      return cb(new Error(`недопустимый тип файла: ${file.mimetype}`))
    }
    cb(null, true)
  },
})
EOF
cat > storage-check.js <<'EOF'
import { randomUUID } from 'node:crypto'
console.log('пример случайного имени:', randomUUID())
console.log('опасное имя клиента никогда не используется напрямую, только:', 'originalname (текст в базе)')
EOF
node storage-check.js
```

**Разбор.** `multer.diskStorage({ filename: ... })` — свой способ назвать файл на диске вместо случайного имени по умолчанию; `randomUUID()` гарантированно не содержит `/` или `..`, значит путь traversal невозможен физически — не потому что мы его «отфильтровали», а потому что в имени просто неоткуда взяться этим символам. `fileFilter` проверяет MIME **по заголовку**, который присылает клиент (не стопроцентная защита — заголовок можно подделать, это первый, не единственный рубеж).

### result
```out auto
```

### why
`originalname` всё равно нужен — показать пользователю красивое «report.pdf» вместо UUID — но живёт только как **текст** в базе, никогда не как имя файла на диске. Это разделение («что видит человек» vs «как это физически называется на диске») — стандартный приём против path traversal в любом языке, не только Node.

### deep Под капотом
`file.mimetype` в multer — то, что браузер или клиент сам заявил в заголовке `Content-Type` этой части формы; злоумышленник может переименовать `evil.exe` в `photo.png` и подделать заголовок. Полноценная проверка — прочитать первые байты файла (**magic bytes**) и сверить с ожидаемым форматом; за пределами этой лабы, но важно знать, что `fileFilter` — не единственная линия защиты.

### deep Если не получилось
- **`fileFilter` не блокирует подозрительный файл** — проверь, что `cb(new Error(...))` вызван без `, false` третьим аргументом по ошибке — при ошибке в `cb` достаточно одного аргумента.
- **`destination` как строка игнорируется** — `multer.diskStorage` ожидает либо строку, либо функцию `(req, file, cb) => cb(null, путь)`; строка — тоже валидный вариант, если путь всегда один.

### quiz
- Почему `randomUUID()` в имени файла на диске защищает от path traversal надёжнее, чем «вырезать `..` из имени» регулярным выражением?
- Где хранится оригинальное имя файла, если не в имени файла на диске?
- Почему проверка `file.mimetype` — не стопроцентная защита от поддельного типа файла?

### links
- https://owasp.org/www-community/attacks/Path_Traversal | path traversal подробно | OWASP: Path Traversal
- https://nodejs.org/api/crypto.html#cryptorandomuuidoptions | randomUUID | Node.js: crypto.randomUUID

## 15.4 Роут загрузки | short: POST /files | est: ~25 мин
### intro
**Слова шага:** *связка multer + сервис + база* — путь от загруженного файла до записи в базу через слои; `req.user` — текущий пользователь из middleware авторизации; `req.file` — метаданные файла из `multer`.

Соберём шаги 15.1–8.3 в настоящий роут загрузки, привязанный к владельцу (сессия 14):

**Файлы:** `src/services/files.service.js`, `lib/upload.js`, `src/controllers/files.controller.js` (дописать).

```bash run
cat > src/services/files.service.js <<'EOF'
import { prisma } from '../prisma.js'
import { NotFoundError, AppError } from '../../lib/errors.js'

export async function getFileOrThrow(id) {
  const file = await prisma.file.findUnique({ where: { id: Number(id) } })
  if (!file) throw new NotFoundError(`файл ${id} не найден`)
  return file
}

export async function createFile({ ownerId, name, sizeBytes, storedPath }) {
  return prisma.file.create({
    data: { ownerId, name, sizeBytes: BigInt(sizeBytes), storedPath },
  })
}

export async function deleteOwnedFile(fileId, userId) {
  const file = await getFileOrThrow(fileId)
  if (file.ownerId !== userId) throw new AppError('это не твой файл', 403)
  await prisma.file.delete({ where: { id: file.id } })
  return { deleted: true }
}
EOF
cat > lib/upload.js <<'EOF'
import { randomUUID } from 'node:crypto'
import multer from 'multer'

const ALLOWED_MIME = new Set(['image/png', 'image/jpeg', 'application/pdf', 'text/plain'])

const storage = multer.diskStorage({
  destination: 'uploads/',
  filename: (req, file, cb) => cb(null, randomUUID()),
})

export const upload = multer({
  storage,
  limits: { fileSize: 200 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_MIME.has(file.mimetype)) return cb(new Error(`недопустимый тип файла: ${file.mimetype}`))
    cb(null, true)
  },
})
EOF
cat >> src/controllers/files.controller.js <<'EOF'

export async function uploadFile(req, res) {
  const { createFile } = await import('../services/files.service.js')
  const saved = await createFile({
    ownerId: req.user.id,
    name: req.file.originalname,
    sizeBytes: req.file.size,
    storedPath: req.file.path,
  })
  res.status(201).json({ id: saved.id, name: saved.name, size: Number(saved.sizeBytes) })
}
EOF
sed -i.bak "1i import { upload } from '../../lib/upload.js'\nimport { requireAuth } from '../../lib/auth-middleware.js'" src/routes/files.routes.js
sed -i.bak "/router.delete/a router.post('/files', requireAuth, upload.single('file'), (await import('../controllers/files.controller.js')).uploadFile)" src/routes/files.routes.js
rm -f src/routes/files.routes.js.bak
echo "роут добавлен; целиком перепишем файл одним блоком в следующем шаге для чистоты"
```

### result
```out
(файлы подготовлены; чистая сборка — в шаге 15.5, там же и проверка запуском)
```

### why
`req.file.path` (куда multer реально сохранил байты) и `req.file.originalname` (как файл назывался у клиента) — оба попадают в `createFile`, но в разные поля: `storedPath` — техническое, для скачивания (следующий шаг); `name` — то, что увидит пользователь.

### deep Если не получилось
- **Патч через `sed` в конце шага — временный** — как и в шаге 14.6, это не стиль для подражания; шаг 15.5 перепишет `files.routes.js` целиком одним понятным файлом.

### quiz
- В какое поле базы попадает `req.file.path`, а в какое — `req.file.originalname`?
- Какой middleware должен отработать раньше — `requireAuth` или `upload.single('file')` — и почему порядок здесь не так важен, как в других местах?
- Что произойдёт с загрузкой, если `req.user` не существует (запрос без токена)?

### links
- https://expressjs.com/en/guide/routing.html | роутинг, для повторения | Express: Routing

## 15.5 Скачивание потоком, Content-Disposition | short: Скачивание | est: ~30 мин
### intro
**Слова шага:** `createReadStream` + `pipe` — отдать файл потоком, тот же приём, что в сессии 2 (есть и готовый `res.download`, см. «Как ещё можно»); `Content-Disposition` — заголовок, который просит браузер сохранить файл; *скачивание потоком* — файл не грузится в память сервера целиком.

Отдать файл клиенту можно так же потоково, как копировали в сессии 2 — не читая его целиком в память:

**Файлы:** `src/controllers/files.controller.js`, `src/routes/files.routes.js`.

```bash run
cat > src/controllers/files.controller.js <<'EOF'
import { createReadStream } from 'node:fs'
import { getFileOrThrow, createFile, deleteOwnedFile } from '../services/files.service.js'

export async function getFile(req, res) {
  res.json(await getFileOrThrow(req.params.id))
}

export async function uploadFile(req, res) {
  const saved = await createFile({
    ownerId: req.user.id,
    name: req.file.originalname,
    sizeBytes: req.file.size,
    storedPath: req.file.path,
  })
  res.status(201).json({ id: saved.id, name: saved.name, size: Number(saved.sizeBytes) })
}

export async function downloadFile(req, res) {
  const file = await getFileOrThrow(req.params.id)
  res.setHeader('Content-Disposition', `attachment; filename="${encodeURIComponent(file.name)}"`)
  createReadStream(file.storedPath).pipe(res)
}

export async function deleteFile(req, res) {
  res.json(await deleteOwnedFile(Number(req.params.id), req.user.id))
}
EOF
cat > src/routes/files.routes.js <<'EOF'
import { Router } from 'express'
import { getFile, uploadFile, downloadFile, deleteFile } from '../controllers/files.controller.js'
import { requireAuth } from '../../lib/auth-middleware.js'
import { upload } from '../../lib/upload.js'

const router = Router()
router.get('/files/:id', getFile)
router.get('/files/:id/download', downloadFile)
router.post('/files', requireAuth, upload.single('file'), uploadFile)
router.delete('/files/:id', requireAuth, deleteFile)
export default router
EOF
node server.js &
SERVER_PID=$!
sleep 1
EMAIL="uploader-$(date +%s)@mail.com"
curl -s -X POST http://localhost:3000/auth/register -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"supersecret123\"}" > /dev/null
TOKEN=$(curl -s -X POST http://localhost:3000/auth/login -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"supersecret123\"}" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).access))")
echo "содержимое файла для скачивания" > upload-me.txt
UPLOAD=$(curl -s -F "file=@upload-me.txt;type=text/plain" -H "Authorization: Bearer $TOKEN" http://localhost:3000/files)
echo "$UPLOAD"
FILE_ID=$(echo "$UPLOAD" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).id))")
curl -s -D - -o downloaded.txt http://localhost:3000/files/$FILE_ID/download | grep -i content-disposition
cat downloaded.txt
kill $SERVER_PID
```

### result
```out auto
```

### why
`createReadStream(...).pipe(res)` — `res` в Express тоже `Writable`-поток (сессия 2!), поэтому к нему применим тот же `pipe`, которым копировался файл на диске. `Content-Disposition: attachment; filename="..."` — заголовок, который заставляет браузер предложить «Сохранить как...» вместо того, чтобы попытаться показать файл прямо на странице.

### deep Как ещё можно
- **`res.download(path, originalName)`** — встроенный метод Express, который делает ровно то же самое: ставит `Content-Disposition` и отдаёт файл потоком, одной строкой вместо двух. В примере выбран ручной `createReadStream(...).pipe(res)` — чтобы было видно, что `res.download` не магия, а обёртка над тем же приёмом из сессии 2; в реальном коде `res.download` короче и достаточно.

### deep Если не получилось
- **Скачанный файл пустой** — `storedPath` в базе не совпадает с реальным путём на диске; сверь, что `req.file.path` из multer (шаг 15.1) сохранён как есть, без изменений.
- **Имя файла при скачивании — с процентами (`%D1%84...`)** — так и задумано для кириллицы: `encodeURIComponent` экранирует не-ASCII символы в заголовке; большинство браузеров декодируют это сами при сохранении.

### quiz
- Почему `createReadStream(...).pipe(res)` не загружает весь файл в память сервера перед отправкой?
- Что делает заголовок `Content-Disposition: attachment`?
- Что из двух — `name` или `storedPath` — попадает в `Content-Disposition`, и почему именно оно?

### links
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Disposition | справочник по Content-Disposition | MDN: Content-Disposition

## 15.6 Range и докачка | short: Range и докачка | est: ~25 мин
### intro
**Слова шага:** `Range` — заголовок запроса конкретного диапазона байт файла; `206 Partial Content` — код ответа на частичный запрос; `Accept-Ranges` — заголовок, которым сервер объявляет поддержку `Range`; *докачка* — продолжение скачивания с места обрыва, а не с начала.

Большой файл (до 200 МБ) при обрыве соединения не хочется качать заново с нуля. Заголовок **`Range`** просит у сервера только часть файла — байты с N по M; сервер отвечает `206 Partial Content` вместо `200`.

**Файлы:** `src/controllers/files.controller.js`, `src/routes/files.routes.js`.

```bash run
cat > src/controllers/files.controller.js <<'EOF'
import { createReadStream, statSync } from 'node:fs'
import { getFileOrThrow, createFile, deleteOwnedFile } from '../services/files.service.js'

export async function getFile(req, res) {
  res.json(await getFileOrThrow(req.params.id))
}

export async function uploadFile(req, res) {
  const saved = await createFile({
    ownerId: req.user.id,
    name: req.file.originalname,
    sizeBytes: req.file.size,
    storedPath: req.file.path,
  })
  res.status(201).json({ id: saved.id, name: saved.name, size: Number(saved.sizeBytes) })
}

export async function downloadFile(req, res) {
  const file = await getFileOrThrow(req.params.id)
  res.setHeader('Content-Disposition', `attachment; filename="${encodeURIComponent(file.name)}"`)
  createReadStream(file.storedPath).pipe(res)
}

export function downloadRangeDemo(req, res) {
  const path = 'uploads-range-demo.bin'
  const { size } = statSync(path)
  const range = req.headers.range
  if (!range) {
    res.setHeader('Accept-Ranges', 'bytes')
    return createReadStream(path).pipe(res)
  }
  const [startStr, endStr] = range.replace(/bytes=/, '').split('-')
  const start = Number(startStr)
  const end = endStr ? Number(endStr) : size - 1
  res.writeHead(206, {
    'Content-Range': `bytes ${start}-${end}/${size}`,
    'Accept-Ranges': 'bytes',
    'Content-Length': end - start + 1,
  })
  createReadStream(path, { start, end }).pipe(res)
}

export async function deleteFile(req, res) {
  res.json(await deleteOwnedFile(Number(req.params.id), req.user.id))
}
EOF
cat > src/routes/files.routes.js <<'EOF'
import { Router } from 'express'
import { getFile, uploadFile, downloadFile, downloadRangeDemo, deleteFile } from '../controllers/files.controller.js'
import { requireAuth } from '../../lib/auth-middleware.js'
import { upload } from '../../lib/upload.js'

const router = Router()
router.get('/files/:id', getFile)
router.get('/files/:id/download', downloadFile)
router.get('/range-demo', downloadRangeDemo)
router.post('/files', requireAuth, upload.single('file'), uploadFile)
router.delete('/files/:id', requireAuth, deleteFile)
export default router
EOF
head -c 100000 /dev/urandom > uploads-range-demo.bin
node server.js &
SERVER_PID=$!
sleep 1
curl -s -o /dev/null -w 'без Range: %{http_code}, размер: %{size_download}\n' http://localhost:3000/range-demo
curl -s -o /dev/null -w 'с Range 0-999: %{http_code}, размер: %{size_download}\n' -H 'Range: bytes=0-999' http://localhost:3000/range-demo
kill $SERVER_PID
```

### result
```out auto
```

### why
`Range` — это ровно то, что позволяет видеоплеерам перематывать видео без скачивания всего файла заново, и то, что в менеджерах загрузки называется «докачка»: клиент, у которого уже есть первые 50 МБ, запрашивает `Range: bytes=50000000-` и получает только остаток. Для ShareBox это значит: обрыв связи на 190 МБ из 200 не требует начинать с нуля.

### deep Если не получилось
- **`206` не приходит, всегда `200`** — заголовок `Range` не дошёл до сервера; некоторые инструменты требуют явного `-H 'Range: bytes=...'` (как в примере), браузер добавляет его сам при перемотке видео.
- **`Content-Range` с неверными числами** — `end - start + 1` — частая ошибка на единицу (`off-by-one`): диапазон `0-999` — это **1000** байт, не 999.

### quiz
- Что означает код `206 Partial Content` в отличие от `200 OK`?
- Как клиент просит «докачать» файл с того места, где оборвалось соединение?
- Сколько байт в диапазоне `bytes=0-999`?

### outro
:::tip Приёмка сессии 15
Ты можешь: принять файл через multer и объяснить формат `multipart/form-data`; поставить лимит размера и обработать `413`; защититься от path traversal случайным именем на диске и объяснить разницу `originalname`/`filename`; отдать файл на скачивание потоком с правильным `Content-Disposition`; обработать `Range` для докачки. ShareBox умеет: загрузить файл (привязан к владельцу), скачать его потоком, удалить свой файл.
:::

### links
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Range | справочник по Range | MDN: Range
