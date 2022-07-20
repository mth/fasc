import utils, std/[tables, os, sugar]

var update: Table[string, proc(old: string): string]

for nth in 1 .. (paramCount() - 1) div 2:
  let idx = nth * 2
  let key = paramStr(idx)
  let value = paramStr(idx + 1)
  capture value:
    update[key] = proc(old: string): string =
      return value

modifyProperties(paramStr(1), update)
