import std/os
import utils

# This part is unlikely to need customization, and probably should into /etc/bash.bashrc
const etc_bashrc = """
# If not running interactively, don't do anything
[ -z "$PS1" ] && return

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

[ -n "${SUDO_USER}" -a -n "${SUDO_PS1}" ] || PS1='\u@\h:\w\$ '
[ "$TERM" != "foot" ] || PROMPT_COMMAND='echo -ne "\033]0;${HOSTNAME@U} ${PWD}\007"'

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

alias ls='ls --color=auto'
alias grep='grep --color=auto'
"""

const debian_bashrc_header = "# ~/.bashrc: executed by bash(1) for non-login shells."

const dot_bashrc = """
PATH="$HOME/bin:$PATH:$HOME/.opam/default/bin"
[ -z "$PS1" ] && return
PS1='\h \w\[\e`[ $? = 0 ]&&echo \e[32m||echo \e[31m`\]/\[\e[0m\] '
export JAVA_HOME=/usr/lib/jvm/default-java
alias less='less -cS'
alias jgrep='rg -tjava'
alias ocaml='rlwrap ocaml'
alias screen='env LOCKPRG=/bin/true screen'
alias bc='rlwrap bc'
alias sad='ssh-add'
alias ssh='TERM=xterm-256color ssh'
"""

proc configureUserBash(user: UserInfo) =
  let bashrc = user.home / ".bashrc"
  try:
    if readLines(bashrc, 1) != [debian_bashrc_header]:
      echo(bashrc, " is not a debian default, not modifying")
      return
  except:
    discard # non-existent .bashrc isn't a problem
  echo("Replacing ", bashrc)
  writeFile(bashrc, dot_bashrc)

proc configureBash*(args: StrMap) =
  echo "Replacing /etc/bash.bashrc"
  writeFile("/etc/bash.bashrc", etc_bashrc)
  configureUserBash(args.userInfo)
