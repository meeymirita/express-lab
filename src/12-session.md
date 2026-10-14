# Сессия 12 · PostgreSQL и SQL
dur: ~4 ч

## 12.1 Docker Compose с базой | short: Compose и база | est: ~25 мин
### intro
**Слова шага:** *PostgreSQL* — реляционная база данных; *Docker Compose* — описывает и поднимает несколько контейнеров одним файлом; *том (volume)* — хранилище данных контейнера, переживающее перезапуск; *порт контейнера* — через него снаружи подключаются к сервису внутри.

До сих пор ShareBox хранил данные прямо в коде (`Map` в сессии 5.1). Настоящим хранилищем будет **PostgreSQL** — реляционная база. Поднимем её в контейнере через **Docker Compose** — он описывает один или несколько контейнеров одним файлом и поднимает их одной командой. *Здесь и дальше Docker запускается только с твоего согласия.*

```bash run hidden
mkdir -p /work/sharebox-db-demo
```

```text
version: '3.9'
services:
  db:
    image: postgres:18
    environment:
      POSTGRES_USER: sharebox
      POSTGRES_PASSWORD: sharebox
      POSTGRES_DB: sharebox
    ports:
      - '5432:5432'
    volumes:
      - db-data:/var/lib/postgresql
volumes:
  db-data:
```

Сохрани это как `compose.yaml` в `/work/sharebox` и подними:

```bash
docker compose up -d
docker compose ps
```

### result
```out
NAME                 IMAGE          STATUS
sharebox-db-1        postgres:18    Up (healthy)
```

### why
`POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB` — переменные, которые образ `postgres` читает сам при первом старте и создаёт пользователя и базу с этими именами. **Том** `db-data:/var/lib/postgresql` — данные базы переживают перезапуск и пересборку контейнера (удалишь контейнер — данные останутся в томе; удалишь том — данные пропадут). Порт `5432:5432` — слева порт на твоём Mac, справа — порт внутри контейнера; через него Node (вне контейнера) сможет подключиться к базе (внутри).

### deep Как ещё можно
Вместо Docker — `brew install postgresql@18` и запустить локально (паспорт лабы это допускает как запасной путь): тогда база слушает `localhost:5432` без контейнера вообще, а имя пользователя/базы создаются командой `createdb`.

### deep Если не получилось
- **`port is already allocated`** — на 5432 уже что-то слушает (другая Postgres); останови её или поменяй левую часть порта, например `5433:5432`, и подключайся на 5433.
- **`Up (unhealthy)` долго** — первый старт образа инициализирует базу, может занять 10–20 секунд; подожди и проверь `docker compose ps` снова.

### quiz
- Что произойдёт с данными в базе, если удалить контейнер, но не трогать том?
- Что означают две части `5432:5432` в `ports`?
- Откуда образ `postgres` берёт имя пользователя и базы при первом запуске?

### links
- https://docs.docker.com/compose/ | документация Docker Compose | Docker: Compose
- https://hub.docker.com/_/postgres | официальный образ PostgreSQL | Docker Hub: postgres

## 12.2 Подключение: пакет pg и пул соединений | short: pg и пул | est: ~25 мин
### intro
**Слова шага:** `pg` — драйвер для подключения Node к PostgreSQL; *пул соединений (connection pool)* — несколько открытых соединений наготове вместо одного на каждый запрос; `DATABASE_URL` — строка подключения к базе одной строкой; `query` — выполнить SQL-запрос через пул.

Node не умеет говорить с PostgreSQL сам по себе — нужен драйвер. **`pg`** — самый распространённый. Вместо одного соединения используют **пул**: несколько уже открытых соединений наготове, потому что открывать новое на каждый запрос слишком медленно.

**Файлы:** `.env` (дописать), `src/db.js`, `db-demo.js`.

```bash run
cd /work/sharebox
npm install pg
cat >> .env <<'EOF'
DATABASE_URL=postgresql://sharebox:sharebox@localhost:5432/sharebox
EOF
cat > src/db.js <<'EOF'
import 'dotenv/config'
import pg from 'pg'

export const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL })
EOF
cat > db-demo.js <<'EOF'
import { pool } from './src/db.js'

const result = await pool.query('select version()')
console.log(result.rows[0].version.split(',')[0])
await pool.end()
EOF
node db-demo.js
```

**Разбор.** `connectionString` в формате `postgresql://пользователь:пароль@хост:порт/база` — одна строка вместо пяти отдельных настроек. `pool.query(sql)` сам берёт свободное соединение из пула, выполняет и возвращает его обратно. `pool.end()` — закрыть все соединения пула (без этого процесс Node не завершился бы сам — пул держит их открытыми).

### result
```out
(нет вывода: шаг требует запущенной Postgres из 5.1 — у тебя будет настоящая версия вида «PostgreSQL 18.x»)
```

### why
Пул — то, что позволит ShareBox обслуживать много параллельных запросов (event loop — из js-lab), не дожидаясь по очереди одного-единственного соединения. `DATABASE_URL` в `.env` — ровно то, ради чего в сессии 11 заводился `.env`: пароль от базы никогда не попадёт в git.

### deep Если не получилось
- **`ECONNREFUSED 127.0.0.1:5432`** — база из шага 12.1 не запущена; `docker compose ps` должен показывать `Up`.
- **`password authentication failed`** — пользователь/пароль в `DATABASE_URL` не совпадают с `POSTGRES_USER`/`POSTGRES_PASSWORD` из `compose.yaml`.

### quiz
- Зачем нужен пул соединений вместо одного соединения на весь процесс?
- Что произойдёт с процессом Node, если не вызвать `pool.end()`?
- Из каких частей состоит `DATABASE_URL`?

### links
- https://node-postgres.com/features/pooling | пул соединений в node-postgres | node-postgres: Pooling

## 12.3 SQL руками: таблицы ShareBox | short: Таблицы | est: ~30 мин
### intro
**Слова шага:** `CREATE TABLE` — создать таблицу в базе; *первичный ключ* — уникальный идентификатор строки (`id`); *внешний ключ (foreign key)* — поле, ссылающееся на строку другой таблицы; `REFERENCES` — ключевое слово, которым задают внешний ключ.

Спроектируем три таблицы под ShareBox: пользователи, файлы, share-ссылки.

```text
users   (id, email UNIQUE, password_hash, created_at)
files   (id, owner_id → users.id, name, size_bytes, stored_path, created_at)
shares  (id, file_id → files.id, code UNIQUE, expires_at, download_limit, downloads_count, password_hash NULL, created_at)
```

**Файлы:** `schema.sql`, `migrate-demo.js`.

```bash run
cat > schema.sql <<'EOF'
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE files (
  id SERIAL PRIMARY KEY,
  owner_id INTEGER NOT NULL REFERENCES users(id),
  name TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  stored_path TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE shares (
  id SERIAL PRIMARY KEY,
  file_id INTEGER NOT NULL REFERENCES files(id),
  code TEXT UNIQUE NOT NULL,
  expires_at TIMESTAMPTZ,
  download_limit INTEGER,
  downloads_count INTEGER NOT NULL DEFAULT 0,
  password_hash TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
EOF
cat > migrate-demo.js <<'EOF'
import { readFile } from 'node:fs/promises'
import { pool } from './src/db.js'

const sql = await readFile('schema.sql', 'utf8')
await pool.query(sql)
const { rows } = await pool.query(`
  select table_name from information_schema.tables
  where table_schema = 'public' order by table_name
`)
console.log(rows.map((r) => r.table_name))
await pool.end()
EOF
node migrate-demo.js
```

**Разбор.** `SERIAL PRIMARY KEY` — автоинкрементный целочисленный id. `REFERENCES users(id)` — **внешний ключ**: `files.owner_id` обязан указывать на существующую строку в `users`; вставить файл с несуществующим `owner_id` база не даст. `UNIQUE` на `email` и `code` — база сама не позволит дубликат.

### result
```out
(нет вывода: требует базу из 5.1; у тебя — ['files', 'shares', 'users'])
```

### why
Внешние ключи — это то, что не даёт базе «рассинхронизироваться»: без `REFERENCES` ничто не мешало бы создать файл с `owner_id = 9999`, которого не существует, и код узнал бы об этом только когда попытался бы показать владельца файла.

### deep Если не получилось
- **`relation "users" already exists`** — схема уже была создана в прошлый раз; это нормально при повторном запуске лабы, таблицы останутся с прошлыми данными (том переживает перезапуск, шаг 12.1). Чтобы начать с чистого листа — `docker compose down -v` (удалит и том).
- **`insert or update on table "files" violates foreign key constraint`** — попытка вставить `owner_id`, которого нет в `users`; сначала создай пользователя.

### quiz
- Что проверяет PostgreSQL перед тем, как разрешить вставку строки с внешним ключом?
- Почему `code` в `shares` помечен `UNIQUE`?
- Что будет с существующими таблицами при повторном запуске `docker compose up` без `-v`?

### links
- https://www.postgresql.org/docs/current/ddl-constraints.html | ограничения (constraints) в PostgreSQL | PostgreSQL: Constraints

## 12.4 Параметризованные запросы и SQL-инъекции | short: Параметры запроса | est: ~25 мин
### intro
**Слова шага:** *параметризованный запрос* — SQL с местом для значения вместо склейки строк; `$1` — место для первого параметра запроса; *SQL-инъекция* — атака, при которой чужой ввод меняет структуру SQL-запроса.

Склеивать SQL из строк с пользовательским вводом — опасно: это и есть **SQL-инъекция**. Покажем на демонстрационной (небезопасной!) функции и тут же — безопасный вариант:

**Файл:** `sql-injection-demo.js`.

```bash run
cat > sql-injection-demo.js <<'EOF'
import { pool } from './src/db.js'

await pool.query(`insert into users (email, password_hash) values ('victim@mail.com', 'x') on conflict do nothing`)

// НЕБЕЗОПАСНО — только чтобы увидеть проблему, так в ShareBox никогда не пишем
async function unsafeFindByEmail(email) {
  const sql = `select * from users where email = '${email}'`
  return pool.query(sql)
}

const evil = "x' OR '1'='1"
const rows = await unsafeFindByEmail(evil)
console.log('небезопасный запрос вернул строк:', rows.rowCount, '(должно быть 0 — это и есть инъекция)')

// БЕЗОПАСНО — параметризованный запрос
async function safeFindByEmail(email) {
  return pool.query('select * from users where email = $1', [email])
}

const safeRows = await safeFindByEmail(evil)
console.log('безопасный запрос вернул строк:', safeRows.rowCount)

await pool.end()
EOF
node sql-injection-demo.js
```

**Разбор.** `$1` — место для первого параметра из массива `[email]`; драйвер `pg` сам экранирует значение и отправляет его базе **отдельно** от текста запроса — специальные символы вроде `'` никак не меняют структуру SQL. В небезопасной версии строка `x' OR '1'='1` превращает `WHERE email = 'x' OR '1'='1'` в условие, истинное для **каждой** строки таблицы.

### result
```out
(нет вывода: требует базу из 5.1; у тебя — «небезопасный запрос вернул строк: N» где N — все пользователи, и «безопасный запрос вернул строк: 0»)
```

### why
Это не теоретическая угроза: именно так в реальных утечках данных читали целые таблицы пользователей или обходили проверку пароля (`' OR '1'='1' --`). В ShareBox каждый SQL-запрос с данными от клиента — только через `$1, $2, ...`, без исключений.

### deep Если не получилось
- **Небезопасный запрос вернул 0 строк, а не «все»** — PostgreSQL мог отклонить синтаксис из-за других кавычек в демонстрационной строке; суть демонстрации не меняется — склейка строк опасна в принципе, не только в этом конкретном примере.
- **`syntax error at or near` в небезопасном запросе** — тоже нормальный исход инъекции: сломанный SQL-синтаксис от постороннего ввода — другая сторона той же проблемы.

### quiz
- Что делает `$1` в SQL-запросе и чем он отличается от склейки строки через шаблонную строку JS?
- Почему `'1'='1'` в примере заставляет условие быть истинным для каждой строки?
- Где в коде ShareBox может появиться SQL-инъекция, если не следить за этим правилом?

### links
- https://node-postgres.com/features/queries#parameterized-query | параметризованные запросы в node-postgres | node-postgres: Parameterized query
- https://owasp.org/www-community/attacks/SQL_Injection | SQL-инъекция подробно | OWASP: SQL Injection

## 12.5 Транзакции | short: Транзакции | est: ~25 мин
### intro
**Слова шага:** *транзакция* — несколько запросов, которые выполняются как одно целое; `BEGIN`/`COMMIT`/`ROLLBACK` — начать, подтвердить, откатить транзакцию; *атомарность* — либо выполнились все запросы транзакции, либо ни один.

Создание share-ссылки (сессия 16) — это запись в `files` и следом в `shares`: если упадёт между ними, в базе останется файл без ссылки — неполные данные. **Транзакция** делает несколько запросов неделимыми: либо выполнятся все, либо (при ошибке) ни один.

**Файл:** `transaction-demo.js`.

```bash run
cat > transaction-demo.js <<'EOF'
import { pool } from './src/db.js'

async function createFileWithShare(ownerId, name, shouldFail) {
  const client = await pool.connect()
  try {
    await client.query('BEGIN')
    const file = await client.query(
      'insert into files (owner_id, name, size_bytes, stored_path) values ($1, $2, $3, $4) returning id',
      [ownerId, name, 1024, '/tmp/demo']
    )
    if (shouldFail) throw new Error('симулируем сбой между двумя вставками')
    await client.query(
      'insert into shares (file_id, code) values ($1, $2)',
      [file.rows[0].id, Math.random().toString(36).slice(2, 8)]
    )
    await client.query('COMMIT')
    console.log('успех: файл и ссылка созданы вместе')
  } catch (err) {
    await client.query('ROLLBACK')
    console.log('откат: ни файл, ни ссылка не сохранены —', err.message)
  } finally {
    client.release()
  }
}

const user = await pool.query(`select id from users limit 1`)
await createFileWithShare(user.rows[0].id, 'report.pdf', true)
const count = await pool.query('select count(*) from files')
console.log('файлов в базе после отката:', count.rows[0].count)

await pool.end()
EOF
node transaction-demo.js
```

**Разбор.** `pool.connect()` — на транзакцию берём **одно** соединение из пула вручную (а не `pool.query`, который каждый раз может взять любое) — иначе `BEGIN` и следующий запрос рискуют оказаться на разных соединениях. `client.release()` в `finally` — обязательно вернуть соединение в пул, даже если был `ROLLBACK`.

### result
```out
(нет вывода: требует базу из 5.1; у тебя — «откат: ...» и «файлов в базе после отката: 0» или столько, сколько было до теста)
```

### why
Без транзакции симулированный сбой оставил бы в базе файл без ссылки — одну из форм того, что называют «рассинхронизацией данных», которую потом долго ищут руками. С транзакцией та же ошибка откатывает обе вставки сразу.

### deep Если не получилось
- **`client.release()` не вызван, пул «кончился»** — следующие запросы зависают: пул ограничен по числу соединений, не освобождённые накапливаются. `finally` в примере — именно для того, чтобы `release()` сработал и при ошибке, и без неё.
- **Данные не откатились** — проверь, что `ROLLBACK` выполняется на **том же** `client`, что и `BEGIN`/вставки, а не через `pool.query` (новое, другое соединение).

### quiz
- Что произойдёт с первой вставкой (`files`), если вторая (`shares`) не выполнится и сделан `ROLLBACK`?
- Почему для транзакции берут одно соединение через `pool.connect()`, а не `pool.query()` на каждый шаг?
- Зачем `client.release()` стоит именно в блоке `finally`?

### links
- https://node-postgres.com/features/transactions | транзакции в node-postgres | node-postgres: Transactions

## 12.6 Переносим ShareBox на базу | short: ShareBox на базе | est: ~30 мин
### intro
**Слова шага:** *миграция (стартовая)* — создание таблиц при первом запуске приложения; *слой данных (repository)* — часть кода, которая читает и пишет в базу, скрывая SQL от остального приложения.

Соберём шаги 12.1–5.5 в постоянную часть ShareBox: при старте сервер сам применяет `schema.sql` (если таблиц ещё нет), а `files.service.js` из сессии 11 переходит с `Map` на настоящие запросы к базе.

**Файлы:** `src/migrate.js`, `src/services/files.service.js`, `src/controllers/files.controller.js`, `server.js`.

```bash run
cat > src/migrate.js <<'EOF'
import { readFile } from 'node:fs/promises'
import { pool } from './db.js'

export async function migrate() {
  const sql = await readFile(new URL('../schema.sql', import.meta.url), 'utf8')
  await pool.query(sql.replace(/CREATE TABLE/g, 'CREATE TABLE IF NOT EXISTS'))
}
EOF
cat > src/services/files.service.js <<'EOF'
import { pool } from '../db.js'
import { NotFoundError } from '../../lib/errors.js'

export async function getFileOrThrow(id) {
  const { rows } = await pool.query('select * from files where id = $1', [id])
  if (!rows[0]) throw new NotFoundError(`файл ${id} не найден`)
  return rows[0]
}

export async function createFile({ ownerId, name, sizeBytes, storedPath }) {
  const { rows } = await pool.query(
    'insert into files (owner_id, name, size_bytes, stored_path) values ($1, $2, $3, $4) returning *',
    [ownerId, name, sizeBytes, storedPath]
  )
  return rows[0]
}
EOF
cat > src/controllers/files.controller.js <<'EOF'
import { getFileOrThrow } from '../services/files.service.js'

export async function getFile(req, res) {
  res.json(await getFileOrThrow(req.params.id))
}
EOF
cat > server.js <<'EOF'
import express from 'express'
import healthRoutes from './src/routes/health.routes.js'
import filesRoutes from './src/routes/files.routes.js'
import { migrate } from './src/migrate.js'

await migrate()

const app = express()
app.use(express.json())
app.use(healthRoutes)
app.use(filesRoutes)

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
curl -s http://localhost:3000/health
echo
curl -s -o /dev/null -w 'несуществующий файл по id из базы: %{http_code}\n' http://localhost:3000/files/999999
kill $SERVER_PID
```

### result
```out auto
```

### why
`getFile` из сессии 5.1 поменял реализацию (`Map` → SQL, и имя на `getFileOrThrow`) и заодно стал **асинхронным** — SQL-запрос не может быть мгновенным, как чтение из `Map`. Из-за этого пришлось поправить и контроллер: `getFile` в сессии 11 был обычной функцией без `await`, а теперь обязан быть `async` и дождаться результата через `await`. Если забыть это сделать, `res.json(file)` отправит клиенту незавершённый `Promise` (пустой объект `{}`) с кодом `200` вместо ожидаемого `404` — ошибка, которую легко не заметить, потому что сервер не падает и не логирует исключение.

### deep Если не получилось
- **`relation "files" does not exist` при старте** — `migrate()` не вызван до создания роутов, или `schema.sql` не найден по относительному пути; сверь `new URL('../schema.sql', import.meta.url)` — путь считается от `src/migrate.js`.
- **Сервер стартует дольше обычного** — `await migrate()` перед `app.listen` — это ожидаемо, миграция выполняется один раз при каждом старте процесса (быстро благодаря `IF NOT EXISTS`).
- **Запрос к несуществующему файлу отвечает `200` с пустым телом `{}` вместо `404`** — контроллер не обновлён до `async`/`await` вслед за асинхронным сервисом (см. «Почему» выше); сверь, что `getFile` в `files.controller.js` — `async function` и использует `await`.

### quiz
- Почему `getFileOrThrow` обязан был стать `async`, хотя в сессии 11 та же функция была синхронной?
- Что отправит клиенту `res.json(file)`, если `file` — незавершённый `Promise`, а не дождавшееся `await` значение?
- Как по ответу `200` с пустым телом `{}` заподозрить именно забытый `await`, а не что-то другое?

### outro
:::tip Приёмка сессии 12
Ты можешь: поднять PostgreSQL в Docker Compose и объяснить роль тома; подключиться к базе из Node через пул `pg`; создать таблицы с первичными и внешними ключами; объяснить и предотвратить SQL-инъекцию через параметризованные запросы; обернуть несколько запросов в транзакцию с откатом при ошибке. ShareBox теперь хранит файлы в PostgreSQL вместо `Map` в памяти.
:::

### links
- https://node-postgres.com/ | полная документация node-postgres | node-postgres: Documentation
