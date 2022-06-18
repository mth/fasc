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
    args: seq[Expr]
  of xConcat: parts: seq[Expr]

type Rule = object
  param: seq[Expr]
  children: seq[Rule]

proc parseString(src: string, pos: var int): Expr

proc parseExpr(src: string, pos: var int): Expr =
  case src[pos]:
    of '"':
      return src.parseString(pos)
    of '(':
      pos.inc
      var param: seq[Expr]
      pos.inc src.skipWhitespace(pos)
      while pos < src.len and src[pos] != ')':
        if src[pos] == '#':
          pos.inc src.skipUntil(NewLines, pos)
        else:
          param.add src.parseExpr(pos)
          if param.len == 2 and param[1].kind != xVar:
            raise newException(ParseError, "Operator expected")
        pos.inc src.skipWhitespace(pos)
      if pos >= src.len:
        raise newException(ParseError, "Unclosed ')'")
      pos.inc
      if param.len == 0:
        return Expr(kind: xConcat, parts: @[]) # empty?
      if param.len == 1:
        return param[0]
      result = Expr(kind: xOp, op: param[1].name, args: param)
      result.args.delete 1
    else:
      var word: string
      pos.inc src.parseUntil(word, Whitespace + {'"', '(', ')', '#', '{', '}'}, pos)
      if word == "":
        raise newException(ParseError, "Syntax error")
      return Expr(kind: xVar, name: word)

proc parseTemplate(src: string, endCh: set[char], pos: var int): Expr =
  let embedCh = endCh + {'%'}
  var parts: seq[Expr]
  while pos < src.len:
    var str: string
    pos.inc src.parseUntil(str, embedCh, pos)
    if str != "":
      parts.add Expr(kind: xString, str: str)
    if pos >= src.len or src[pos] in endCh:
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
  return Expr(kind: xConcat, parts: parts)

proc parseString(src: string, pos: var int): Expr =
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
      case src[pos]:
        of '%':
          pos.inc
          rule.param.add src.parseExpr(pos)
        of '{':
          if rule.param.len == 0:
            raise newException(ParseError, "Unexpected '{'")
          pos.inc
          rule.children = src.parseRules pos
          if pos >= src.len:
            raise newException(ParseError, "Missing closing '}'")
          pos.inc
          break
        of '#':
          pos.inc src.skipUntil(Newlines, pos)
          break
        else:
          rule.param.add src.parseExpr(pos)
      pos.inc src.skipWhile(Whitespace - Newlines, pos)
    if rule.param.len != 0:
      result.add rule

proc parseRules*(src: string): seq[Rule] =
  var start = 0
  result = src.parseRules start
  if start < src.len:
    raise newException(ParseError, "Unexpected '}'")
