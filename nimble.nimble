# Package

version       = "1.0.0"
author        = "Render Ping Bot Developer"
description   = "Multi-user Telegram bot to monitor personal Render services"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["main"]

# Dependencies

requires "nim >= 1.6.0"
requires "db_connector"
