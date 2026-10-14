# Сессия 13 · Prisma 7
dur: ~4 ч

## 13.1 Зачем ORM, если есть pg | short: Зачем Prisma | est: ~20 мин
### intro
**Слова шага:** *ORM (Object-Relational Mapping)* — библиотека, представляющая таблицы как объекты и методы; *Prisma* — одна из самых популярных ORM для Node; *типобезопасность* — опечатки в полях/запросах ловятся до запуска, а не в рантайме.

Сессия 5 показала живой SQL через `pg` — он гибкий, но каждый запрос пишется строкой, опечатку в имени колонки находишь только в рантайме, а JOIN на три таблицы руками быстро разрастается. **ORM** — библиотека, которая превращает таблицы в объекты, а запросы — в вызовы методов. **Prisma** — одна из самых популярных в экосистеме Node: схема описывается отдельным файлом, а клиент для неё генерируется автоматически и знает все поля и типы.

```bash run
cd /work/sharebox
npm install prisma@7 --save-dev
npm install @prisma/client@7 @prisma/adapter-pg
npx prisma --version
```

### result
```out auto
```

### why
Ты не выбрасываешь то, что узнала про SQL в сессии 12 — Prisma **генерирует** SQL под капотом, и когда она делает что-то неожиданное, читать её логи получится только зная SQL. Эта лаба показывает оба пути (сначала руками, потом Prisma), потому что в реальной работе встречаются оба: где-то Prisma, где-то сырой SQL для сложного отчёта.

`@prisma/adapter-pg` — отдельный пакет, который понадобится в шаге 13.3: начиная с версии 7 Prisma всегда подключается к базе через явный **адаптер драйвера**, а не сама по себе — тот же `pg`, что ты уже ставила в сессии 12, просто Prisma теперь использует его напрямую вместо своего встроенного движка подключения.

### deep Как ещё можно
Другие ORM в экосистеме Node: `TypeORM`, `Sequelize`, `Drizzle` (ближе к сырому SQL, чем Prisma). Prisma выбрана для лабы, потому что у неё лучше всего автодополнение и генератор миграций «из коробки».

### deep Если не получилось
- **`npm error` при установке `@prisma/client`** — убедись, что сначала поставлена `prisma` (CLI, `--save-dev`), а `@prisma/client` и `@prisma/adapter-pg` — отдельные пакеты, все три нужны.
- **Долгая установка** — Prisma при установке скачивает бинарники движка под твою ОС; на медленном интернете это может занять минуту.

### quiz
- Чем ORM отличается от прямых SQL-запросов через `pg`?
- Зачем в лабе сначала был SQL руками, если потом всё равно ставится Prisma?
- Что из поставленного — CLI, а что — библиотеки для кода?

### links
- https://www.prisma.io/docs/orm/overview/introduction/what-is-prisma | что такое Prisma | Prisma Docs: What is Prisma

## 13.2 Схема, конфиг и генератор | short: Схема Prisma | est: ~35 мин
### intro
**Слова шага:** `schema.prisma` — файл, описывающий таблицы на языке Prisma; *модель (model)* — описание одной таблицы в схеме; `prisma7.config.ts` — конфиг CLI, где с версии 7 живёт строка подключения; *генератор (generator)* — что именно Prisma сгенерирует (клиент) и куда.

`npx prisma init` создаёт стартовые файлы: схему и отдельный конфиг-файл для самой Prisma (начиная с версии 7 строка подключения к базе для миграций живёт не в схеме, а в нём):

```bash run
npx prisma init --datasource-provider postgresql
cat prisma7.config.ts
```

Опишем те же три таблицы из сессии 12 — `User`, `File`, `Share` — на языке схемы Prisma. В генераторе укажем `prisma-client` (новый, без зависимости от Rust-движка) и свою папку вывода, а из `datasource` **уберём** `url` — он больше не читается отсюда:

**Файл:** `prisma/schema.prisma`.

```bash run
cat > prisma/schema.prisma <<'EOF'
generator client {
  provider = "prisma-client"
  output   = "../generated/prisma"
}

datasource db {
  provider = "postgresql"
}

model User {
  id           Int      @id @default(autoincrement())
  email        String   @unique
  passwordHash String   @map("password_hash")
  createdAt    DateTime @default(now()) @map("created_at")
  files        File[]

  @@map("users")
}

model File {
  id         Int      @id @default(autoincrement())
  ownerId    Int      @map("owner_id")
  owner      User     @relation(fields: [ownerId], references: [id])
  name       String
  sizeBytes  BigInt   @map("size_bytes")
  storedPath String   @map("stored_path")
  createdAt  DateTime @default(now()) @map("created_at")
  shares     Share[]

  @@map("files")
}

model Share {
  id              Int      @id @default(autoincrement())
  fileId          Int      @map("file_id")
  file            File     @relation(fields: [fileId], references: [id])
  code            String   @unique
  expiresAt       DateTime? @map("expires_at")
  downloadLimit   Int?      @map("download_limit")
  downloadsCount  Int       @default(0) @map("downloads_count")
  passwordHash    String?   @map("password_hash")
  createdAt       DateTime  @default(now()) @map("created_at")

  @@map("shares")
}
EOF
cat prisma/schema.prisma | head -8
```

**Разбор.** `prisma7.config.ts` (имя с цифрой — чтобы не конфликтовать с форматом следующей major-версии) создан автоматически: он читает `DATABASE_URL` из `.env` (шаг 12.2) и говорит Prisma CLI, где лежит схема и куда класть файлы миграций — то, что раньше писалось прямо в `schema.prisma`. `output = "../generated/prisma"` — генерируемый клиент теперь **не** кладётся в `node_modules` (как было в версиях до 7), а в обычную папку проекта, путь к которой ты видишь явно. `@map("owner_id")` — в коде поле называется `ownerId` (camelCase), а в таблице колонка — `owner_id` (snake_case) — Prisma сама переводит между ними.

### result
```out auto
```

### why
Разделение «подключение к базе — в конфиге CLI» и «структура данных — в схеме» — решение версии 7: `schema.prisma` стал чище (там нет секретов вроде пароля), а `prisma7.config.ts` — обычный `.ts`-файл, который можно расширять кодом (например, разными URL для теста и прода), а не только константами.

### deep Если не получилось
- **`Error validating datasource` или `the URL ... is no longer supported`** — в `datasource db {}` остался `url = env("DATABASE_URL")`; в Prisma 7 эта строка должна быть удалена из схемы целиком — подключение задаёт только `prisma7.config.ts`.
- **Опечатка в `@relation`** — Prisma при `generate`/`migrate` покажет точную строку схемы с ошибкой; это один из плюсов схемы отдельным файлом — ошибка ловится до похода в базу.

### quiz
- Где в Prisma 7 указывается строка подключения к базе — в схеме или в другом файле, и как он называется?
- Что означает `output = "../generated/prisma"` и чем это отличается от более старых версий Prisma?
- Что описывает `@relation(fields: [ownerId], references: [id])`?

### links
- https://www.prisma.io/docs/orm/prisma-schema/data-model/models | модели в схеме Prisma | Prisma Docs: Models
- https://www.prisma.io/docs/guides/upgrade-prisma-orm/v7 | что изменилось в Prisma 7 | Prisma Docs: Upgrade to v7

## 13.3 Клиент с адаптером: чтение и запись | short: Prisma Client | est: ~30 мин
### intro
**Слова шага:** `PrismaClient` — сгенерированный клиент для обращения к базе методами; *адаптер драйвера* — обёртка над `pg`, через которую Prisma 7 подключается к базе; `findUnique` — найти одну запись по уникальному полю; `create` — создать запись; `include` — подтянуть связанную запись (JOIN под капотом).

Сгенерируем клиент. С версии 7 его всегда создают **с адаптером** — самим Prisma Client больше не идёт встроенный движок подключения, он переиспользует тот же `pg`, что ты уже умеешь настраивать:

**Файлы:** `src/prisma.js`, `prisma-demo.js`.

```bash run
npx prisma generate
mkdir -p src
cat > src/prisma.js <<'EOF'
import 'dotenv/config'
import { PrismaPg } from '@prisma/adapter-pg'
import { PrismaClient } from '../generated/prisma/client.ts'

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL })
export const prisma = new PrismaClient({ adapter })
EOF
cat > prisma-demo.js <<'EOF'
import { prisma } from './src/prisma.js'

const user = await prisma.user.create({
  data: { email: `demo-${Date.now()}@mail.com`, passwordHash: 'x' },
})
console.log('создан пользователь:', user.id, user.email)

const file = await prisma.file.create({
  data: { ownerId: user.id, name: 'report.pdf', sizeBytes: 1024n, storedPath: '/tmp/demo' },
})
console.log('создан файл:', file.id, file.name)

const withOwner = await prisma.file.findUnique({
  where: { id: file.id },
  include: { owner: true },
})
console.log('файл с владельцем:', withOwner.name, '→', withOwner.owner.email)

await prisma.$disconnect()
EOF
node prisma-demo.js
```

**Разбор.** `import { PrismaClient } from '../generated/prisma/client.ts'` — импорт прямо из `.ts`-файла: Node 24 умеет выполнять такой код без сборки, если в нём нет настоящих TypeScript-конструкций (только типы, которые можно «стереть») — ровно так устроен сгенерированный клиент. `new PrismaPg({ connectionString })` — адаптер оборачивает обычную строку подключения (ту же, что в сессии 12.2) в объект, который Prisma Client использует вместо встроенного движка. `src/prisma.js` — единая точка создания клиента, как `src/db.js` с `pool` в сессии 12: весь остальной код импортирует готовый `prisma`, не создаёт свой.

### result
```out auto
```

### why
Сравни этот код с `files.service.js` из шага 12.6 — то же самое действие, но без единой строки SQL и с автодополнением полей в IDE. `include: { owner: true }` просит Prisma сразу подтянуть связанную запись (JOIN под капотом) — без этого `withOwner.owner` был бы `undefined`. `sizeBytes: 1024n` — `n` на конце означает `BigInt`, потому что в схеме поле `BigInt` (обычный JS `number` не гарантирует точность для очень больших файлов).

### deep Если не получилось
- **`Unknown arg 'include' in...`** — модель не содержит такой связи в схеме; сверь имя точно как в `schema.prisma` (`owner`, не `ownerId`).
- **Клиент не видит новое поле после правки схемы** — после **любой** правки `schema.prisma` нужен повторный `npx prisma generate`, иначе `generated/prisma/` остаётся старым.
- **`Cannot find module '../generated/prisma/client.ts'`** — `npx prisma generate` не выполнен, или путь в `src/prisma.js` не совпадает с `output` из схемы (оба указывают на один и тот же `../generated/prisma`, но считаются от разных файлов: `output` — от `prisma/schema.prisma`, импорт — от `src/prisma.js`).

### quiz
- Зачем Prisma Client с версии 7 требует явный адаптер драйвера?
- Что делает `include: { owner: true }` и что без него будет в `withOwner.owner`?
- Почему в проекте один файл `src/prisma.js` создаёт клиент, а остальные — только импортируют его?

### links
- https://www.prisma.io/docs/orm/prisma-client/queries/crud | CRUD-операции Prisma Client | Prisma Docs: CRUD
- https://www.prisma.io/docs/orm/overview/databases/postgresql | адаптер node-postgres | Prisma Docs: PostgreSQL

## 13.4 Сравнение: pg руками vs Prisma | short: pg vs Prisma | est: ~20 мин
### intro
**Слова шага:** *читаемость* — насколько легко понять, что делает запрос; *производительность* — насколько быстро он выполняется; *контроль над SQL* — видно ли и можно ли управлять точным текстом запроса.

Поставим рядом одну и ту же задачу — найти файл с владельцем — двумя способами из сессий 12 и 6, и сравним.

```text
pg руками (сессия 12):
  const { rows } = await pool.query(
    `select f.*, u.email as owner_email
     from files f join users u on u.id = f.owner_id
     where f.id = $1`,
    [id]
  )

Prisma (сессия 13):
  const file = await prisma.file.findUnique({
    where: { id },
    include: { owner: true },
  })
```

| | `pg` руками | Prisma |
|---|---|---|
| Опечатка в имени колонки | находится в рантайме, по ошибке базы | находится при `generate`/в IDE |
| Сложный отчёт с динамическими условиями | полный контроль над SQL | иногда приходится падать назад на `$queryRaw` |
| Скорость написания простого CRUD | дольше (писать SQL руками) | быстрее (готовые методы) |
| Что реально ушло в базу | видно сразу — это и есть запрос | нужно включать логирование Prisma, чтобы увидеть |

Включим лог запросов Prisma, чтобы увидеть, какой SQL она построила — для этого адаптер и клиент пересоздаём с опцией `log`:

**Файл:** `prisma-log-demo.js`.

```bash run
cat > prisma-log-demo.js <<'EOF'
import 'dotenv/config'
import { PrismaPg } from '@prisma/adapter-pg'
import { PrismaClient } from './generated/prisma/client.ts'

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL })
const prisma = new PrismaClient({ adapter, log: ['query'] })

const user = await prisma.user.findFirst()
if (user) {
  await prisma.file.findMany({ where: { ownerId: user.id }, include: { owner: true } })
}

await prisma.$disconnect()
EOF
node prisma-log-demo.js
```

### result
```out auto
```

### why
`log: ['query']` закрывает главный риск ORM — «магию», которую не видно: теперь видно ровно тот SQL, что уходит в базу, и можно сверить его с тем, что написала бы ты сама руками в сессии 12. В ShareBox простые операции (создать файл, найти по id) — через Prisma; сложную агрегацию для админ-панели (сессия 17) проще написать как сырой SQL через `prisma.$queryRaw`.

### deep Если не получилось
- **В логе нет запросов** — `log: ['query']` указывается при создании `new PrismaClient({...})`, а не отдельным вызовом после.
- **Таблица `users` пустая, `user` — `null`** — `findFirst()` вернул `null`, если до этого шага не создавался пользователь; запусти `prisma-demo.js` из 6.3 ещё раз.

### quiz
- В каком случае `pg` руками выигрывает у Prisma, судя по таблице сравнения?
- Что показывает `log: ['query']` и зачем это важно для доверия к ORM?
- Как выполнить сырой SQL-запрос, если готового метода Prisma для задачи нет?

### links
- https://www.prisma.io/docs/orm/prisma-client/queries/raw-database-access | $queryRaw и сырой SQL | Prisma Docs: Raw queries

## 13.5 Миграции при изменении схемы | short: Миграции | est: ~25 мин
### intro
**Слова шага:** `prisma migrate dev` — создать и применить миграцию по изменению схемы; *файл миграции* — пронумерованный SQL-файл с одним изменением структуры базы; *история миграций* — последовательность всех миграций проекта.

Добавим в `Share` поле `label` (пользователь сможет подписать ссылку) и посмотрим, как Prisma фиксирует изменение. Правка схемы — явным скриптом, а не хрупким `sed` (та же причина, что в сессии 17):

**Файл:** `add-label-field.js`.

```bash run
cat > add-label-field.js <<'EOF'
import { readFileSync, writeFileSync } from 'node:fs'
let schema = readFileSync('prisma/schema.prisma', 'utf8')
if (!schema.includes('label')) {
  schema = schema.replace(
    'downloadsCount  Int       @default(0) @map("downloads_count")',
    'downloadsCount  Int       @default(0) @map("downloads_count")\n  label           String?'
  )
  writeFileSync('prisma/schema.prisma', schema)
}
console.log('готово')
EOF
node add-label-field.js
npx prisma migrate dev --name add_share_label
```

У тебя, скорее всего, вместо списка миграций — сообщение **«Drift detected»**: таблицы в базе уже существуют (сессия 12 создала их сырым SQL через `schema.sql`), а история миграций Prisma — пустая, и она не знает, что эти таблицы «её». Для учебной базы (данные не жалко) это решается пересозданием:

```bash run
npx prisma migrate reset --force
ls prisma/migrations
```

### result
```out auto
```

### why
Каждое изменение схемы превращается в отдельный пронумерованный SQL-файл в `prisma/migrations/` — это **история**: на новой машине (или у другого разработчика) `npx prisma migrate deploy` применит все миграции по порядку и получит ровно такую же структуру базы. Без миграций «передать структуру базы» означало бы «перечислить голосом, что поменялось». Расхождение в этом шаге — не баг методички, а естественное следствие того, что сессия 12 нарочно шла путём сырого SQL: в реальном проекте, начатом сразу с Prisma, миграция прошла бы с первого раза без `reset`.

### deep Если не получилось
- **`Drift detected` не проходит даже после `reset --force`** — убедись, что переменная `DATABASE_URL` в `.env` (шаг 12.2) указывает на ту же базу, где сессия 12 создавала таблицы; `prisma migrate reset` очищает именно её.
- **Пустая папка `migrations` после команды** — проверь код выхода команды (`echo $?`) и сообщение об ошибке выше; частая причина — недоступна база (сверь шаг 12.1) или `prisma7.config.ts` не находит `DATABASE_URL`.
- **`--force` в реальном проекте** — удаляет все данные без подтверждения; годится для учебной базы или dev-окружения, никогда — для базы с настоящими данными.

### quiz
- Что произойдёт, если выполнить `prisma migrate deploy` на новой пустой базе, имея папку `migrations` с историей?
- Почему в этой лабе возникает «Drift detected», хотя в типичном проекте, начатом сразу с Prisma, его бы не было?
- Где хранится история изменений структуры базы в Prisma-подходе?

### links
- https://www.prisma.io/docs/orm/prisma-migrate/getting-started | миграции Prisma | Prisma Docs: Migrate

## 13.6 Переводим ShareBox на Prisma | short: ShareBox на Prisma | est: ~30 мин
### intro
**Слова шага:** *замена слоя данных* — переход с одного способа хранения (`pg`) на другой (Prisma); *совместимость интерфейса сервиса* — сервис отдаёт те же данные тем же способом, не ломая вызывающий код.

Как и в шаге 12.6 (переход с `Map` на `pg`), меняем **только** `files.service.js` — контроллер и роут не трогаем, оба уже `async`/`await` (шаг 12.6):

**Файл:** `src/services/files.service.js`.

```bash run
cat > src/services/files.service.js <<'EOF'
import { prisma } from '../prisma.js'
import { NotFoundError } from '../../lib/errors.js'

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
EOF
node server.js &
SERVER_PID=$!
sleep 1
curl -s -o /dev/null -w 'через Prisma, нет такого файла: %{http_code}\n' http://localhost:3000/files/999999
kill $SERVER_PID
```

### result
```out auto
```

### why
Контроллер (`files.controller.js`, шаг 12.6) не изменился ни на строку — он уже был `async`/`await` и вызывает `getFileOrThrow(id)`, и ему всё равно, `pg` или Prisma за этим стоит. Это и есть обещание слоёв из сессии 5.1: смена способа хранения данных — локальное изменение одного файла, а не рефакторинг всего приложения. `src/prisma.js` из шага 13.3 — тот же приём, что `src/db.js` для `pool`: один файл создаёт клиент, остальные — импортируют.

### deep Если не получилось
- **`PrismaClientValidationError` при поиске по `id`** — `req.params.id` — строка (сессия 9.2), а поле `id` в схеме — `Int`; `Number(id)` в примере — обязательное приведение типа, как и с `req.query.page` в шаге 9.2.
- **`Cannot find module '../prisma.js'`** — путь считается от `src/services/files.service.js`; `src/prisma.js` — на уровень выше, поэтому `../prisma.js`, а не `./prisma.js`.

### quiz
- Почему `files.controller.js` не пришлось менять ни строчкой при переходе с `pg` на Prisma?
- Что делает `Number(id)` перед `prisma.file.findUnique` и почему без него будет ошибка валидации?
- Зачем `src/prisma.js` создаёт клиент в одном месте, а не в каждом файле отдельно?

### outro
:::tip Приёмка сессии 13
Ты можешь: описать модели в `schema.prisma` со связями; объяснить, где в Prisma 7 хранится строка подключения и зачем нужен адаптер драйвера; сгенерировать и применить миграцию; читать и писать через `PrismaClient`, включая `include` для связанных записей; увидеть реальный SQL под капотом через `log: ['query']`; сказать, когда Prisma удобнее `pg`, а когда наоборот. `files.service.js` ShareBox теперь работает через Prisma.
:::

### links
- https://www.prisma.io/docs/orm | полная документация Prisma ORM | Prisma Docs: ORM
