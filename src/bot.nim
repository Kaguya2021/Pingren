import os, strutils, json, options, db_connector/db_sqlite, asyncdispatch, asynchttpcom
import database, handlers, ping

proc serveDummyHttp() {.async.} =
  var server = newAsyncHttpServer()
  proc cb(req: Request) {.async.} =
    await req.respond(Http200, "Bot is alive!")
  let port = Port(parseInt(getEnv("PORT", "8080")))
  echo "[INFO] Binding HTTP server on port ", port
  server.listen(port)
  while true:
    if server.shouldAcceptRequest():
      await server.acceptRequest(cb)
    else:
      await sleepAsync(10)

proc startBot*() =
  let token = getEnv("BOT_TOKEN")
  if token.len == 0:
    echo "[ERROR] BOT_TOKEN environment variable is missing!"
    return

  let dbPath = getEnv("DATABASE_PATH", "data/bot.db")
  let db = initDb(dbPath)
  defer: db.close()

  echo "[INFO] Bot started successfully..."

  asyncCheck serveDummyHttp()
  asyncCheck runScheduler()
  runForever()
