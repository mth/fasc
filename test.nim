import parse

let src = readFile("test.rule")
for rule in src.parseRules:
  echo rule
