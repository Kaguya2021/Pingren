import config, bot

proc main() =
  echo "[INFO] Initializing Render Ping Bot in Nim..."
  let cfg = loadConfig()
  var manager = newBotManager(cfg)
  manager.start()

when isMainModule:
  main()
