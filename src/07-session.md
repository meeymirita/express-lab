# Сессия 7 · Аутентификация
dur: ~4 ч

## 7.1 Регистрация и хеширование пароля | short: Регистрация | est: ~30 мин
### intro
**Слова шага:** *хеш пароля* — необратимое преобразование пароля перед сохранением в базу; `argon2` — современный, специально медленный алгоритм хеширования паролей; *соль (salt)* — случайное значение, подмешиваемое к паролю перед хешированием.

Пароль **никогда** не хранят в базе как есть: если базу украдут, все пароли окажутся открытыми. Хранят **хеш** — результат необратимого преобразования; при входе сверяют хеш введённого пароля с сохранённым, а не сами пароли. **argon2** — современный алгоритм хеширования паролей (победитель конкурса Password Hashing Competition), медленный специально — это защита от перебора.

**Файл:** `argon2-demo.js`.

```bash run
cd /work/sharebox
npm install argon2 zod
cat > argon2-demo.js <<'EOF'
import argon2 from 'argon2'

const hash = await argon2.hash('supersecret123')
console.log('хеш:', hash.slice(0, 30) + '...')

console.log('верный пароль:', await argon2.verify(hash, 'supersecret123'))
console.log('неверный пароль:', await argon2.verify(hash, 'wrong'))

const hash2 = await argon2.hash('supersecret123')
console.log('два хеша одного пароля совпадают:', hash === hash2)
EOF
node argon2-demo.js
```

**Разбор.** `argon2.hash(пароль)` сам генерирует случайную **соль** и примешивает её к паролю перед хешированием — поэтому `hash` и `hash2` разные, хотя пароль один и тот же: без соли одинаковые пароли у разных пользователей давали бы одинаковый хеш, и по базе было бы видно, кто с кем использует один пароль. `argon2.verify(hash, пароль)` сам достаёт соль из хеша и проверяет.

### result
```out auto
```

### why
Это защищает пользователей ShareBox даже если база утечёт целиком: из хеша argon2 восстановить исходный пароль вычислительно нереально (в разумное время), а из простого `md5`/`sha256` без соли — вполне реально через готовые таблицы (rainbow tables).

### deep Если не получилось
- **`node-gyp` ошибка при установке `argon2`** — пакет содержит нативный код (на C), для сборки под некоторые платформы нужны инструменты сборки; в контейнере лабы они уже есть, на чистом Mac иногда требуется `xcode-select --install`.
- **Хеши выглядят одинаково в начале** — это нормально: формат `$argon2id$v=19$m=...` одинаков у всех хешей argon2 (это параметры алгоритма, не секрет), различается хвост.

### quiz
- Зачем нужна соль, если алгоритм хеширования и так необратим?
- Почему два хеша одного и того же пароля отличаются?
- Что сможет сделать злоумышленник, укравший базу с хешами argon2, но не сами пароли?

### links
- https://www.npmjs.com/package/argon2 | документация пакета argon2 для Node | npm: argon2

## 7.2 Роут регистрации | short: POST /auth/register | est: ~25 мин
### intro
**Слова шага:** *роут регистрации* — `POST /auth/register`, создающий нового пользователя; `409 Conflict` — код ответа «такой ресурс уже существует»; *дублирующийся email* — попытка зарегистрировать уже занятую почту.

Соберём настоящий роут: валидация (сессия 4) → проверка, что email свободен → хеш пароля → запись в базу.

**Файлы:** `lib/schemas.js`, `src/services/auth.service.js`, `src/controllers/auth.controller.js`, `src/routes/auth.routes.js`.

```bash run
mkdir -p src/routes src/controllers src/services
cat > lib/schemas.js <<'EOF'
import { z } from 'zod'

export const RegisterSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
})
EOF
cat > src/services/auth.service.js <<'EOF'
import argon2 from 'argon2'
import { prisma } from '../prisma.js'
import { AppError } from '../../lib/errors.js'

export async function registerUser(email, password) {
  const existing = await prisma.user.findUnique({ where: { email } })
  if (existing) throw new AppError('email уже занят', 409)
  const passwordHash = await argon2.hash(password)
  const user = await prisma.user.create({ data: { email, passwordHash } })
  return { id: user.id, email: user.email }
}
EOF
cat > src/controllers/auth.controller.js <<'EOF'
import { RegisterSchema } from '../../lib/schemas.js'
import { registerUser } from '../services/auth.service.js'

export async function register(req, res) {
  const parsed = RegisterSchema.safeParse(req.body)
  if (!parsed.success) {
    return res.status(400).json({ error: 'validation', issues: parsed.error.issues })
  }
  const user = await registerUser(parsed.data.email, parsed.data.password)
  res.status(201).json(user)
}
EOF
cat > src/routes/auth.routes.js <<'EOF'
import { Router } from 'express'
import { register } from '../controllers/auth.controller.js'

const router = Router()
router.post('/auth/register', register)
export default router
EOF
```

(Файл `server.js` подключим в шаге 7.4, когда появится полный роутер авторизации.)

### result
```out
(файлы созданы, подключение к server.js — в шаге 7.4; проверим всё вместе там)
```

### why
`409 Conflict` (а не `400`) — правильный код именно для «такой ресурс уже существует»: `400` означает «ты прислала что-то невалидное», а тут данные валидны, просто email занят — разница важна для клиента, который по коду решает, что показать пользователю («неверный формат» vs «уже зарегистрирован»).

### deep Если не получилось
- **Схема `email`/`password` не найдена в `lib/schemas.js`** — модуль создаётся первым блоком этого шага; если шаги выполнялись не по порядку, вернись и выполни заново.
- **Хочется сразу проверить роут** — он ещё не подключён к `server.js` (это шаг 7.4, где появится и вход) — так короче объяснять два связанных роута вместе.

### quiz
- Чем `409 Conflict` концептуально отличается от `400 Bad Request`?
- Почему `registerUser` сначала проверяет `findUnique`, а не просто пытается создать и ловит ошибку уникальности из базы?
- Что контроллер (`auth.controller.js`) делает сам, а что отдаёт сервису?

### links
- https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/409 | код ответа 409 | MDN: 409 Conflict

## 7.3 JWT: access и refresh токены | short: JWT-токены | est: ~35 мин
### intro
**Слова шага:** *JWT (JSON Web Token)* — подписанный токен с данными внутри, который сервер проверяет без похода в базу; *access-токен* — короткоживущий токен для каждого запроса; *refresh-токен* — долгоживущий токен для получения новой пары токенов; *подпись* — то, что не даёт подделать токен; *срок жизни (expiry)* — время, после которого токен перестаёт быть валидным.

После входа сервер не должен проверять пароль на **каждый** запрос — вместо этого выдаётся **токен**: подписанная секретным ключом строка, которую сервер может проверить без похода в базу. **JWT** — такой токен, состоящий из трёх частей (заголовок, данные, подпись), пара base64-блоков через точку.

Используют **два** токена: **access** — живёт недолго (минуты), именно он летает в каждом запросе; **refresh** — живёт долго (дни), хранится отдельно и нужен только для того, чтобы получить новый access, когда старый истёк — так утечка access-токена опаснее на меньший срок.

**Файлы:** `.env` (дописать), `jwt-demo.js`.

```bash run
npm install jsonwebtoken
cat >> .env <<'EOF'
JWT_SECRET=dev-secret-change-in-production
EOF
cat > jwt-demo.js <<'EOF'
import 'dotenv/config'
import jwt from 'jsonwebtoken'

const access = jwt.sign({ sub: 42, type: 'access' }, process.env.JWT_SECRET, { expiresIn: '15m' })
const refresh = jwt.sign({ sub: 42, type: 'refresh' }, process.env.JWT_SECRET, { expiresIn: '7d' })

console.log('access:', access.slice(0, 40) + '...')
const decoded = jwt.verify(access, process.env.JWT_SECRET)
console.log('расшифрован:', decoded)

try {
  jwt.verify(access, 'неправильный-секрет')
} catch (err) {
  console.log('с чужим секретом:', err.message)
}

const expired = jwt.sign({ sub: 42 }, process.env.JWT_SECRET, { expiresIn: '-1s' })
try {
  jwt.verify(expired, process.env.JWT_SECRET)
} catch (err) {
  console.log('просроченный токен:', err.message)
}
EOF
node jwt-demo.js
```

### result
```out auto
```

### why
`jwt.verify` проверяет подпись **локально**, без запроса к базе на каждый вход — это и есть главная причина использовать JWT вместо «проверять сессию в базе на каждый запрос»: быстрее и не нагружает базу. Но это же и риск: пока access-токен не истёк, отозвать его раньше времени нельзя (сервер его не хранит) — отсюда короткий срок жизни access и отдельный, более управляемый refresh.

### deep Под капотом
JWT **не шифрован**, а только подписан: `decoded` в примере виден любому, кто получит токен (можно раскодировать base64 без секрета) — секрет нужен только чтобы **подделать** подпись. Поэтому в `payload` никогда не кладут пароль или другие секреты — только `id` и неважные данные.

### deep Если не получилось
- **`jwt.verify` не падает на чужом секрете** — проверь, что секрет при создании и при чужой проверке действительно разные строки.
- **`JsonWebTokenError: invalid signature`** — это ожидаемая ошибка для чужого секрета в примере, не баг.

### quiz
- Почему JWT не стоит использовать для хранения секретных данных в payload?
- Зачем нужен отдельный refresh-токен, если можно было бы просто сделать access с долгим сроком жизни?
- Что проверяет `jwt.verify` и зачем ему нужен тот же секрет, что был при `jwt.sign`?

### links
- https://jwt.io/introduction | введение в JWT | JWT.io: Introduction
- https://www.npmjs.com/package/jsonwebtoken | документация jsonwebtoken | npm: jsonwebtoken

## 7.4 Вход, middleware авторизации | short: Вход и middleware | est: ~30 мин
### intro
**Слова шага:** `POST /auth/login` — роут входа, выдающий токены; `Authorization: Bearer` — заголовок, которым клиент присылает access-токен; *middleware авторизации* — проверяет токен и кладёт пользователя в `req.user`; `401 Unauthorized` — код ответа «не знаю, кто ты».

Соберём вход и middleware, который защищает роуты: читает заголовок `Authorization`, проверяет токен, кладёт `req.user`.

**Файлы:** `src/services/auth.service.js`, `lib/auth-middleware.js`, `src/controllers/auth.controller.js`, `src/routes/auth.routes.js`, `server.js`.

```bash run
cat > src/services/auth.service.js <<'EOF'
import argon2 from 'argon2'
import jwt from 'jsonwebtoken'
import { prisma } from '../prisma.js'
import { AppError } from '../../lib/errors.js'

export async function registerUser(email, password) {
  const existing = await prisma.user.findUnique({ where: { email } })
  if (existing) throw new AppError('email уже занят', 409)
  const passwordHash = await argon2.hash(password)
  const user = await prisma.user.create({ data: { email, passwordHash } })
  return { id: user.id, email: user.email }
}

function issueTokens(userId) {
  const access = jwt.sign({ sub: userId, type: 'access' }, process.env.JWT_SECRET, { expiresIn: '15m' })
  const refresh = jwt.sign({ sub: userId, type: 'refresh' }, process.env.JWT_SECRET, { expiresIn: '7d' })
  return { access, refresh }
}

export async function loginUser(email, password) {
  const user = await prisma.user.findUnique({ where: { email } })
  if (!user) throw new AppError('неверный email или пароль', 401)
  const ok = await argon2.verify(user.passwordHash, password)
  if (!ok) throw new AppError('неверный email или пароль', 401)
  return issueTokens(user.id)
}
EOF
cat > lib/auth-middleware.js <<'EOF'
import jwt from 'jsonwebtoken'
import { AppError } from './errors.js'

export function requireAuth(req, res, next) {
  const header = req.headers.authorization || ''
  const token = header.startsWith('Bearer ') ? header.slice(7) : null
  if (!token) return next(new AppError('нужен токен', 401))
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET)
    req.user = { id: payload.sub }
    next()
  } catch (err) {
    next(new AppError('невалидный или просроченный токен', 401))
  }
}
EOF
cat > src/controllers/auth.controller.js <<'EOF'
import { RegisterSchema } from '../../lib/schemas.js'
import { registerUser, loginUser } from '../services/auth.service.js'

export async function register(req, res) {
  const parsed = RegisterSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: 'validation', issues: parsed.error.issues })
  res.status(201).json(await registerUser(parsed.data.email, parsed.data.password))
}

export async function login(req, res) {
  const { email, password } = req.body
  res.json(await loginUser(email, password))
}

export function me(req, res) {
  res.json({ userId: req.user.id })
}
EOF
cat > src/routes/auth.routes.js <<'EOF'
import { Router } from 'express'
import { register, login, me } from '../controllers/auth.controller.js'
import { requireAuth } from '../../lib/auth-middleware.js'

const router = Router()
router.post('/auth/register', register)
router.post('/auth/login', login)
router.get('/auth/me', requireAuth, me)
export default router
EOF
cat > server.js <<'EOF'
import express from 'express'
import healthRoutes from './src/routes/health.routes.js'
import filesRoutes from './src/routes/files.routes.js'
import authRoutes from './src/routes/auth.routes.js'
import { migrate } from './src/migrate.js'

await migrate()

const app = express()
app.use(express.json())
app.use(healthRoutes)
app.use(filesRoutes)
app.use(authRoutes)

app.use((req, res) => res.status(404).json({ error: 'not_found' }))
app.use((err, req, res, next) => {
  console.error('поймано:', err.message)
  res.status(err.status || 500).json({ error: err.message || 'internal' })
})

const PORT = process.env.PORT || 3000
app.listen(PORT, () => console.log(`ShareBox слушает порт ${PORT}`))
EOF
node server.js &
SERVER_PID=$!
sleep 1
EMAIL="user-$(date +%s)@mail.com"
curl -s -X POST http://localhost:3000/auth/register -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"supersecret123\"}"
echo
TOKEN=$(curl -s -X POST http://localhost:3000/auth/login -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"supersecret123\"}" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).access))")
curl -s http://localhost:3000/auth/me -H "Authorization: Bearer $TOKEN"
echo
curl -s -o /dev/null -w 'без токена: %{http_code}\n' http://localhost:3000/auth/me
kill $SERVER_PID
```

### result
```out auto
```

### why
`requireAuth` — обычный middleware (сессия 3.4): ставится **перед** нужным роутом в цепочке и либо пропускает запрос дальше (`next()`), либо отдаёт ошибку. Такой же middleware в сессии 9 защитит удаление чужих файлов.

### deep Если не получилось
- **`401` на `/auth/me` с токеном** — токен не передан в формате `Bearer <токен>` (с пробелом после `Bearer`), сверь заголовок.
- **Регистрация успешна, вход — `401`** — пароль при регистрации и входе должен совпадать дословно; в примере оба `supersecret123`.

### quiz
- Что делает `requireAuth`, если заголовок `Authorization` отсутствует вообще?
- Откуда middleware берёт `userId` после успешной проверки токена, и куда он его кладёт для следующих обработчиков?
- Почему проверка в `loginUser` возвращает одно и то же сообщение «неверный email или пароль» и для несуществующего email, и для неверного пароля?

### links
- https://expressjs.com/en/guide/writing-middleware.html | свой middleware | Express: Writing middleware

## 7.5 Ротация refresh-токена | short: Ротация refresh | est: ~25 мин
### intro
**Слова шага:** *ротация (rotation)* — каждый `refresh` выдаёт новую пару токенов взамен старой; `POST /auth/refresh` — роут обновления токенов по живому refresh-токену; *повторное использование токена* — риск, которого ротация и призвана уменьшить.

Короткий access неудобен, если пользователю приходится логиниться каждые 15 минут. Решение — роут `/auth/refresh`: прислал ещё живой refresh-токен → получил новую пару access+refresh. **Ротация** — каждый refresh выдаётся на замену предыдущему, а не используется повторно.

**Файлы:** `src/services/auth.service.js` (дописать), `src/controllers/auth.controller.js` (дописать).

```bash run
cat >> src/services/auth.service.js <<'EOF'

export function refreshTokens(refreshToken) {
  const payload = jwt.verify(refreshToken, process.env.JWT_SECRET)
  if (payload.type !== 'refresh') throw new AppError('это не refresh-токен', 401)
  return issueTokens(payload.sub)
}
EOF
cat >> src/controllers/auth.controller.js <<'EOF'

export function refresh(req, res) {
  res.json(refreshTokens(req.body.refreshToken))
}
EOF
sed -i.bak "s/^import { registerUser, loginUser } from '..\/services\/auth.service.js'/import { registerUser, loginUser, refreshTokens } from '..\/services\/auth.service.js'/" src/controllers/auth.controller.js
rm -f src/controllers/auth.controller.js.bak
sed -i.bak "s/^import { register, login, me } from '..\/controllers\/auth.controller.js'/import { register, login, refresh, me } from '..\/controllers\/auth.controller.js'/" src/routes/auth.routes.js
sed -i.bak "/router.post('\/auth\/login', login)/a router.post('/auth/refresh', refresh)" src/routes/auth.routes.js
rm -f src/routes/auth.routes.js.bak
node server.js &
SERVER_PID=$!
sleep 1
EMAIL="user-$(date +%s)@mail.com"
curl -s -X POST http://localhost:3000/auth/register -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"supersecret123\"}" > /dev/null
LOGIN=$(curl -s -X POST http://localhost:3000/auth/login -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"supersecret123\"}")
REFRESH=$(echo "$LOGIN" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).refresh))")
curl -s -X POST http://localhost:3000/auth/refresh -H 'Content-Type: application/json' -d "{\"refreshToken\":\"$REFRESH\"}"
echo
kill $SERVER_PID
```

### result
```out auto
```

### why
Эта лаба не хранит выданные refresh-токены в базе (упрощение для учебных целей — в «Production Hell» сессии 11 разберём, чего этому не хватает для настоящего прода: таблицы отозванных токенов, чтобы украденный refresh можно было отозвать досрочно). Но сам принцип ротации — выдавать новую пару при каждом обновлении — защищает от долгоживущих токенов в логах и истории браузера.

### deep Если не получилось
- **`sed` не находит строку для вставки** — проверь точное совпадение (включая кавычки) с тем, что реально в `auth.controller.js`/`auth.routes.js` после шага 7.4; при расхождении проще открыть файл и дописать функцию/роут вручную.
- **`refresh` возвращает `401` сразу после `login`** — убедись, что `REFRESH` в переменной — это именно значение поля `refresh` из ответа `/auth/login`, а не `access`.
- **`ReferenceError: refresh is not defined` при старте сервера** — добавила роут `router.post('/auth/refresh', refresh)` в `auth.routes.js`, но не добавила `refresh` в импорт из `auth.controller.js` в той же строке файла; без этого сервер падает при запуске. Проверь строку `import { register, login, refresh, me } from '../controllers/auth.controller.js'`.

### quiz
- Что проверяет `if (payload.type !== 'refresh')` и зачем, если токен уже прошёл `jwt.verify`?
- Чего не хватает этой реализации, чтобы досрочно отозвать украденный refresh-токен (ответь своими словами, подробно — в сессии 11)?
- Почему `/auth/refresh` выдаёт новую пару токенов, а не продлевает старый access?

### links
- https://auth0.com/docs/secure/tokens/refresh-tokens/refresh-token-rotation | ротация refresh-токенов, подробно | Auth0 Docs: Refresh Token Rotation

## 7.6 Владение ресурсом | short: Владение ресурсом | est: ~25 мин
### intro
**Слова шага:** *владение ресурсом (ownership)* — проверка, что пользователь действует со своими, а не чужими данными; `403 Forbidden` — код ответа «знаю, кто ты, но тебе сюда нельзя»; *проверка на уровне контроллера* — сравнение владельца ресурса с текущим пользователем в коде.

Авторизация (знаешь, **кто** ты) — не то же самое, что права доступа (можешь ли ты **это**). Пользователь A не должен иметь возможности удалить файл пользователя B, даже зная его `id`. Добавим проверку владения в удаление файла:

**Файлы:** `src/services/files.service.js`, `src/controllers/files.controller.js`, `src/routes/files.routes.js`.

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
cat > src/controllers/files.controller.js <<'EOF'
import { getFileOrThrow, deleteOwnedFile } from '../services/files.service.js'

export async function getFile(req, res) {
  res.json(await getFileOrThrow(req.params.id))
}

export async function deleteFile(req, res) {
  res.json(await deleteOwnedFile(Number(req.params.id), req.user.id))
}
EOF
cat > src/routes/files.routes.js <<'EOF'
import { Router } from 'express'
import { getFile, deleteFile } from '../controllers/files.controller.js'
import { requireAuth } from '../../lib/auth-middleware.js'

const router = Router()
router.get('/files/:id', getFile)
router.delete('/files/:id', requireAuth, deleteFile)
export default router
EOF
node server.js &
SERVER_PID=$!
sleep 1
EMAIL_A="owner-$(date +%s)@mail.com"
EMAIL_B="stranger-$(date +%s)@mail.com"
curl -s -X POST http://localhost:3000/auth/register -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL_A\",\"password\":\"supersecret123\"}" > /dev/null
curl -s -X POST http://localhost:3000/auth/register -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL_B\",\"password\":\"supersecret123\"}" > /dev/null
TOKEN_B=$(curl -s -X POST http://localhost:3000/auth/login -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL_B\",\"password\":\"supersecret123\"}" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>console.log(JSON.parse(d).access))")
curl -s -o /dev/null -w 'чужой файл, чужой токен: %{http_code}\n' -X DELETE http://localhost:3000/files/1 -H "Authorization: Bearer $TOKEN_B"
kill $SERVER_PID
```

### result
```out auto
```

### why
`401 Unauthorized` значит «я не знаю, кто ты» (нет или невалиден токен); `403 Forbidden` значит «я знаю, кто ты, но тебе сюда нельзя» — разные ситуации с разным ответом клиенту. Проверка владения — ровно то место, где `req.user.id` из `requireAuth` (шаг 7.4) встречается с `ownerId` из базы.

### deep Если не получилось
- **Смешались `401` и `403` в коде** — если сомневаешься, задай вопрос: «известен ли сервер, кто перед ним?» Если нет — `401`. Если да, но ему сюда нельзя — `403`.
- **`403` вместо ожидаемого удаления** — в примере специально используется файл с `id=1`, который, скорее всего, принадлежит не `EMAIL_B`; это и есть демонстрация защиты, не баг.

### quiz
- Чем отличаются ситуации, в которых уместен `401`, а в которых `403`?
- Где именно в коде сравниваются «кто спрашивает» и «кто владеет»?
- Что произойдёт, если убрать проверку `file.ownerId !== userId` совсем?

### outro
:::tip Приёмка сессии 7
Ты можешь: захешировать пароль через argon2 и объяснить роль соли; выдать и проверить JWT, объяснить разницу access/refresh; защитить роут middleware'ом авторизации; обновить токены через ротацию refresh; отличить «не авторизован» (401) от «нет прав» (403) и проверить владение ресурсом. ShareBox умеет регистрацию, вход, `/auth/me`, обновление токенов и защищённое удаление файла.
:::

### links
- https://expressjs.com/en/resources/middleware/cors.html | опционально: как устроены заголовки авторизации в запросах | Express: Resources (middleware)
