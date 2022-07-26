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
