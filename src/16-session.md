# Сессия 16 · Share-ссылки и консоль
dur: ~4 ч

## 16.1 Код ссылки и создание share | short: Код ссылки | est: ~25 мин
### intro
**Слова шага:** *код ссылки* — короткий случайный идентификатор в адресе ссылки; `nanoid` — генератор таких строк; `POST /shares` — роут создания share-ссылки на файл (`fileId` — в теле запроса).

Делиться файлом — не значит отдавать его `id` из базы (последовательный, легко перебрать). Нужен отдельный короткий случайный **код** — то, что видно в адресе `/s/<код>`.

**Файлы:** `src/services/shares.service.js`, `nanoid-demo.js`.

```bash run
cd /work/sharebox
npm install nanoid
cat > src/services/shares.service.js <<'EOF'
import { nanoid } from 'nanoid'
import { prisma } from '../prisma.js'
import { AppError } from '../../lib/errors.js'

export async function createShare(fileId, ownerId, { expiresInHours, downloadLimit, password } = {}) {
  const file = await prisma.file.findUnique({ where: { id: fileId } })
  if (!file || file.ownerId !== ownerId) throw new AppError('файл не найден или не твой', 403)
  const expiresAt = expiresInHours ? new Date(Date.now() + expiresInHours * 3600 * 1000) : null
  return prisma.share.create({
    data: {
      fileId,
      code: nanoid(8),
      expiresAt,
      downloadLimit: downloadLimit || null,
    },
  })
}
EOF
cat > nanoid-demo.js <<'EOF'
import { nanoid } from 'nanoid'
console.log(nanoid(8), nanoid(8), nanoid(8))
EOF
node nanoid-demo.js
```

**Разбор.** `nanoid(8)` — короткий случайный id из URL-безопасных символов (без `+`, `/`, как у base64) — удобно вставлять прямо в адрес. `expiresInHours` переводится в точную дату `expiresAt` **в момент создания**, а не хранится как «через сколько часов» — проверка истечения (шаг 16.2) тогда просто сравнивает с текущим временем, без пересчётов.

### result
```out auto
```

### why
Код ссылки `nanoid(8)` — это ~218 триллионов комбинаций, перебором не угадать за разумное время; `id` файла из базы (1, 2, 3...) — наоборот, тривиально перебрать. Share-ссылка всегда отдельная сущность от самого файла: один файл может иметь несколько ссылок с разными сроками и лимитами (разным людям — разные условия).

### deep Если не получилось
- **`Cannot find module 'nanoid'`** — `npm install nanoid` не выполнен; версии 4+ — чистый ESM, `import { nanoid }`, без `require`.
- **`expiresAt` — не дата, а `NaN`** — `expiresInHours` передан строкой вместо числа; `req.body` всегда присылает JSON-типы как есть, но стоит валидировать zod-схемой (как в сессии 11), если данные приходят от клиента.

### quiz
- Почему код share-ссылки — отдельное случайное значение, а не просто `id` файла?
- Как `expiresInHours` превращается в `expiresAt`, и почему это делается один раз при создании, а не каждый раз при проверке?
- Может ли у одного файла быть несколько share-ссылок одновременно?

### links
- https://github.com/ai/nanoid#readme | nanoid, как устроен | nanoid: README

## 16.2 Срок жизни, лимит скачиваний, 410 Gone | short: Срок и лимит | est: ~30 мин
### intro
**Слова шага:** `410 Gone` — код ответа «было, но больше недоступно»; *истёкшая ссылка* — share-ссылка с истёкшим сроком действия; *исчерпанный лимит* — ссылка, которую скачали уже максимум разрешённых раз; `downloadsCount` — счётчик скачиваний ссылки в базе.

Проверка при переходе по ссылке: существует ли код, не истёк ли срок, не исчерпан ли лимит скачиваний. **`410 Gone`** — специальный код именно для «было, но больше недоступно» (в отличие от `404 Not Found` — «никогда не было»).

**Файлы:** `src/services/shares.service.js` (дописать), `shares-logic-demo.js`.

```bash run
cat >> src/services/shares.service.js <<'EOF'

export async function resolveShare(code) {
  const share = await prisma.share.findUnique({ where: { code }, include: { file: true } })
  if (!share) {
    const { NotFoundError } = await import('../../lib/errors.js')
    throw new NotFoundError('ссылка не найдена')
  }
  if (share.expiresAt && share.expiresAt < new Date()) {
    throw new AppError('срок действия ссылки истёк', 410)
  }
  if (share.downloadLimit && share.downloadsCount >= share.downloadLimit) {
    throw new AppError('лимит скачиваний исчерпан', 410)
  }
  return share
}

export async function registerDownload(shareId) {
  await prisma.share.update({ where: { id: shareId }, data: { downloadsCount: { increment: 1 } } })
}
EOF
cat > shares-logic-demo.js <<'EOF'
const now = new Date()
const pastExpiry = new Date(now.getTime() - 3600 * 1000)
const futureExpiry = new Date(now.getTime() + 3600 * 1000)
console.log('просроченная ссылка:', pastExpiry < now)
console.log('ещё живая ссылка:', futureExpiry < now)
EOF
node shares-logic-demo.js
```

**Разбор.** `downloadsCount: { increment: 1 }` — атомарная операция на уровне базы («увеличь текущее значение на 1»), а не «прочитать, прибавить в JS, записать обратно» — последнее подвержено гонке при двух одновременных скачиваниях (несколько запросов могут выполняться «одновременно» с точки зрения клиента — event loop из js-lab). `resolveShare` — одна функция, которую вызовут и для скачивания (16.5), и для HTML-страницы (16.4): логика проверки в одном месте.

### result
```out auto
```

### why
`410` вместо `404` для истёкшей ссылки — не просто вежливость: клиентский код (или человек, читающий ответ) по коду понимает, что ссылка **была** валидна, просто время/лимит вышли — это другая ситуация, чем «опечатка в адресе».

### deep Если не получилось
- **Гонка при одновременных скачиваниях увеличивает счётчик неправильно** — если вместо `{ increment: 1 }` писать `downloadsCount: share.downloadsCount + 1`, два параллельных запроса могут оба прочитать одно и то же старое значение и оба прибавить к нему по 1 — итог `+1`, а не `+2`; `increment` в Prisma превращается в SQL `downloads_count = downloads_count + 1`, выполняемый самой базой атомарно.

### quiz
- Чем `410 Gone` концептуально отличается от `404 Not Found`?
- Почему `downloadsCount: { increment: 1 }` безопаснее, чем прочитать значение в JS и прибавить единицу?
- Что проверяется раньше — срок действия или лимит скачиваний, и важен ли этот порядок?

### links
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/410 | код ответа 410 | MDN: 410 Gone

## 16.3 Пароль на ссылку | short: Пароль на ссылку | est: ~20 мин
### intro
**Слова шага:** *опциональный пароль* — share-ссылка может быть без пароля (открыта всем) или с паролем; `401` при неверном пароле на скачивание — код ответа, если пароль не подошёл.

Share-ссылка может быть с паролем — тем же способом хеширования, что и пароль пользователя (сессия 14, argon2), только отдельное поле `passwordHash` у `Share`, не у `User`.

**Файлы:** `src/services/shares.service.js` (дописать), `share-password-demo.js`.

```bash run
cat >> src/services/shares.service.js <<'EOF'

export async function checkSharePassword(share, providedPassword) {
  if (!share.passwordHash) return true
  if (!providedPassword) return false
  const argon2 = (await import('argon2')).default
  return argon2.verify(share.passwordHash, providedPassword)
}
EOF
cat > share-password-demo.js <<'EOF'
import argon2 from 'argon2'

const passwordHash = await argon2.hash('letmein')
console.log('верный пароль:', await argon2.verify(passwordHash, 'letmein'))
console.log('неверный пароль:', await argon2.verify(passwordHash, 'guess'))
EOF
node share-password-demo.js
```

### result
```out auto
```

### why
Пароль на ссылку — независимая возможность от пароля аккаунта: получатель файла может вообще не иметь аккаунта ShareBox (паспорт лабы: «получателю аккаунт не нужен, если ссылка публичная»), но для чувствительного файла автор может потребовать пароль именно на эту ссылку.

### deep Если не получилось
- **`checkSharePassword` всегда возвращает `true`** — `share.passwordHash` пустой (`null`), если пароль не задавался при создании ссылки (шаг 16.1 это поддерживает как опциональный параметр) — поведение правильное: без пароля ссылка открыта всем.

### quiz
- Чем пароль на ссылку отличается от пароля пользователя из сессии 14 с точки зрения модели данных?
- Что вернёт `checkSharePassword`, если у ссылки нет пароля вообще?
- Каким алгоритмом хешируется пароль ссылки?

### links
- https://www.npmjs.com/package/argon2 | argon2, ещё раз для повторения | npm: argon2

## 16.4 HTML-страница скачивания | short: Страница скачивания | est: ~30 мин
### intro
**Слова шага:** *рендер HTML без шаблонизатора* — страница собирается обычной шаблонной строкой JS, без отдельного движка вроде EJS; `res.send` — отправить готовую HTML-строку клиенту; *форма пароля* — `<form>` на странице скачивания, если у ссылки есть пароль.

Получатель переходит по `/s/:code` в браузере — ему нужна простая HTML-страница, не JSON. Без фреймворка шаблонов (за пределами паспорта лабы — «клиент в Vue/Nuxt-лабах») — достаточно строки с HTML:

**Файл:** `src/controllers/shares.controller.js`.

```bash run
cat > src/controllers/shares.controller.js <<'EOF'
import { createShare, resolveShare, checkSharePassword } from '../services/shares.service.js'

export async function postShare(req, res) {
  const share = await createShare(req.body.fileId, req.user.id, req.body)
  res.status(201).json({ code: share.code, url: `/s/${share.code}` })
}

export async function getSharePage(req, res) {
  const share = await resolveShare(req.params.code)
  if (share.passwordHash) {
    return res.send(`<!doctype html>
<meta charset="utf-8">
<h1>${share.file.name}</h1>
<form method="POST" action="/s/${share.code}/download">
  <input type="password" name="password" placeholder="Пароль от ссылки">
  <button type="submit">Скачать</button>
</form>`)
  }
  res.send(`<!doctype html>
<meta charset="utf-8">
<h1>${share.file.name}</h1>
<p>Размер: ${share.file.sizeBytes} байт</p>
<a href="/s/${share.code}/download">Скачать</a>`)
}
EOF
echo "контроллер страницы готов; роуты и проверка запуском — в шаге 16.5 вместе со скачиванием"
```

### result
```out
(контроллер создан; проверка запуском — в 9.5)
```

### why
`res.send(строка)` — Express сам определяет `Content-Type: text/html` по содержимому строки (начинается с `<`); для JSON использовался `res.json`, здесь — обычный HTML-текст. Форма с паролем — простейший вариант без JavaScript на странице: обычная `<form method="POST">`, которую поймёт роут скачивания (следующий шаг).

### deep Если не получилось
- **На странице видно `${share.file.name}` буквально** — используются не те кавычки; шаблонная строка JS требует обратных кавычек `` ` ``, а не обычных `'` или `"`.
- **`share.file` — `undefined`** — `resolveShare` должен делать `include: { file: true }` при поиске (шаг 16.2); без этого в `share` нет связанного файла.

### quiz
- Как Express понимает, что отдавать в `Content-Type` — JSON или HTML?
- Что отличает страницу со ссылкой с паролем от страницы без пароля в этом коде?
- Какой HTTP-метод указан у формы ввода пароля и почему не GET?

### links
- https://expressjs.com/en/api.html#res.send | справочник по res.send | Express: res.send

## 16.5 Скачивание по share-коду | short: GET /s/:code/download | est: ~30 мин
### intro
**Слова шага:** *сборка всех шагов сессии* — шаги 16.1–9.4 собираются в рабочие роуты одним файлом; *счётчик скачиваний на лету* — `downloadsCount` увеличивается прямо при скачивании, атомарно в базе.

Соберём 9.1–9.4 в рабочие роуты: страница, форма с паролем, само скачивание потоком (сессия 15) с увеличением счётчика.

Соберём сервис и контроллер **целиком** — одним чистым файлом каждый, вместо накопленных за шаги 16.1–9.4 добавлений:

**Файлы:** `src/services/shares.service.js`, `src/controllers/shares.controller.js`, `src/routes/shares.routes.js`.

```bash run
cat > src/services/shares.service.js <<'EOF'
import { nanoid } from 'nanoid'
import argon2 from 'argon2'
import { prisma } from '../prisma.js'
import { AppError, NotFoundError } from '../../lib/errors.js'

export async function createShare(fileId, ownerId, { expiresInHours, downloadLimit, password } = {}) {
  const file = await prisma.file.findUnique({ where: { id: fileId } })
  if (!file || file.ownerId !== ownerId) throw new AppError('файл не найден или не твой', 403)
  const expiresAt = expiresInHours ? new Date(Date.now() + expiresInHours * 3600 * 1000) : null
  const passwordHash = password ? await argon2.hash(password) : null
  return prisma.share.create({
    data: { fileId, code: nanoid(8), expiresAt, downloadLimit: downloadLimit || null, passwordHash },
  })
}

export async function resolveShare(code) {
  const share = await prisma.share.findUnique({ where: { code }, include: { file: true } })
  if (!share) throw new NotFoundError('ссылка не найдена')
  if (share.expiresAt && share.expiresAt < new Date()) throw new AppError('срок действия ссылки истёк', 410)
  if (share.downloadLimit && share.downloadsCount >= share.downloadLimit) {
    throw new AppError('лимит скачиваний исчерпан', 410)
  }
  return share
}

export async function checkSharePassword(share, providedPassword) {
  if (!share.passwordHash) return true
  if (!providedPassword) return false
  return argon2.verify(share.passwordHash, providedPassword)
}

export async function registerDownload(shareId) {
  await prisma.share.update({ where: { id: shareId }, data: { downloadsCount: { increment: 1 } } })
}
EOF
cat > src/controllers/shares.controller.js <<'EOF'
import { createReadStream } from 'node:fs'
import { createShare, resolveShare, checkSharePassword, registerDownload } from '../services/shares.service.js'

export async function postShare(req, res) {
  const share = await createShare(req.body.fileId, req.user.id, req.body)
  res.status(201).json({ code: share.code, url: `/s/${share.code}` })
}

export async function getSharePage(req, res) {
  const share = await resolveShare(req.params.code)
  if (share.passwordHash) {
    return res.send(`<!doctype html>
<meta charset="utf-8">
<h1>${share.file.name}</h1>
<form method="POST" action="/s/${share.code}/download">
  <input type="password" name="password" placeholder="Пароль от ссылки">
  <button type="submit">Скачать</button>
</form>`)
  }
  res.send(`<!doctype html>
<meta charset="utf-8">
<h1>${share.file.name}</h1>
<p>Размер: ${share.file.sizeBytes} байт</p>
<a href="/s/${share.code}/download">Скачать</a>`)
}

export async function downloadByShare(req, res) {
  const share = await resolveShare(req.params.code)
  const ok = await checkSharePassword(share, req.body?.password)
  if (!ok) return res.status(401).send('Неверный пароль')
  await registerDownload(share.id)
  res.setHeader('Content-Disposition', `attachment; filename="${encodeURIComponent(share.file.name)}"`)
  createReadStream(share.file.storedPath).pipe(res)
}
EOF
cat > src/routes/shares.routes.js <<'EOF'
import { Router } from 'express'
import { postShare, getSharePage, downloadByShare } from '../controllers/shares.controller.js'
import { requireAuth } from '../../lib/auth-middleware.js'

const router = Router()
router.post('/shares', requireAuth, postShare)
router.get('/s/:code', getSharePage)
router.post('/s/:code/download', downloadByShare)
router.get('/s/:code/download', downloadByShare)
export default router
EOF
sed -i.bak "/import authRoutes/a import sharesRoutes from './src/routes/shares.routes.js'" server.js
sed -i.bak "/app.use(authRoutes)/a app.use(sharesRoutes)" server.js
rm -f server.js.bak
node server.js &
SERVER_PID=$!
sleep 2
EMAIL="sharer-$(date +%s)@mail.com"
curl -s -X POST http://localhost:3000/auth/register -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"supersecret123\"}" > /dev/null
TOKEN=$(curl -s -X POST http://localhost:3000/auth/login -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"supersecret123\"}" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).access))")
echo "файл для шаринга" > share-me.txt
UPLOAD=$(curl -s -F "file=@share-me.txt;type=text/plain" -H "Authorization: Bearer $TOKEN" http://localhost:3000/files)
FILE_ID=$(echo "$UPLOAD" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).id))")
SHARE=$(curl -s -X POST http://localhost:3000/shares -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "{\"fileId\":$FILE_ID}")
echo "$SHARE"
CODE=$(echo "$SHARE" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).code))")
curl -s http://localhost:3000/s/$CODE | head -3
curl -s http://localhost:3000/s/$CODE/download
kill $SERVER_PID
```

### result
```out auto
```

### why
Это первый сквозной путь ShareBox целиком: регистрация → вход → загрузка → создание ссылки → переход по ссылке → скачивание. Всё, что писалось по частям в прошлых сессиях, здесь впервые работает вместе.

### deep Если не получилось
- **`downloadByShare` не увеличивает счётчик** — `registerDownload` должен вызываться **после** успешной проверки пароля, но **до** отдачи файла — если поставить после `pipe(res)`, поток уже начал отправку, а код может не успеть выполниться до завершения запроса.
- **GET и POST на одном пути `/s/:code/download`** — сделаны оба специально: GET — для ссылки без пароля (прямая ссылка на скачивание), POST — для формы с паролем из шага 16.4.

### quiz
- Перечисли по шагам весь путь от регистрации до успешного скачивания файла по ссылке.
- Почему `registerDownload` вызывается до `pipe(res)`, а не после?
- Зачем на `/s/:code/download` зарегистрированы и GET, и POST?

### links
- https://expressjs.com/en/guide/routing.html | роутинг, финальное повторение | Express: Routing

## 16.6 Скачивание из консоли с нуля | short: curl, wget, докачка | est: ~25 мин
### intro
**Слова шага:** `curl -O` — скачать и сохранить под именем с сервера; `wget -c` — скачать с докачкой при повторном запуске; `curl -C -` — докачать файл, сама вычислив, с какого байта; `sha256sum` — посчитать контрольную сумму файла; *PowerShell `Invoke-WebRequest`* — аналог `curl`/`wget` на Windows.

Получатель ShareBox не обязан открывать браузер — ссылку можно скачать прямо из консоли. Это пригодится и для проверки собственного сервиса.

```bash
curl -O http://localhost:3000/s/КОД/download
wget http://localhost:3000/s/КОД/download
```

```bash
curl -C - -O http://localhost:3000/s/КОД/download
wget -c http://localhost:3000/s/КОД/download
```

На Windows без `curl`/`wget` — PowerShell:

```powershell
Invoke-WebRequest -Uri "http://localhost:3000/s/КОД/download" -OutFile "файл.bin"
```

Проверить, что скачанный файл — ровно тот же, что был загружен (данные не повредились при передаче), сверяют **контрольной суммой**:

```bash run
cd /work/sharebox
echo "проверка целостности" > integrity-demo.txt
sha256sum integrity-demo.txt
cp integrity-demo.txt integrity-demo-copy.txt
sha256sum integrity-demo-copy.txt
echo "испорченная версия" > integrity-demo-broken.txt
sha256sum integrity-demo-broken.txt
```

**Разбор.** `-O` у `curl` — сохранить под именем, которое указал сервер (`Content-Disposition`, шаг 15.5), а не печатать в терминал. `-C -` у `curl` и `-c` у `wget` — докачать, если файл уже частично скачан (используют `Range`, шаг 15.6: `-` в `-C -` означает «вычисли точку докачки сама»). `sha256sum` — хеш содержимого файла (не путать с хешем пароля, шаг 14.1, но тот же принцип: одинаковый вход → одинаковый хеш).

### result
```out auto
```

### why
Два одинаковых файла (оригинал и копия) дают одинаковый `sha256sum`; испорченный (другое содержимое) — другой. Это способ убедиться, что ShareBox передал файл **без потерь**, даже после докачки по частям через `Range` — просуммировать готовый файл и сравнить с суммой, которую мог бы предоставить автор ссылки.

### deep Если не получилось
- **`curl: command not found` на Windows** — используй PowerShell-вариант (`Invoke-WebRequest`) или поставь `curl` отдельно (в современной Windows 10/11 он уже встроен).
- **`wget: command not found` на Mac** — на Mac по умолчанию нет `wget` (только `curl`); `brew install wget`, если нужен именно он, либо используй `curl -C -`.

### quiz
- Что делает `-O` у `curl` и зачем он нужен при скачивании через share-ссылку?
- Как докачать файл, не начиная заново, если соединение оборвалось на середине?
- Как проверить, что скачанный файл не повреждён, без ручного сравнения байт за байтом?

### outro
:::tip Приёмка сессии 16
Ты можешь: создать share-ссылку со случайным кодом, сроком жизни и лимитом скачиваний; объяснить разницу `404`/`410`; защитить ссылку паролем; отдать простую HTML-страницу скачивания; собрать весь путь от регистрации до скачивания по ссылке; скачать файл из консоли (`curl`/`wget`/PowerShell) с докачкой и проверить целостность через `sha256sum`. ShareBox теперь — рабочий файлообменник end-to-end.
:::

### links
- https://curl.se/docs/manpage.html | полный справочник curl | curl: Manual
