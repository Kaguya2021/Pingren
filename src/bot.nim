import os, strutils, json, options, db_connector/db_sqlite, asyncdispatch
import database, handlers, ping

proc startBot*() =
  let token = getEnv("BOT_TOKEN")
  if token.len == 0:
    echo "[ERROR] BOT_TOKEN environment variable is missing!"
    return

  let dbPath = getEnv("DATABASE_PATH", "data/bot.db")
  let db = initDb(dbPath)
  defer: db.close()

  let tg = TelegramClient(token: token)
  echo "[INFO] Bot started successfully..."

  # Запуск фонового планировщика
  asyncCheck runScheduler()
  runForever()
