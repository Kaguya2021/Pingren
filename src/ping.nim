import httpclient, times, db_connector/db_sqlite, options, os, strutils, asyncdispatch

type PingResult* = object
  statusCode*: int
  responseTimeMs*: int64
  isSuccess*: bool

proc performPing*(url: string): PingResult =
  let client = newHttpClient(timeout = 10000)
  let startTime = cpuTime()
  try:
    let response = client.get(url)
    let elapsedMs = int64((cpuTime() - startTime) * 1000)
    let isOk = response.code.int >= 200 and response.code.int < 400
    return PingResult(statusCode: response.code.int, responseTimeMs: elapsedMs, isSuccess: isOk)
  except Exception:
    let elapsedMs = int64((cpuTime() - startTime) * 1000)
    return PingResult(statusCode: 0, responseTimeMs: elapsedMs, isSuccess: false)
  finally:
    client.close()

proc runScheduler*() {.async.} =
  while true:
    await sleepAsync(60000)
