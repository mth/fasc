import std/[strutils, parseutils]

# https://nim-lang.org/docs/strutils.html
# https://nim-lang.org/docs/parseutils.html

proc parseRule(src: string, start: var int): seq[string] =
    let indent = src.skipWhitespace start
    start = start + indent
    if start >= src.len:
        return @[]
    var word: string
    let eow = str.parseUntil(word, {' ', '\t', '\f', '\r', '\n'}, start)
    return @[]

echo readFile("README")
