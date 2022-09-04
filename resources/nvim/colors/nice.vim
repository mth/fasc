set background=dark
hi clear

if exists("syntax_on")
  syntax reset
endif

let colors_name = "nice"

hi Comment    ctermfg=Red          guifg=Red
hi Constant   ctermfg=Cyan         guifg=Cyan
hi Function   ctermfg=LightBlue    guifg=LightBlue cterm=bold gui=bold
hi Identifier ctermfg=Magenta      guifg=Magenta
hi Include    ctermfg=DarkMagenta  guifg=DarkMagenta
hi PreCondit  ctermfg=DarkMagenta  guifg=DarkMagenta
hi PreProc    ctermfg=LightMagenta guifg=LightMagenta
hi Special    ctermfg=LightGreen   guifg=seagreen
hi Statement  ctermfg=Yellow       guifg=Yellow
hi Type       ctermfg=DarkGreen    guifg=DarkGreen
hi SpellBad   ctermfg=Yellow       guifg=Yellow    ctermbg=DarkGray guibg=DarkGray
hi SpellCap   ctermfg=LightGray    guifg=LightGray ctermbg=DarkBlue guibg=DarkBlue
hi SpellRare  ctermfg=LightGray    guifg=LightGray ctermbg=DarkGray guibg=DarkGray
hi SpellLocal ctermfg=LightGray    guibg=LightGray ctermbg=DarkGray guibg=DarkGray

hi Search     term=reverse ctermbg=3 guibg=Gold2
hi IncSearch  term=reverse cterm=reverse gui=reverse
"hi ColorColumn ctermbg=darkgray guibg=darkgray

" vim: sw=2
