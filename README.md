# Ruby Catalog Parser

Багатопоточний збір каталогу [ScrapeMe](https://scrapeme.live/shop/), завантаження
зображень, експорт у TXT, CSV, JSON, YAML, SQLite та MongoDB, створення ZIP
і фонова відправка через Sidekiq та Pony.

## Вимоги

Ruby 3.2+ (Windows: Ruby+DevKit), Bundler. Для додаткових функцій — MongoDB,
Redis 7+ і SMTP-акаунт.

## Встановлення

```powershell
git clone https://github.com/RoomToom/ruby-catalog-parser.git
cd ruby-catalog-parser
.\scripts\run.ps1 install
```

Альтернативно, з Ruby у PATH:

```sh
bundle config set --local path vendor/bundle
bundle install
```

## Запуск

На Windows двічі натисніть `run_lab.cmd` у папці проєкту. Після завершення
вікно залишається відкритим для перегляду результату. Залежності потрібно
встановити один раз за інструкцією вище.

Запуск із параметрами у PowerShell:

```powershell
.\run_lab.cmd --limit 5 --pages 1 --threads 2
```

Альтернативні команди: `.\scripts\run.ps1 run`, `bundle exec ruby main.rb`, `bundle exec rake run`.
Стандартний запуск: 20 товарів, 2 сторінки, 4 потоки, TXT/CSV/JSON/YAML, SQLite та ZIP.

Параметри:

- `--limit N`, `--pages N`, `--threads N` — обсяг збору та кількість потоків.
- `--mongodb` — додатковий запис у MongoDB.
- `--no-sqlite`, `--no-archive` — вимкнення SQLite або ZIP.
- `--send-archive` — відправка ZIP через чергу Sidekiq.
- `--show-config`, `--help` — конфігурація та довідка.

## Структура

```text
main.rb                   точка входу
lib/main.rb               параметри командного рядка
lib/tasks/                Rake-задачі
libs/                     класи MyApplicationTokarchuk
config/default_config.yaml
config/yaml_config/       конфігурація
config/sidekiq_boot.rb     завантаження worker
scripts/                  запуск і перевірки
test/                     автоматичні тести
examples/                 приклад результатів
```

## Налаштування

Файли в `config/yaml_config/`:

- `web_parser.yaml` — URL, CSS-селектори, пагінація, потоки, затримки та повторні спроби.
- `database_config.yaml` — файл SQLite та параметри MongoDB.
- `execution.yaml` — перемикачі дій: `1` увімкнено, `0` вимкнено.
- `logging.yaml` — каталог, рівень і файли журналів.
- `archive.yaml` — каталог ZIP, SMTP та Redis.

Змінні оточення: `MONGODB_URI`, `REDIS_URL`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`,
`SMTP_USER`, `SMTP_PASSWORD`, `SMTP_STARTTLS`, `ARCHIVE_EMAIL`.

## MongoDB

Запустити MongoDB, потім:

```powershell
$env:MONGODB_URI = 'mongodb://127.0.0.1:27017'
.\scripts\run.ps1 run --mongodb
```

База — `tokarchuk_catalog`, колекція — `products`. SQLite та MongoDB оновлюють
товари за `source_url`, не створюючи повторних записів.

## Відправка архіву

Запустити Redis. У двох терміналах задати однакові параметри SMTP і Redis:

```powershell
$env:REDIS_URL = 'redis://127.0.0.1:6379/0'
$env:SMTP_HOST = '<SMTP-сервер>'
$env:SMTP_PORT = '587'
$env:SMTP_FROM = '<адреса відправника>'
$env:SMTP_USER = '<SMTP-користувач>'
$env:SMTP_STARTTLS = 'true'
$env:ARCHIVE_EMAIL = '<адреса отримувача>'
# SMTP_PASSWORD задається локально перед запуском.
```

Перший термінал:

```powershell
.\scripts\run.ps1 worker
```

Другий термінал:

```powershell
.\scripts\run.ps1 run --send-archive
```

Worker та застосунок повинні бачити одну папку проєкту. Завдання надходить у Redis;
worker надсилає лист через Pony. Для помилок налаштовано три повторні спроби.

## Результати

- `output/data.txt`, `data.csv`, `data.json` — поточна колекція.
- `config/yaml_config/products/<категорія>/*.yaml` — окремі товари.
- `media/<категорія>/` — зображення.
- `db/local_database.sqlite` — SQLite, таблиця `products`.
- `output/mongodb_snapshot.json` — знімок MongoDB.
- `output/run.json` — статистика та помилки.
- `output/archives/` — ZIP-архіви.
- `logs/application.log`, `logs/error.log` — журнали.

БД зберігають накопичений набір товарів; файловий експорт — поточну колекцію.
ZIP містить її файли, зображення, SQLite та знімок MongoDB за наявності.
Приклад: `examples/catalog-20-products.zip`.

## Перевірки

```powershell
.\scripts\run.ps1 test
.\scripts\run.ps1 lint
```

Для тесту MongoDB задати `TEST_MONGODB_URI` з адресою запущеного тестового сервера.
Локальна перевірка фонової відправки потребує Redis і створеного ZIP:

```powershell
$env:TEST_REDIS_URL = 'redis://127.0.0.1:6379/15'
bundle exec ruby scripts/verify_background.rb
```

Коди завершення: `0` — успіх, `1` — помилка запуску, `2` — частковий збій збору.
