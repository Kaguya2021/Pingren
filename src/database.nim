import db_connector/db_sqlite, os, times, strutils, options

type
  UserRecord* = object
    id*: int64
    telegramUserId*: int64
    username*: string
    firstName*: string
    state*: string
    createdAt*: int64

  ServiceRecord* = object
    id*: int64
    userId*: int64
    renderUrl*: string
    enabled*: bool
    intervalMinutes*: int
    lastPing*: int64
    nextPing*: int64
    createdAt*: int64

  StatsRecord* = object
    totalPings*: int
    successfulPings*: int
    failedPings*: int
    lastHttpStatus*: int
    avgResponseMs*: int
    lastPingTime*: int64

  PingLogRecord* = object
    id*: int64
    serviceId*: int64
    statusCode*: int
    responseTimeMs*: int
    isSuccess*: bool
    createdAt*: int64

proc initDb*(dbPath: string): DbConn =
  let dir = parentDir(dbPath)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
    
  let db = open(dbPath, "", "", "")
  
  db.exec(sql"""
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    telegram_user_id INTEGER UNIQUE NOT NULL,
    username TEXT DEFAULT '',
    first_name TEXT DEFAULT '',
    state TEXT DEFAULT 'IDLE',
    created_at INTEGER NOT NULL
  );
  """)

  db.exec(sql"""
  CREATE TABLE IF NOT EXISTS services (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER UNIQUE NOT NULL,
    render_url TEXT NOT NULL,
    enabled INTEGER DEFAULT 1,
    interval_minutes INTEGER DEFAULT 10,
    last_ping INTEGER DEFAULT 0,
    next_ping INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    FOREIGN KEY(user_id) REFERENCES users(telegram_user_id) ON DELETE CASCADE
  );
  """)

  db.exec(sql"""
  CREATE TABLE IF NOT EXISTS ping_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    service_id INTEGER NOT NULL,
    status_code INTEGER DEFAULT 0,
    response_time_ms INTEGER DEFAULT 0,
    is_success INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    FOREIGN KEY(service_id) REFERENCES services(id) ON DELETE CASCADE
  );
  """)

  db.exec(sql"CREATE INDEX IF NOT EXISTS idx_users_tg_id ON users(telegram_user_id);")
  db.exec(sql"CREATE INDEX IF NOT EXISTS idx_services_user_id ON services(user_id);")
  db.exec(sql"CREATE INDEX IF NOT EXISTS idx_services_next_ping ON services(enabled, next_ping);")
  db.exec(sql"CREATE INDEX IF NOT EXISTS idx_ping_history_service ON ping_history(service_id);")

  return db

proc registerOrUpdateUser*(db: DbConn, tgUserId: int64, username, firstName: string) =
  let now = getTime().toUnix()
  db.exec(sql"""
  INSERT INTO users (telegram_user_id, username, first_name, state, created_at)
  VALUES (?, ?, ?, 'IDLE', ?)
  ON CONFLICT(telegram_user_id) DO UPDATE SET
    username = excluded.username,
    first_name = excluded.first_name;
  """, tgUserId, username, firstName, now)

proc getUserState*(db: DbConn, tgUserId: int64): string =
  let res = db.getValue(sql"SELECT state FROM users WHERE telegram_user_id = ?", tgUserId)
  if res.len == 0: "IDLE" else: res

proc setUserState*(db: DbConn, tgUserId: int64, state: string) =
  db.exec(sql"UPDATE users SET state = ? WHERE telegram_user_id = ?", state, tgUserId)

proc getServiceByUserId*(db: DbConn, tgUserId: int64): Option[ServiceRecord] =
  let row = db.getRow(sql"""
  SELECT id, user_id, render_url, enabled, interval_minutes, last_ping, next_ping, created_at
  FROM services WHERE user_id = ?
  """, tgUserId)
  
  if row[0].len == 0:
    return none(ServiceRecord)
  else:
    return some(ServiceRecord(
      id: parseBiggestInt(row[0]),
      userId: parseBiggestInt(row[1]),
      renderUrl: row[2],
      enabled: row[3] == "1",
      intervalMinutes: parseInt(row[4]),
      lastPing: parseBiggestInt(row[5]),
      nextPing: parseBiggestInt(row[6]),
      createdAt: parseBiggestInt(row[7])
    ))

proc saveService*(db: DbConn, tgUserId: int64, url: string) =
  let now = getTime().toUnix()
  db.exec(sql"""
  INSERT INTO services (user_id, render_url, enabled, interval_minutes, last_ping, next_ping, created_at)
  VALUES (?, ?, 1, 10, 0, ?, ?)
  ON CONFLICT(user_id) DO UPDATE SET
    render_url = excluded.render_url,
    enabled = 1,
    next_ping = excluded.next_ping;
  """, tgUserId, url, now, now)

proc updateServiceStatus*(db: DbConn, tgUserId: int64, enabled: bool) =
  let status = if enabled: 1 else: 0
  db.exec(sql"UPDATE services SET enabled = ? WHERE user_id = ?", status, tgUserId)

proc updateServiceInterval*(db: DbConn, tgUserId: int64, minutes: int) =
  let now = getTime().toUnix()
  let nextPing = now + (minutes * 60)
  db.exec(sql"UPDATE services SET interval_minutes = ?, next_ping = ? WHERE user_id = ?", minutes, nextPing, tgUserId)

proc deleteService*(db: DbConn, tgUserId: int64) =
  let service = db.getServiceByUserId(tgUserId)
  if service.isSome:
    db.exec(sql"DELETE FROM ping_history WHERE service_id = ?", service.get.id)
    db.exec(sql"DELETE FROM services WHERE user_id = ?", tgUserId)

proc logPingResult*(db: DbConn, serviceId: int64, statusCode: int, responseMs: int, success: bool, intervalMinutes: int) =
  let now = getTime().toUnix()
  let nextPing = now + (intervalMinutes * 60)
  
  db.exec(sql"""
  INSERT INTO ping_history (service_id, status_code, response_time_ms, is_success, created_at)
  VALUES (?, ?, ?, ?, ?)
  """, serviceId, statusCode, responseMs, (if success: 1 else: 0), now)
  
  db.exec(sql"""
  UPDATE services SET last_ping = ?, next_ping = ? WHERE id = ?
  """, now, nextPing, serviceId)

  # Cleanup old history (keep last 200 records per service)
  db.exec(sql"""
  DELETE FROM ping_history WHERE id NOT IN (
    SELECT id FROM ping_history WHERE service_id = ? ORDER BY created_at DESC LIMIT 200
  ) AND service_id = ?
  """, serviceId, serviceId)

proc getUserStats*(db: DbConn, tgUserId: int64): StatsRecord =
  let service = db.getServiceByUserId(tgUserId)
  if service.isNone:
    return StatsRecord()

  let sId = service.get.id
  let total = parseInt(db.getValue(sql"SELECT COUNT(*) FROM ping_history WHERE service_id = ?", sId))
  let success = parseInt(db.getValue(sql"SELECT COUNT(*) FROM ping_history WHERE service_id = ? AND is_success = 1", sId))
  let failed = total - success
  
  let lastRow = db.getRow(sql"SELECT status_code, created_at FROM ping_history WHERE service_id = ? ORDER BY created_at DESC LIMIT 1", sId)
  let lastStatus = if lastRow[0].len > 0: parseInt(lastRow[0]) else: 0
  let lastTime = if lastRow[1].len > 0: parseBiggestInt(lastRow[1]) else: 0
  
  let avgMs = parseInt(db.getValue(sql"SELECT COALESCE(AVG(response_time_ms), 0) FROM ping_history WHERE service_id = ? AND is_success = 1", sId))

  return StatsRecord(
    totalPings: total,
    successfulPings: success,
    failedPings: failed,
    lastHttpStatus: lastStatus,
    avgResponseMs: avgMs,
    lastPingTime: lastTime
  )

proc getDueServices*(db: DbConn): seq[ServiceRecord] =
  let now = getTime().toUnix()
  let rows = db.getAllRows(sql"""
  SELECT id, user_id, render_url, enabled, interval_minutes, last_ping, next_ping, created_at
  FROM services 
  WHERE enabled = 1 AND next_ping <= ?
  """, now)
  
  result = @[]
  for row in rows:
    result.add(ServiceRecord(
      id: parseBiggestInt(row[0]),
      userId: parseBiggestInt(row[1]),
      renderUrl: row[2],
      enabled: row[3] == "1",
      intervalMinutes: parseInt(row[4]),
      lastPing: parseBiggestInt(row[5]),
      nextPing: parseBiggestInt(row[6]),
      createdAt: parseBiggestInt(row[7])
    ))
