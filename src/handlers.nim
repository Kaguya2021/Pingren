import json, strutils, options, db_connector/db_sqlite, times
import database, utils, ping

type TelegramClient* = object
  token*: string

proc apiUrl(tg: TelegramClient, method_name: string): string =
  "https://api.telegram.org/bot" & tg.token & "/" & method_name

proc sendRequest(tg: TelegramClient, method_name: string, payload: JsonNode) =
  let client = newHttpClient(timeout = 10000)
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  try:
    discard client.postContent(tg.apiUrl(method_name), $payload)
  except Exception as e:
    echo "[ERROR] Telegram API Request failed (", method_name, "): ", e.msg
  finally:
    client.close()

proc sendMessage*(tg: TelegramClient, chatId: int64, text: string, replyMarkup: JsonNode = nil) =
  var payload = %*{
    "chat_id": chatId,
    "text": text,
    "parse_mode": "HTML",
    "disable_web_page_preview": true
  }
  if replyMarkup != nil:
    payload["reply_markup"] = replyMarkup
  tg.sendRequest("sendMessage", payload)

proc editMessageText*(tg: TelegramClient, chatId: int64, messageId: int64, text: string, replyMarkup: JsonNode = nil) =
  var payload = %*{
    "chat_id": chatId,
    "message_id": messageId,
    "text": text,
    "parse_mode": "HTML",
    "disable_web_page_preview": true
  }
  if replyMarkup != nil:
    payload["reply_markup"] = replyMarkup
  tg.sendRequest("editMessageText", payload)

proc answerCallbackQuery*(tg: TelegramClient, callbackQueryId: string, text: string = "") =
  var payload = %*{
    "callback_query_id": callbackQueryId
  }
  if text.len > 0:
    payload["text"] = text
  tg.sendRequest("answerCallbackQuery", payload)

# Генераторы клавиатур
proc buildMainMenuKeyboard*(hasService: bool, isEnabled: bool): JsonNode =
  if not hasService:
    return %*{
      "inline_keyboard": [
        [{"text": "🔗 Добавить сервис", "callback_data": "action_add"}],
        [{"text": "❓ Помощь", "callback_data": "action_help"}]
      ]
    }
  
  let toggleText = if isEnabled: "🟢 Ping: ВКЛ" else: "🔴 Ping: ВЫКЛ"
  return %*{
    "inline_keyboard": [
      [{"text": "🔄 Проверить сейчас", "callback_data": "action_check"}],
      [{"text": "📊 Статистика", "callback_data": "action_stats"}, {"text": toggleText, "callback_data": "action_toggle"}],
      [{"text": "⚙️ Настройки", "callback_data": "action_settings"}]
    ]
  }

proc buildSettingsKeyboard*(): JsonNode =
  return %*{
    "inline_keyboard": [
      [{"text": "⏱ Изменить интервал", "callback_data": "menu_interval"}],
      [{"text": "🔗 Изменить URL", "callback_data": "action_add"}],
      [{"text": "🗑 Удалить сервис", "callback_data": "action_delete_confirm"}],
      [{"text": "⬅️ Назад в меню", "callback_data": "menu_main"}]
    ]
  }

proc buildIntervalKeyboard*(): JsonNode =
  return %*{
    "inline_keyboard": [
      [{"text": "⏱ 10 минут", "callback_data": "set_interval_10"}, {"text": "⏱ 15 минут", "callback_data": "set_interval_15"}],
      [{"text": "⏱ 20 минут", "callback_data": "set_interval_20"}, {"text": "⏱ 30 минут", "callback_data": "set_interval_30"}],
      [{"text": "⬅️ Назад в настройки", "callback_data": "action_settings"}]
    ]
  }

proc buildDeleteConfirmKeyboard*(): JsonNode =
  return %*{
    "inline_keyboard": [
      [{"text": "❌ Отмена", "callback_data": "action_settings"}, {"text": "🗑 Да, удалить", "callback_data": "action_delete_do"}]
    ]
  }

proc buildBackToMenuKeyboard*(): JsonNode =
  return %*{
    "inline_keyboard": [
      [{"text": "⬅️ В главное меню", "callback_data": "menu_main"}]
    ]
  }

# Рендеринг главных экранов
proc renderMainView*(db: DbConn, tgUserId: int64): (string, JsonNode) =
  let service = db.getServiceByUserId(tgUserId)
  if service.isNone:
    let text = "╭─────────────────────╮\n" &
               "│ 🚀 <b>RENDER PING BOT</b>    │\n" &
               "├─────────────────────┤\n" &
               "│ У вас пока нет     │\n" &
               "│ активного сервиса.  │\n" &
               "│                     │\n" &
               "│ Нажмите кнопку ниже │\n" &
               "│ для добавления.     │\n" &
               "╰─────────────────────╯"
    return (text, buildMainMenuKeyboard(false, false))
  
  let s = service.get
  let statusStr = if s.enabled: "🟢 Активен" else: "🔴 Приостановлен"
  let lastPingStr = formatAgo(s.lastPing)
  
  let text = "╭─────────────────────╮\n" &
             "│ 🚀 <b>RENDER PING BOT</b>    │\n" &
             "├─────────────────────┤\n" &
             "│ Статус: " & statusStr & "\n" &
             "│ Интервал: " & $s.intervalMinutes & " мин\n" &
             "│ Проверка: " & lastPingStr & "\n" &
             "╰─────────────────────╯"
  
  return (text, buildMainMenuKeyboard(true, s.enabled))

# Обработка команд и текстовых сообщений
proc handleMessage*(tg: TelegramClient, db: DbConn, msg: JsonNode) =
  if not msg.hasKey("from") or not msg.hasKey("chat"): return
  
  let chatId = msg["chat"]["id"].getBiggestInt()
  let tgUserId = msg["from"]["id"].getBiggestInt()
  let username = if msg["from"].hasKey("username"): msg["from"]["username"].getStr() else: ""
  let firstName = if msg["from"].hasKey("first_name"): msg["from"]["first_name"].getStr() else: "User"
  let text = if msg.hasKey("text"): msg["text"].getStr().strip() else: ""

  db.registerOrUpdateUser(tgUserId, username, firstName)
  let currentState = db.getUserState(tgUserId)

  if text == "/start":
    db.setUserState(tgUserId, "IDLE")
    let (viewText, keyboard) = renderMainView(db, tgUserId)
    tg.sendMessage(chatId, viewText, keyboard)
    return

  elif text == "/help":
    let helpText = "ℹ️ <b>Справка по боту</b>\n\n" &
                   "Этот бот выполняет регулярные HTTP-запросы к вашему Render-сервису, чтобы предотвратить его переход в спящий режим.\n\n" &
                   "<b>Команды:</b>\n" &
                   "/start — Главное меню\n" &
                   "/status — Состояние сервиса\n" &
                   "/check — Ручная проверка\n" &
                   "/settings — Настройки бота\n" &
                   "/help — Данная справка"
    tg.sendMessage(chatId, helpText, buildBackToMenuKeyboard())
    return

  elif text == "/status" or text == "/check" or text == "/settings":
    db.setUserState(tgUserId, "IDLE")
    let (viewText, keyboard) = renderMainView(db, tgUserId)
    tg.sendMessage(chatId, viewText, keyboard)
    return

  # Ожидание URL сервиса
  if currentState == "WAITING_FOR_URL":
    if not isValidRenderUrl(text):
      let errText = "❌ <b>Некорректный URL!</b>\n\n" &
                    "Отправьте валидный HTTP или HTTPS URL.\n" &
                    "<i>Пример: https://my-app.onrender.com</i>"
      tg.sendMessage(chatId, errText, buildBackToMenuKeyboard())
      return

    # Проводим первичную проверку доступности
    tg.sendMessage(chatId, "🔍 <i>Проверяем доступность URL...</i>")
    let pingRes = performPing(text)
    
    db.saveService(tgUserId, text)
    db.setUserState(tgUserId, "IDLE")

    let serviceOpt = db.getServiceByUserId(tgUserId)
    if serviceOpt.isSome:
      db.logPingResult(serviceOpt.get.id, pingRes.statusCode, pingRes.responseTimeMs, pingRes.isSuccess, 10)

    let successText = "✅ <b>Сервис успешно сохранён!</b>\n\n" &
                      "🟢 <b>Ping:</b> Активен\n" &
                      "⏱ <b>Интервал:</b> 10 минут\n" &
                      "📡 <b>Первичный HTTP-ответ:</b> " & (if pingRes.statusCode > 0: $pingRes.statusCode else: "Ошибка соединения") & "\n\n" &
                      "🔒 <i>URL сохранен изолированно в вашем аккаунте.</i>"
    tg.sendMessage(chatId, successText, buildBackToMenuKeyboard())
    return

  # Дефолтный ответ
  let (viewText, keyboard) = renderMainView(db, tgUserId)
  tg.sendMessage(chatId, viewText, keyboard)

# Обработка Inline-кнопок
proc handleCallbackQuery*(tg: TelegramClient, db: DbConn, callback: JsonNode) =
  let callbackId = callback["id"].getStr()
  let chatId = callback["message"]["chat"]["id"].getBiggestInt()
  let messageId = callback["message"]["message_id"].getBiggestInt()
  let tgUserId = callback["from"]["id"].getBiggestInt()
  let data = callback["data"].getStr()

  tg.answerCallbackQuery(callbackId)

  if data == "menu_main":
    db.setUserState(tgUserId, "IDLE")
    let (viewText, keyboard) = renderMainView(db, tgUserId)
    tg.editMessageText(chatId, messageId, viewText, keyboard)

  elif data == "action_add":
    db.setUserState(tgUserId, "WAITING_FOR_URL")
    let promptText = "🔗 <b>Добавление сервиса</b>\n\n" &
                     "Отправьте URL вашего Render-сервиса в ответ на это сообщение.\n\n" &
                     "Например:\n<code>https://my-service.onrender.com</code>\n\n" &
                     "🔒 <i>Ссылка доступна только вам и используется исключительно для HTTP GET проверок.</i>"
    tg.editMessageText(chatId, messageId, promptText, buildBackToMenuKeyboard())

  elif data == "action_check":
    let service = db.getServiceByUserId(tgUserId)
    if service.isNone:
      tg.editMessageText(chatId, messageId, "⚠️ Сервис не найден.", buildBackToMenuKeyboard())
      return

    tg.editMessageText(chatId, messageId, "🔄 <i>Выполняем запрос к вашему сервису...</i>")
    
    let res = performPing(service.get.renderUrl)
    db.logPingResult(service.get.id, res.statusCode, res.responseTimeMs, res.isSuccess, service.get.intervalMinutes)

    var resultText = ""
    if res.isSuccess:
      resultText = "🔍 <b>Результат проверки</b>\n\n" &
                   "🟢 <b>Статус:</b> ONLINE\n" &
                   "📡 <b>HTTP код:</b> " & $res.statusCode & "\n" &
                   "⚡ <b>Время отклика:</b> " & $res.responseTimeMs & " ms\n" &
                   "🕐 <b>Проверено:</b> только что"
    else:
      resultText = "🔍 <b>Результат проверки</b>\n\n" &
                   "🔴 <b>Статус:</b> OFFLINE / Oшибка\n" &
                   "⚠️ <b>Детали:</b> " & (if res.statusCode > 0: "HTTP " & $res.statusCode else: "Сервер недоступен") & "\n" &
                   "⚡ <b>Время отклика:</b> " & $res.responseTimeMs & " ms\n" &
                   "🕐 <b>Проверено:</b> только что"

    tg.editMessageText(chatId, messageId, resultText, buildBackToMenuKeyboard())

  elif data == "action_stats":
    let stats = db.getUserStats(tgUserId)
    let statsText = "📊 <b>Ваша статистика</b>\n\n" &
                    "🟢 <b>Успешных проверок:</b> " & $stats.successfulPings & "\n" &
                    "🔴 <b>Ошибок:</b> " & $stats.failedPings & "\n" &
                    "📡 <b>Последний HTTP код:</b> " & (if stats.lastHttpStatus > 0: $stats.lastHttpStatus else: "N/A") & "\n" &
                    "⚡ <b>Средний отклик:</b> " & $stats.avgResponseMs & " ms\n" &
                    "🕐 <b>Последняя проверка:</b> " & formatAgo(stats.lastPingTime)
    tg.editMessageText(chatId, messageId, statsText, buildBackToMenuKeyboard())

  elif data == "action_toggle":
    let service = db.getServiceByUserId(tgUserId)
    if service.isSome:
      let newState = not service.get.enabled
      db.updateServiceStatus(tgUserId, newState)
    let (viewText, keyboard) = renderMainView(db, tgUserId)
    tg.editMessageText(chatId, messageId, viewText, keyboard)

  elif data == "action_settings":
    let settingsText = "⚙️ <b>Настройки сервиса</b>\n\n" &
                       "Выберите параметр для изменения:"
    tg.editMessageText(chatId, messageId, settingsText, buildSettingsKeyboard())

  elif data == "menu_interval":
    let intervalText = "⏱ <b>Выбор интервала проверки</b>\n\n" &
                       "Укажите периодичность отправки пингов:"
    tg.editMessageText(chatId, messageId, intervalText, buildIntervalKeyboard())

  elif data.startsWith("set_interval_"):
    let minutesStr = data.replace("set_interval_", "")
    let minutes = try: parseInt(minutesStr) except: 10
    db.updateServiceInterval(tgUserId, minutes)
    
    let confirmText = "✅ <b>Интервал обновлен!</b>\n\nНовая периодичность: <b>" & $minutes & " минут</b>."
    tg.editMessageText(chatId, messageId, confirmText, buildBackToMenuKeyboard())

  elif data == "action_delete_confirm":
    let delText = "⚠️ <b>Удаление сервиса</b>\n\n" &
                  "Вы уверены, что хотите удалить сохраненный URL и всю историю проверок?"
    tg.editMessageText(chatId, messageId, delText, buildDeleteConfirmKeyboard())

  elif data == "action_delete_do":
    db.deleteService(tgUserId)
    let doneText = "🗑 <b>Сервис удален!</b>\n\nВсе ваши данные и статистика успешно очищены."
    tg.editMessageText(chatId, messageId, doneText, buildBackToMenuKeyboard())
