import os, strutils

type Config* = object
  botToken*: string
  dbPath*: string
  pollTimeout*: int

proc loadEnvFile(path: string = ".env") =
  if fileExists(path):
    for line in lines(path):
      let trimmed = line.strip()
      if trimmed.len > 0 and not trimmed.startsWith("#"):
        let parts = trimmed.split("=", 1)
        if parts.len == 2:
          putEnv(parts[0].strip(), parts[1].strip())

proc loadConfig*(): Config =
  loadEnvFile()
  
  result.botToken = getEnv("BOT_TOKEN", "")
  if result.botToken.len == 0:
    quit("FATAL: BOT_TOKEN environment variable is not set!")
    
  result.dbPath = getEnv("DATABASE_PATH", "data/bot.db")
  result.pollTimeout = parseInt(getEnv("POLL_TIMEOUT", "30"))
