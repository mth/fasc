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

const Space = {'\t', ' '}

func isEOL(src: string, pos: int): bool =
  pos >= src.len or src[pos] in NewLines

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

func parseRule(src: string, rule: var Rule, pos: var int): bool =
  var word = ""
  while not src.isEOL pos:
    if src[pos] == '"':
      rule.param.add src.parseString(pos)
      pos.inc src.skipWhile(Whitespace - Newlines, pos)
    else:
      var parsedWord: string
      pos.inc src.parseUntil(parsedWord, Whitespace, pos)
      let sp = src.skipWhile(Whitespace - Newlines, pos)
      pos.inc sp
      word.add parsedWord
      if sp != 0 and not src.isEOL(pos) or not parsedWord.endsWith ':':
        rule.param.add Expr(kind: xString, str: word)
        word = ""
  if word != "":
    rule.param.add Expr(kind: xString, str: word[0..^2])
    return true

func parseRules(src: string, baseIndent: int, pos: var int): seq[Rule] =
  var indent = -1
  while true:
    let oldIndent = indent
    indent = 0
    while pos < src.len and src[pos] in Whitespace:
      pos.inc src.skipWhile(Whitespace - Space, pos)
      indent = src.skipWhile(Space, pos)
      pos.inc indent
    if pos >= src.len or indent <= baseIndent:
      pos.dec indent
      return
    if oldIndent >= 0 and indent != oldIndent:
      raise newException(ParseError, "Inconsistent indent")
    var rule = Rule()
    if src.parseRule(rule, pos):
      rule.children = src.parseRules(indent, pos)
      if rule.children.len == 0:
        raise newException(ParseError, "Missing child block")
    result.add rule

let src = readFile("test.rule")
var start = 0
let rules = src.parseRules(-1, start)
for rule in rules:
  echo rule
