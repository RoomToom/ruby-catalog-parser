# Ruby Catalog Parser

Ruby-додаток для багатопоточного збору каталогу [ScrapeMe](https://scrapeme.live/shop/),
збереження даних у SQLite та MongoDB і надсилання результатів електронною поштою.
Простір імен — `MyApplicationTokarchuk`.

## Функціонал

- Обхід сторінок каталогу й карток товарів через Mechanize з урахуванням robots.txt.
- Паралельна обробка через Thread і Queue; синхронізація колекції через Mutex.
- Збір назви, ціни, валюти, опису, категорій, SKU, URL та зображення товару.
- Обмеження частоти запитів, повторні спроби й журналювання помилок.
- Експорт у TXT, CSV, JSON та окремий YAML для кожного товару; локальні зображення.
- Запис у SQLite та MongoDB з оновленням за `source_url` без дублювання товарів.
- ZIP із результатами, зображеннями, SQLite та знімком MongoDB.
- Фонова відправка ZIP через Redis, Sidekiq і Pony з автентифікацією SMTP.
- Локальне шифрування SMTP-пароля засобами Windows.

## Встановлення на Windows

1. Встановити Ruby 3.2+ з DevKit і Bundler. Ruby має бути у PATH;
   також підтримується локальний шлях `D:\Ruby\Ruby40-x64\bin`.
2. Встановити MongoDB Community Server зі службою `MongoDB` і запустити її.
   MongoDB Compass можна встановити для перегляду даних.
3. Клонувати репозиторій або розпакувати архів, відкрити PowerShell у папці проєкту:

```powershell
git clone https://github.com/RoomToom/ruby-catalog-parser.git
cd ruby-catalog-parser
.\scripts\run.ps1 install
```

Команда встановлює Ruby-залежності та завантажує portable Redis 7.4.9
із проєкту [redis-windows](https://github.com/redis-windows/redis-windows),
перевіряючи SHA256. Redis зберігається у `tmp/tools`; системна служба не створюється.

4. Запустити `setup_smtp.cmd`, ввести адресу Gmail і пароль застосунку без пробілів.
   У Google потрібна двоетапна перевірка й доступність паролів застосунків.
   Отримувач за замовчуванням — `tokarchuk.roman@chnu.edu.ua`.
   Для іншого отримувача:

```powershell
.\setup_smtp.cmd -Recipient recipient@example.com
```

Перевірка налаштування має завершитися повідомленням `SMTP authentication successful`.
Пароль зберігається в `.smtp.local.xml`, зашифрований для поточного користувача
Windows на цьому ПК. Файл не входить у Git і архів коду. Після перенесення
проєкту на інший ПК налаштування SMTP потрібно виконати повторно.

## Запуск

**Двічі натиснути `run_lab.cmd`.**

Запуск автоматично піднімає окремий Redis на вільному локальному порту та worker
Sidekiq, збирає каталог, записує дані в SQLite і MongoDB, створює ZIP і надсилає
його на налаштовану пошту. Після підтвердження SMTP допоміжні процеси завершуються.
Служба MongoDB продовжує працювати. Вікно залишається відкритим для перегляду результату.
Кожний повний запуск надсилає новий лист.

Стандартні параметри: 20 товарів, 2 сторінки, 4 потоки. Зміна параметрів:

```powershell
.\run_lab.cmd --limit 5 --pages 1 --threads 2
```

Успішна відправка позначається `SMTP accepted the archive for ...`.
Це підтвердження прийняття листа SMTP-сервером; папку «Спам» потрібно перевіряти окремо.
Очікування відправки обмежене 120 секундами. Якщо підтвердження немає,
програма завершується з помилкою; готовий ZIP залишається на диску.
Тимчасова черга повного запуску не зберігається після його завершення.

## Перегляд MongoDB

У Compass підключитися до `mongodb://127.0.0.1:27017` і відкрити
`tokarchuk_catalog` → `products`.

Адресу іншого сервера задають через `MONGODB_URI` або
`config/yaml_config/database_config.yaml`. SQLite та MongoDB накопичують
товари з оновленням за URL; файлові експорти містять поточну колекцію.

## Результати

- `output/data.txt`, `output/data.csv`, `output/data.json` — поточна колекція.
- `config/yaml_config/products/<категорія>/*.yaml` — окремі товари.
- `media/<категорія>/` — зображення.
- `db/local_database.sqlite` — таблиця `products`.
- `output/mongodb_snapshot.json` — знімок колекції MongoDB.
- `output/run.json` — статистика збору.
- `output/archives/*.zip` — архіви результатів.
- `output/archives/*.sent.json` — підтвердження SMTP для відповідного архіву.
- `logs/application.log`, `logs/error.log` — журнали програми.
- `tmp/desktop-worker.log`, `tmp/desktop-redis.log` — журнали допоміжних процесів.

## Структура коду

- `main.rb`, `lib/main.rb` — точка входу й аргументи командного рядка.
- `libs/app_config_loader.rb`, `configurator.rb` — YAML/ERB і перемикачі дій.
- `libs/item.rb`, `item_container.rb`, `item_collection.rb` — модель, колекція та експорт.
- `libs/simple_website_parser.rb` — парсинг і багатопоточність.
- `libs/database_connector.rb` — SQLite і MongoDB.
- `libs/engine.rb` — послідовність збору та збереження.
- `libs/archive_builder.rb`, `archive_sender.rb` — ZIP і фонова відправка.
- `libs/logger_manager.rb` — журнали.
- `scripts/desktop.rb` — повний запуск із керуванням Redis і worker.
- `scripts/run.ps1`, `setup_smtp.ps1`, `smtp_settings.ps1` — Windows-запуск і SMTP.
- `test/` — автоматичні перевірки; `examples/` — приклад результатів.

## Конфігурація та окремі команди

У `config/yaml_config/`: `web_parser.yaml` задає сайт, селектори й потоки;
`database_config.yaml` — БД; `execution.yaml` — перемикачі `0/1`;
`logging.yaml` — журнали; `archive.yaml` — SMTP, Redis і архіви.

`run_lab.cmd` завжди додає `--mongodb --send-archive`. Для запуску тільки
операцій з `execution.yaml` використовувати:

```powershell
.\scripts\run.ps1 run
```

За замовчуванням цей окремий режим виконує збір, файлові експорти, SQLite та ZIP.
Доступні `--mongodb`, `--send-archive`, `--no-sqlite`, `--no-archive`,
`--limit N`, `--pages N`, `--threads N`, `--show-config`, `--help`.
Команди `bundle exec ruby main.rb` і `bundle exec rake run` також виконують
окремий режим без автоматичного керування Redis та worker.

Для постійної черги потрібен окремо запущений Redis і worker:

```powershell
$env:REDIS_URL = 'redis://127.0.0.1:6379/0'
.\scripts\run.ps1 worker
```

У другому терміналі з тією ж `REDIS_URL`:

```powershell
.\scripts\run.ps1 run --mongodb --send-archive
```

Worker має три повторні спроби. `run.ps1` читає `.smtp.local.xml` для запуску
та worker; цей файл має пріоритет над змінними SMTP середовища.
Без нього параметри задаються через `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`,
`SMTP_USER`, `SMTP_PASSWORD`, `SMTP_STARTTLS`, `ARCHIVE_EMAIL`.

## Перевірки

```powershell
$env:TEST_MONGODB_URI = 'mongodb://127.0.0.1:27017'
.\scripts\run.ps1 test
.\scripts\run.ps1 lint
.\scripts\run.ps1 smtp-check
```

Тест MongoDB використовує окрему тимчасову базу. `smtp-check` перевіряє вхід,
не надсилаючи листа. Для локальної перевірки Sidekiq потрібні запущений тестовий
Redis та готовий ZIP:

```powershell
$env:TEST_REDIS_URL = 'redis://127.0.0.1:6379/15'
bundle exec ruby scripts/verify_background.rb
```

Коди завершення: `0` — успіх, `1` — помилка запуску або відправки,
`2` — частковий збій збору.
