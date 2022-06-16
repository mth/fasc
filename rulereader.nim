import std/[strutils, parseutils]

# https://nim-lang.org/docs/strutils.html
# https://nim-lang.org/docs/parseutils.html

proc parseRule(src: string, start: var int): seq[string] =
    let indent = src.skipWhitespace
    start = start + indent
    if start >= src.len:
        return @[]
    return @[]

echo readFile("README")
