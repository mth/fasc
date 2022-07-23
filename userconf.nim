const bashrc_prefix = """
PATH="/home/mzz/bin:$PATH:/home/mzz/.opam/default/bin"
"""

# This part is unlikely to need customization
const bashrc_fasc = """

### BEGIN FASC injection
# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
export LESSCHARSET=utf-8
export LESS_TERMCAP_md=$'\E[1;36m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[33m'

# don't put duplicate lines or lines starting with space in the history.
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000

shopt -s histappend
shopt -s checkwinsize
shopt -s globstar
shopt -s globasciiranges
shopt -s autocd

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
### END FASC injection

"""

const bashrc_prefix = """
PS1='\h \w\[\e`[ $? = 0 ]&&echo \e[32m||echo \e[31m`\]/\[\e[0m\] '
export JAVA_HOME=/usr/lib/jvm/default-java
alias ls='ls --color=auto'
alias jgrep='rg -tjava'
alias grep='grep --color=auto'
alias less='less -cS'
alias ocaml='rlwrap ocaml'
alias screen='env LOCKPRG=/bin/true screen'
alias bc='rlwrap bc'
alias sad='ssh-add'
alias ssh='TERM=xterm-256color ssh'
"""
