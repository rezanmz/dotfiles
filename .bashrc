#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return
PS1='[\u@\h \W]\$ '

alias ls='ls -ltrh --color=auto'
alias vim='nvim'
alias htop='htop -d 5'
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME'
alias pytorch='docker run --rm -it pytorch/pytorch ipython'

DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
