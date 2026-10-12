# Сессия 1 · Node с нуля
dur: ~4 ч

## 1.1 Что такое Node.js и V8 | short: Что такое Node | est: ~20 мин
### intro
**Слова шага:** *Node.js* — среда выполнения JS вне браузера; *V8* — движок, который превращает JS в машинный код; *движок JavaScript* — программа, которая исполняет код; *addon* (fs/net/http) — модули Node для файлов, сети, процессов; *однопоточность* — весь код Node выполняется в одном потоке.

До 2009 года JavaScript работал только в браузере: страница — и ничего больше. **V8** — движок, который Google написал для Chrome: он берёт текст JS-кода и превращает в машинные инструкции (JIT-компиляция), заметно быстрее старых интерпретаторов. **Node.js** взял V8 и пристроил к нему то, чего у движка внутри браузера нет и не должно быть: доступ к файлам (`fs`), к сети (`net`, `http`), к процессам операционной системы. Получился JavaScript, который умеет быть сервером, а не только скриптом на странице.

Аналогия: V8 — двигатель. Браузер ставит этот двигатель в кузов «для города» (DOM, окна, куки). Node ставит тот же двигатель в кузов «для дороги» — с доступом к файлам и сети, но без руля и педалей браузера (в Node нет `document`, нет `window`).

Проверим, что Node установлен и какая версия (лаба написана и проверена на Node 24):

```bash run
node --version
npm --version
```

### result
```out auto
```

### why
Все следующие сессии — надстройки над одним и тем же: Express добавляет роутинг поверх `http`, Prisma — удобный доступ к той же файловой/сетевой подсистеме для базы. Если не понимать, что Node = V8 + свои модули, непонятно, почему код из браузерной консоли не всегда работает в Node и наоборот.

### deep Как ещё можно
Кроме Node есть **Deno** и **Bun** — тоже V8 (Deno) или собственный движок (Bun), с другими умолчаниями (Deno — безопасность по умолчанию, Bun — скорость старта). Эта лаба — про Node, потому что он стоит почти везде на серверах и под ним работает NestJS.

### deep Если не получилось
- **`node: command not found`** — Node не установлен. Поставь: `brew install node@24` (Mac) или скачай установщик с [nodejs.org](https://nodejs.org/).
- **Версия меньше 24** — через `nvm install 24 && nvm use 24`, если нужно несколько версий Node одновременно; без nvm — переустановить через brew.

### quiz
- Что добавляет Node к движку V8, чего нет в браузере?
- Почему в браузерной консоли работает `document.querySelector`, а в Node — нет?
- На чём написан Node и зачем ему вообще нужен V8?

### links
- https://nodejs.org/en/learn/getting-started/introduction-to-nodejs | что такое Node.js, из официального Learn | Node.js: Introduction to Node.js

## 1.2 Первый файл и REPL | short: REPL и файл | est: ~20 мин
### intro
**Слова шага:** *REPL* — интерактивная консоль (ввела строку — увидела результат); *скрипт* — файл, который Node выполняет целиком; `console.log` — напечатать в терминал; *интерпретатор* — программа, которая читает и сразу выполняет код.

Node — *интерпретатор*: программа, которая читает JS-код и сразу выполняет, без отдельной компиляции в файл. Два способа его использовать.

Первый — **REPL** (Read-Eval-Print Loop: читает строку → выполняет → печатает результат → ждёт следующую). Запусти на своём Mac:

```bash
node
```

```text
> 2 + 2
4
> console.log('привет')
привет
undefined
> .exit
```

(`undefined` печатается отдельно от «привет»: это то, что *вернул* `console.log` — он возвращает `undefined`, а печатает в консоль как побочный эффект. Выйти — `.exit` или [[Ctrl]]+[[D]].)

Второй способ — то, как лаба работает дальше: **файл**, который Node выполняет целиком. Дальше все команды — в контейнере лабы с Node 24 (как в Bash Lab: одинаковая версия у всех; по паспорту лабы можно и прямо на Mac).

**Файл:** `hello.js`.

```bash run
mkdir -p /work/sharebox
cd /work/sharebox
cat > hello.js <<'EOF'
console.log('ShareBox стартует')
console.log('Node:', process.version)
EOF
node hello.js
```

### result
```out auto
```

### why
REPL — быстрый черновик для проверки одной строки. Но программа — это файл: Node читает его сверху вниз, выполняет и завершается (в отличие от браузерной страницы, которая «живёт», пока открыта). Весь ShareBox — такие файлы.

### deep Как ещё можно
`node -e "код"` выполняет код из аргумента командной строки без файла — удобно для одной проверки, без REPL и без файла.

### deep Если не получилось
- **REPL не реагирует на Enter** — ты внутри многострочной конструкции (Node ждёт закрывающую скобку); закрой её `)` или `}`, либо `.exit`.
- **`SyntaxError` в `hello.js`** — сверь кавычки: heredoc `<<'EOF'` (в одинарных кавычках) не раскрывает `$переменные`, это ровно то, что нужно для JS-кода.

### quiz
- Чем REPL отличается от запуска файла?
- Что возвращает `console.log` и что он делает «по пути»?
- Когда программа на Node завершается сама, без `exit`?

### links
- https://nodejs.org/api/repl.html | справочник по REPL | Node.js: REPL

## 1.3 Модули: CommonJS | short: CommonJS | est: ~25 мин
### intro
**Слова шага:** *модуль* — отдельный файл с кодом, который можно подключить; *CommonJS* — исходная система модулей Node; `require` — подключить чужой модуль; `module.exports` — что файл отдаёт наружу; *кеш модулей* — повторный `require` того же пути не выполняет файл заново.

Один файл — уже тесно: код надо делить на части. **CommonJS** — исходная система модулей Node (ещё до того, как модули появились в самом JavaScript): каждый файл — отдельный модуль, он отдаёт наружу то, что положит в `module.exports`, а получает чужой код через `require(путь)`.

Сделаем отдельную папку для примера — не часть ShareBox, просто чтобы увидеть механизм:

**Файлы:** `cjs-demo/package.json`, `cjs-demo/greet.js`, `cjs-demo/demo.js`.

```bash run
mkdir -p cjs-demo
cat > cjs-demo/package.json <<'EOF'
{ "type": "commonjs" }
EOF
cat > cjs-demo/greet.js <<'EOF'
function greet(name) {
  return `Привет, ${name}!`
}
module.exports = { greet }
EOF
cat > cjs-demo/demo.js <<'EOF'
const { greet } = require('./greet')
const again = require('./greet')
console.log(greet('CommonJS'))
console.log('тот же объект:', require('./greet') === again)
EOF
node cjs-demo/demo.js
```

**Разбор.** `require('./greet')` — путь относительный, с `./`, расширение `.js` можно не писать (CommonJS сам допишет). `module.exports = {...}` — то, что отдаём наружу; можно отдать и одну функцию (`module.exports = greet`), без объекта. `require` **кеширует** модуль по полному пути: второй `require('./greet')` не выполняет файл снова, а возвращает тот же уже готовый объект — поэтому `===` в примере даёт `true`.

### result
```out auto
```

### why
CommonJS — то, что ты увидишь в большинстве старого кода на Node и во многих npm-пакетах до сих пор (поле `"main"` в их `package.json`). Кеш модулей объясняет, почему, например, переменная-счётчик внутри модуля «помнит» значение между разными `require` в одной программе — модуль выполняется один раз.

### deep Под капотом
`require` — не часть языка JavaScript, а функция, которую Node подставляет в каждый CommonJS-файл вместе с `module`, `exports`, `__filename`, `__dirname`. Поэтому в браузере `require` сам по себе не существует — это особенность Node.

### deep Если не получилось
- **`Cannot find module './greet'`** — опечатка в пути или забыли `./` (без него Node ищет пакет в `node_modules`, а не файл рядом).
- **Перепутаны варианты экспорта** — `module.exports = greet` (вся функция), `exports.greet = greet` (свойство существующего объекта), `module.exports = { greet }` (новый объект с одним свойством) — три разных результата.

### quiz
- Что делает `require` при повторном вызове с тем же путём?
- Чем `module.exports = greet` отличается от `module.exports = { greet }`?
- Почему `require` не работает в коде браузера?

### links
- https://nodejs.org/api/modules.html | справочник по модулям CommonJS | Node.js: Modules (CommonJS)

## 1.4 Модули: ES Modules | short: import/export | est: ~25 мин
### intro
**Слова шага:** *ES Modules (ESM)* — модули самого языка JS, те же в браузере; `import`/`export` — синтаксис подключения и экспорта; *поле `type` в package.json* — говорит Node, как читать `.js`-файлы (ESM или CommonJS).

CommonJS придумал сам Node; **ES Modules** — модули, которые придумал сам язык JavaScript (стандарт ES2015), и ими же пользуется браузер (`<script type="module">`). У них другой синтаксис — `import`/`export` — и важное отличие: Node должен заранее знать, какую систему модулей использовать в файле, потому что `import` и `require` не смешиваются в одном файле.

Решает это поле `"type"` в `package.json`: `"type": "module"` — все `.js` в этой папке и ниже (если нет своего `package.json`) читаются как ESM; без этого поля (или `"type": "commonjs"`) — как CommonJS. ShareBox по паспорту лабы написан на чистом ESM — поставим это прямо сейчас, в корне проекта, и дальше весь ShareBox будет на `import`/`export`:

**Файлы:** `package.json`, `lib/greet.js`, `greet-demo.js`.

```bash run
cat > package.json <<'EOF'
{
  "name": "sharebox",
  "private": true,
  "type": "module"
}
EOF
mkdir -p lib
cat > lib/greet.js <<'EOF'
export function greet(name) {
  return `Привет, ${name}!`
}
export const APP_NAME = 'ShareBox'
EOF
cat > greet-demo.js <<'EOF'
import { greet, APP_NAME } from './lib/greet.js'
console.log(greet(APP_NAME))
EOF
node greet-demo.js
```

**Разбор.** `export function` / `export const` — несколько именованных экспортов из одного файла (в CommonJS наружу обычно уходит один объект). `import { ... } from './lib/greet.js'` — **расширение `.js` обязательно** в ESM (в CommonJS было необязательно) — частая ошибка при переходе, разберём её в следующем шаге.

### result
```out auto
```

### why
Паспорт лабы задаёт ESM для всего ShareBox: это современный стандарт, он же в браузере и во Vue/Nuxt-лабах, а NestJS и TypeScript дальше проще настраиваются под ESM. Файлы из шага 1.3 (`cjs-demo/`) остаются CommonJS благодаря своему собственному `package.json` — поле `type` действует на подпапку вплоть до следующего `package.json` внутри.

### deep Как ещё можно
Можно держать смешанный проект без единого `type` в корне: тогда ESM-файлам нужно расширение `.mjs`, а CommonJS — `.cjs`, и расширение решает за Node, не дожидаясь `package.json`. В этой лабе выбран один `type: module` на весь проект — проще держать в голове одно правило.

### deep Если не получилось
- **`Cannot use import statement outside a module`** — в этом файле Node считает, что это CommonJS (нет `"type": "module"` в ближайшем `package.json` вверх по дереву, или расширение `.cjs`).
- **`ERR_MODULE_NOT_FOUND`** — забыли расширение `.js` в пути импорта; в ESM Node, в отличие от CommonJS, его не дописывает сам.

### quiz
- Что решает, читать ли `.js`-файл как CommonJS или как ESM?
- Почему в `import './lib/greet.js'` обязательно писать `.js`, а в `require('./lib/greet')` — нет?
- Что произойдёт с файлами в `cjs-demo/`, если в корне проекта стоит `"type": "module"`?

### links
- https://nodejs.org/api/esm.html | справочник по ES-модулям | Node.js: ECMAScript modules
- https://nodejs.org/api/packages.html | поле type и package.json | Node.js: Modules: Packages

## 1.5 process, npm-скрипты | short: process и npm | est: ~20 мин
### intro
**Слова шага:** `process` — объект со сведениями о запущенной программе; `process.argv` — аргументы командной строки; `process.env` — переменные окружения; *npm-скрипт* — короткое имя для команды в `package.json`; `npm run` — запустить такой скрипт.

`process` — объект, который Node вставляет в каждую программу сам: через него видны аргументы командной строки, переменные окружения, можно завершить программу кодом выхода. Два самых нужных свойства:

**Файл:** `args-demo.js`.

```bash run
cat > args-demo.js <<'EOF'
console.log('argv:', process.argv.slice(2))
console.log('PORT из окружения:', process.env.PORT || '(не задан)')
EOF
node args-demo.js foo bar
PORT=4000 node args-demo.js
```

**Разбор.** `process.argv` — массив: [0] путь к Node, [1] путь к файлу, дальше — твои аргументы; `.slice(2)` отрезает первые два системных. `process.env` — объект со всеми переменными окружения; `PORT=4000 node args-demo.js` задаёт переменную только для этого запуска (как в Bash Lab — переменная перед командой).

Запускать `node args-demo.js` каждый раз длинно. **npm-скрипты** в `package.json` дают короткие имена:

**Файл:** `package.json`.

```bash run
cat > package.json <<'EOF'
{
  "name": "sharebox",
  "private": true,
  "type": "module",
  "scripts": {
    "hello": "node hello.js",
    "args": "node args-demo.js из-npm"
  }
}
EOF
npm run hello
npm run args
```

### result
```out auto
```

### why
`process.env` — то, как ShareBox дальше (сессия 4) получит, например, строку подключения к базе: не прямо в коде, а из окружения, чтобы пароль не лежал в git. `npm run` — стандарт для старта, тестов и сборки в любом Node-проекте; `start` и `test` можно вызывать даже без `run` (`npm start`, `npm test`) — это два зарезервированных имени.

### deep Как ещё можно
Файл `.env` (переменные построчно `ИМЯ=значение`) и пакет вроде `dotenv` читают его в `process.env` при старте — появится в сессии 4, когда переменных станет много.

### deep Если не получилось
- **`npm error Missing script`** — имя скрипта не совпадает с ключом в `"scripts"`; сверь `cat package.json`.
- **`PORT` «не виден» в следующей команде** — переменная перед командой действует только на эту одну команду; если нужно на несколько, `export PORT=4000` (как в Bash Lab).

### quiz
- Что лежит в `process.argv[0]` и `process.argv[1]`?
- Зачем переменные окружения, а не просто значения в коде?
- Чем `npm run hello` отличается от `npm start`?

### links
- https://nodejs.org/api/process.html | справочник по process | Node.js: process
- https://docs.npmjs.com/cli/v10/using-npm/scripts | документация по npm-скриптам | npm Docs: scripts

## 1.6 🔨 Сломать → починить: забытое расширение, и первый сервер | short: Сломать → починить | est: ~30 мин
### intro
:::trap Сломать → починить
Самая частая ошибка новичка в ESM — забытое расширение `.js` в импорте. Воспроизведи её и почини. Затем — первый сервер ShareBox без фреймворка.
:::

Добавим второй модуль и импортируем его без расширения:

**Файлы:** `lib/id.js`, `broken.js`.

```bash run
cat > lib/id.js <<'EOF'
export function makeId() {
  return Math.random().toString(36).slice(2, 8)
}
EOF
cat > broken.js <<'EOF'
import { makeId } from './lib/id'
console.log('id:', makeId())
EOF
node broken.js
```

**Почини** — перепиши импорт с расширением и запусти снова:

**Файл:** `broken.js`.

```bash run
cat > broken.js <<'EOF'
import { makeId } from './lib/id.js'
console.log('id:', makeId())
EOF
node broken.js
```

Теперь — первый сервер, без Express, прямо встроенным модулем `node:http`. Он пока отвечает на всё одним и тем же обработчиком — роутинг появится в сессии 3:

**Файл:** `server.js`.

```bash run
cat > server.js <<'EOF'
import { createServer } from 'node:http'

const server = createServer((req, res) => {
  console.log(`${req.method} ${req.url}`)
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ status: 'ok', uptime: process.uptime() }))
    return
  }
  res.writeHead(404, { 'Content-Type': 'text/plain' })
  res.end('Not Found')
})

const PORT = process.env.PORT || 3000
server.listen(PORT, () => console.log(`ShareBox слушает порт ${PORT}`))
EOF
```

```bash run
node server.js &
SERVER_PID=$!
sleep 1
curl -s http://localhost:3000/health
echo
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/whatever
kill $SERVER_PID
```

### result
```out auto
```

### why
Ошибка `ERR_MODULE_NOT_FOUND` без расширения — то, что ждёт тебя при любом рефакторинге на ESM, пока не стало привычкой. А `createServer` показывает, *что именно* скрывает Express: функция-обработчик, которая получает `req`/`res` и сама решает, что ответить, — весь роутинг ты сейчас написал руками через `if`. В сессии 3 Express возьмёт это на себя.

### deep Как ещё можно
`server.listen(PORT, HOST, callback)` — можно указать и адрес (`'0.0.0.0'` — слушать на всех интерфейсах, понадобится в Docker в сессии 11). Без адреса слушает только `localhost`.

### deep Если не получилось
- **`EADDRINUSE`** — порт 3000 уже занят (прошлый `server.js` не остановлен). Останови его: найди процесс (`ps aux | grep server.js` на Mac) и `kill <pid>`.
- **`curl: (7) Failed to connect`** — сервер не успел подняться до `curl`; `sleep 1` в примере — для этого. На своей машине запускай сервер в одном окне терминала, `curl` — в другом, `sleep` не нужен.

### quiz
- Что означает `ERR_MODULE_NOT_FOUND` и когда он возникает в ESM, но не в CommonJS?
- Что делает `createServer`, и что ты сам написал внутри обработчика, чтобы отличить `/health` от любого другого адреса?
- Зачем нужен `process.env.PORT || 3000`, а не просто `3000`?

### outro
:::tip Приёмка сессии 1
Ты можешь: объяснить, что Node добавляет к V8; запустить файл и REPL; написать и подключить модуль в CommonJS (`require`/`module.exports`) и в ES Modules (`import`/`export`), и сказать, чем они отличаются; прочитать аргументы и переменные окружения через `process`; запустить npm-скрипт; поднять сервер на `node:http` и получить от него ответ. В `/work/sharebox` лежит каркас проекта: `package.json` (ESM), `lib/greet.js`, `lib/id.js`, `server.js`.
:::

### links
- https://nodejs.org/api/http.html | справочник по node:http | Node.js: HTTP
