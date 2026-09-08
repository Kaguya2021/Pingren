import uri, times, strutils

proc isValidRenderUrl*(urlString: string): bool =
  try:
    let parsed = parseUri(urlString)
    if parsed.scheme != "http" and parsed.scheme != "https":
      return false
    if parsed.hostname.len == 0:
      return false
    return true
  except:
    return false

proc formatAgo*(timestamp: int64): string =
  if timestamp <= 0:
    return "никогда"
  
  let diff = getTime().toUnix() - timestamp
  if diff < 60:
    return "только что"
  elif diff < 3600:
    return $ (diff div 60) & " мин назад"
  elif diff < 86400:
    return $ (diff div 3600) & " ч назад"
  else:
    return $ (diff div 86400) & " дн назад"
