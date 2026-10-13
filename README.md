# Node.js + Express Lab

![Express Lab](https://raw.githubusercontent.com/meeymirita/works-lab/main/images/express.png)

Введение в Node.js и Express перед `typescript-lab` и `nestjs-lab`: что такое Node, event loop, модули, streams, роутинг, middleware, ошибки, база, JWT, тесты, Docker — и в конце таблица «что из этого скрывает NestJS». Сквозной проект — **ShareBox**: файлообменник со ссылками (до 200 МБ).

**Статус: ✅ методичка написана и вычитана (11 сессий, 66 шагов + справочные страницы); вычитка 12.10 — ассистентом (13 находок, все исправлены), весь вывод проверен настоящим прогоном в Docker (Node 24, PostgreSQL 18 для сессий 5–11); владелец лабу ещё не проходила.**
**Сложность: лёгкая–средняя.**

## Что внутри

- **11 сессий, 66 шагов, ~44 часа.** Node и V8, модули, event loop, streams → Express 5: роутер, middleware, тело запроса → ошибки, zod, слои routes/controllers/services, `.env` → PostgreSQL: `pg`, SQL, транзакции → Prisma 7: схема, миграции, клиент → JWT-аутентификация, ротация refresh, владение ресурсом → файлы: `multer`, лимиты, path traversal, Range → share-ссылки, HTML-страница скачивания, скачивание из консоли → админка, rate limit, helmet/cors/pino, graceful shutdown → тесты (`node:test`, supertest), Docker, финал.
- В нескольких сессиях — шаг «🔨 Сломать → починить», в сессии 11 — «Production Hell» без подсказок.
- Справка: шпаргалка, справочник ошибок (симптом → причина → что делать), глоссарий (35 терминов), 38 вопросов на собеседование, «что дальше».
- Режим: самостоятельная лаба. Node нужен на Mac с сессии 1; PostgreSQL в Docker — с сессии 5, только с согласия.

## Файлы

| Файл | Что |
|---|---|
| `express.html` | методичка (HTML-«бандл»; не править руками — собирается из `src/`) |
| `src/*.md` | исходники: `00-meta.md`, `01…11-session.md`, `ref-*.md`, `gloss.md` |
| `src/outputs.json` | настоящие выводы команд из Docker (подставляются в «Ожидаемый результат») |
| `Dockerfile` | образ лабы: `node:24-alpine` + bash, curl |
| `express_lab_plan.md` | план и ТЗ лабы (паспорт, сессии, API, критерии приёмки) |

## Как пересобрать методичку

Из корня сборного репозитория `anitech-performance`:

```bash
python3 tools/build-manual.py express --run   # выполнить блоки ```bash run в Docker и собрать
python3 tools/build-manual.py express         # собрать из сохранённых выводов (Docker не нужен)
python3 tools/build-manual.py express --check # только проверка структуры
```

Для сессий 5–11 одного `--run` недостаточно — нужен реальный PostgreSQL 18, доступный внутри check-контейнера как `localhost:5432` (подробности — `fixes/backend/express.md`, раздел «🧪 Инфраструктура проверки»).

## Лицензия и авторство

Код — MIT, тексты — CC BY 4.0, обложки не покрыты (см. [LICENSE](LICENSE)). Кто что сделал: [NOTICE](NOTICE).

---

Часть сборного репозитория лабораторных работ — [anitech-performance](https://github.com/meeymirita/anitech-performance).
