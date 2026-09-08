import strutils, times

proc isValidRenderUrl*(url: string): bool =
  let cleanUrl = url.strip()
  if not (cleanUrl.startsWith("http://") or cleanUrl.startsWith("https://")):
    return false
  return cleanUrl.contains(".")

proc formatAgo*(timestamp: int64): string =
  if timestamp == 0: return "никогда"
  let diff = getTime().toUnix() - timestamp
  if diff < 60: return $diff & " сек. назад"
  elif diff < 3600: return $(diff div 60) & " мин. назад"
  elif diff < 86400: return $(diff div 3600) & " ч. назад"
  else: return $(diff div 86400) & " дн. назад"
