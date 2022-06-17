import std/[strutils, parseutils]

# https://nim-lang.org/docs/strutils.html
# https://nim-lang.org/docs/parseutils.html

type Rule = object
    param: seq[string]
    children: seq[Rule]

const Space = {'\t', ' '}

proc parseRule(src: string, indent, start: var int): Rule =
    while start < src.len and src[start] in Whitespace:
        start.inc src.skipWhile(Whitespace - Space, start)
        indent = src.skipWhile(Space, start)
        start.inc indent
    while start < src.len and not (src[start] in Newlines):
        var word: string
        start.inc src.parseUntil(word, Whitespace, start)
        result.param.add word
        start.inc src.skipWhile(Whitespace - Newlines, start)

proc parseRules(src: string, start: var int): seq[Rule] =
    var ruleStack: seq[tuple[indent: int, rule: Rule]] = @[(0, Rule())]
    while true:
        var ruleIndent = 0
        let rule = src.parseRule(ruleIndent, start)
        if rule.param.len == 0:
            break
        while ruleIndent < ruleStack[^1].indent:
            discard ruleStack.pop
        if ruleIndent > ruleStack[^1].indent:
            ruleStack.add((ruleIndent, Rule()))
        ruleStack[^1].rule.children.add rule
    return ruleStack[0].rule.children

let src = readFile("test.rule")
var pos = 0
let rules = src.parseRules pos
for rule in rules:
    echo rule
