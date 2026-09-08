import httpclient, times, db_connector/db_sqlite, options, os
import database, utils

type PingResult* = object
  statusCode*: int
  responseTimeMs*: int
  isSuccess*: bool
  errorMsg*: string

proc performPing*(url: string, timeoutMs: int = 10000): PingResult =
  let client = newHttpClient(timeout = timeoutMs)
  client.headers = newHttpHeaders({
    "User-Agent": "RenderPingBot/1.0 (+https://github.com/render-ping-bot)"
  })
  
  let startTime = getTime()
  try:
    let resp = client.get(url)
    let elapsed = (getTime() - startTime).inMilliseconds.int
    let code = resp.status.split(" ")[0]
    let statusCode = try: parseInt(code) except: 200
    
    # Считаем успешными ответы 2xx и 3xx
    let isSuccess = statusCode >= 200 and statusCode < 400
    return PingResult(
      statusCode: statusCode,
      responseTimeMs: elapsed,
      isSuccess: isSuccess,
      errorMsg: if isSuccess: "" else: resp.status
    )
  except Exception as e:
    let elapsed = (getTime() - startTime).inMilliseconds.int
    return PingResult(
      statusCode: 0,
      responseTimeMs: elapsed,
      isSuccess: false,
      errorMsg: e.msg
    )
  finally:
    client.close()

proc runScheduler*(db: DbConn) =
  let dueServices = db.getDueServices()
  if dueServices.len == 0:
    return

  echo "[INFO] Running scheduler tick for ", dueServices.len, " service(s)"
  for service in dueServices:
    # Безопасное логирование без раскрытия URL
    echo "[INFO] Auto-pinging service for user_id: ", service.userId
    
    let res = performPing(service.renderUrl)
    db.logPingResult(
      service.id,
      res.statusCode,
      res.responseTimeMs,
      res.isSuccess,
      service.intervalMinutes
    )
    
    # Задержка между запросами для защиты от перегрузки сетевого стека
    sleep(500)
