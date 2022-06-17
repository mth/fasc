import std/[strutils, parseutils]

# https://nim-lang.org/docs/strutils.html
# https://nim-lang.org/docs/parseutils.html

type ParseError* = object of ValueError

type Rule = object
    param: seq[string]
    children: seq[Rule]

const Space = {'\t', ' '}

func isEOL(src: string; pos: int): bool =
    pos >= src.len or src[pos] in NewLines

func parseRule(src: string, rule: var Rule, pos: var int): bool =
    var word = ""
    while not src.isEOL pos:
        var parsedWord: string
        #while pos >= src.len && src[pos] == '"':
        #    pos.inc
        #    pos.inc src.parseUntil(parsedWord, {'"'}, pos)
        #    if pos >= src.len:
        #        raise newException(ParseError, "Unclosed string")
        #    pos.inc
        pos.inc src.parseUntil(parsedWord, Whitespace, pos)
        let sp = src.skipWhile(Whitespace - Newlines, pos)
        pos.inc sp
        word.add parsedWord
        if sp != 0 and not src.isEOL(pos) or not parsedWord.endsWith ':':
            rule.param.add word
            word = ""
    if word != "":
        rule.param.add word[0..^2]
        return true
    return false

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
