import std/[strutils, parseutils]

# https://nim-lang.org/docs/strutils.html
# https://nim-lang.org/docs/parseutils.html

const Space = {'\t', ' '}

proc parseRule(src: string, start: var int): seq[string] =
    var indent = 0
    while start < src.len and src[start] in Whitespace:
        start = start + src.skipWhile(Whitespace - Space, start)
        indent = src.skipWhile(Space, start)
        start = start + indent
    while start < src.len and not (src[start] in Newlines):
        var word: string
        start = start + src.parseUntil(word, Whitespace, start)
        result.add word
        start = start + src.skipWhile(Whitespace - Newlines, start)

let src = readFile("test.rule")
var pos = 0
while pos < src.len:
    let cmd = src.parseRule pos
    echo cmd
