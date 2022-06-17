import std/[strutils, parseutils]

# https://nim-lang.org/docs/strutils.html
# https://nim-lang.org/docs/parseutils.html

type ParseError* = object of ValueError

type ExprKind = enum xString, xVar, xOp, xConcat

type Expr = object
  case kind: ExprKind
  of xString: str: string
  of xVar: name: string
  of xOp:
    op: string
    left: ref Expr
    right: seq[Expr]
  of xConcat: parts: seq[Expr]

type Rule = object
  param: seq[Expr]
  children: seq[Rule]

func parseString(src: string, pos: var int): Expr

func parseExpr(src: string, pos: var int): Expr =
  Expr(kind: xVar, name: "") # TODO

func parseTemplate(src: string, endCh: set[char], pos: var int): Expr =
  let embedCh = endCh + {'%'}
  var parts: seq[Expr]
  while pos < src.len:
    var str: string
    pos.inc src.parseUntil(str, embedCh, pos)
    if str != "":
      parts.add Expr(kind: xString, str: str)
    if pos >= src.len or str[pos] in endCh:
      if pos + 1 < src.len and src[pos + 1] == '"':
        parts.add Expr(kind: xString, str: "\"")
      break
    pos.inc # skip %
    if src[pos] == '(':
      parts.add src.parseExpr(pos)
    else:
      let identLen = src.parseIdent(str, pos)
      if identLen > 0:
        pos.inc identLen
        parts.add Expr(kind: xVar, name: str)
      else:
        parts.add Expr(kind: xString, str: "%")
        if str[pos] == '%':
          pos.inc
  if parts.len == 0:
    return Expr(kind: xString, str: "")
  return Expr(kind: xConcat, parts: @[])

func parseString(src: string, pos: var int): Expr =
  pos.inc
  result = src.parseTemplate({'"'}, pos)
  if pos >= src.len:
    raise newException(ParseError, "Unclosed string")
  pos.inc

proc parseRules(src: string, pos: var int): seq[Rule] =
  while true:
    pos.inc src.skipWhitespace pos
    if pos >= src.len or src[pos] == '}':
      return
    var rule = Rule()
    while not (pos >= src.len or src[pos] in NewLines):
      if src[pos] == '"':
        rule.param.add src.parseString(pos)
      elif src[pos] == '{':
        if rule.param.len == 0:
          raise newException(ParseError, "Unexpected '{'")
        pos.inc
        rule.children = src.parseRules pos
        if pos >= src.len:
          raise newException(ParseError, "Missing closing '}'")
        pos.inc
        break
      else:
        var word: string
        pos.inc src.parseUntil(word, Whitespace, pos)
        rule.param.add Expr(kind: xString, str: word)
      pos.inc src.skipWhile(Whitespace - Newlines, pos)
    result.add rule

let src = readFile("test.rule")
var start = 0
let rules = src.parseRules start
if start < src.len:
  raise newException(ParseError, "Unexpected '}'")
for rule in rules:
  echo rule
