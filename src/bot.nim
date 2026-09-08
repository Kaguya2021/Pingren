import httpclient, json, os, times, db_connector/db_sqlite
import config, database, handlers, ping

type BotManager* = object
  config*: Config
  db*: DbConn
  tg*: TelegramClient
  lastUpdateId*: int64

proc newBotManager*(cfg: Config): BotManager =
  result.config = cfg
  result.db = initDb(cfg.dbPath)
  result.tg = TelegramClient(token: cfg.botToken)
  result.lastUpdateId = 0

proc pollUpdates*(bm: var BotManager) =
  let client = newHttpClient(timeout = (bm.config.pollTimeout + 5) * 1000)
  let url = "https://api.telegram.org/bot" & bm.config.botToken & "/getUpdates?offset=" &
            $(bm.lastUpdateId + 1) & "&timeout=" & $bm.config.pollTimeout

  try:
    let responseText = client.getContent(url)
    let jsonResp = parseJson(responseText)

    if jsonResp["ok"].getBool() and jsonResp.hasKey("result"):
      for update in jsonResp["result"]:
        let updateId = update["update_id"].getBiggestInt()
        bm.lastUpdateId = updateId

        if update.hasKey("message"):
          handleMessage(bm.tg, bm.db, update["message"])
        elif update.hasKey("callback_query"):
          handleCallbackQuery(bm.tg, bm.db, update["callback_query"])

  except Exception as e:
    echo "[WARN] Error fetching updates: ", e.msg
    sleep(2000)
  finally:
    client.close()

proc start*(bm: var BotManager) =
  echo "[INFO] Bot started successfully"
  echo "[INFO] Database path: ", bm.config.dbPath
  
  var lastSchedulerTick: int64 = 0

  while true:
    # 1. Получение обновлений Telegram (Long Polling)
    bm.pollUpdates()

    # 2. Периодический запуск планировщика pings (раз в 30 секунд)
    let now = getTime().toUnix()
    if now - lastSchedulerTick >= 30:
      runScheduler(bm.db)
      lastSchedulerTick = now
