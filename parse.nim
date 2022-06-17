import std/[strutils, parseutils]

# https://nim-lang.org/docs/strutils.html
# https://nim-lang.org/docs/parseutils.html

type ParseError* = object of ValueError

type Rule = object
    param: seq[string]
    children: seq[Rule]

const Space = {'\t', ' '}

func isEOL(src: string; start: int): bool =
    start >= src.len or src[start] in NewLines

func parseRules(src: string, baseIndent: int, start: var int): seq[Rule] =
    var indent = -1
    while true:
        let oldIndent = indent
        indent = 0
        while start < src.len and src[start] in Whitespace:
            start.inc src.skipWhile(Whitespace - Space, start)
            indent = src.skipWhile(Space, start)
            start.inc indent
        if start >= src.len or indent <= baseIndent:
            start.dec indent
            return
        if oldIndent >= 0 and indent != oldIndent:
            raise newException(ParseError, "Inconsistent indent")
        var rule = Rule()
        var word = ""
        while not src.isEOL start:
            var parsedWord: string
            start.inc src.parseUntil(parsedWord, Whitespace, start)
            let sp = src.skipWhile(Whitespace - Newlines, start)
            start.inc sp
            word.add parsedWord
            if sp != 0 and not src.isEOL(start) or not parsedWord.endsWith ':':
                rule.param.add word
                word = ""
        if word != "":
            rule.param.add word[0..^2]
            rule.children = src.parseRules(indent, start)
            if rule.children.len == 0:
                raise newException(ParseError, "Missing child block")
        result.add rule

let src = readFile("test.rule")
var start = 0
let rules = src.parseRules(-1, start)
for rule in rules:
    echo rule
