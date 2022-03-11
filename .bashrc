#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return
PS1='[\u@\h \W]\$ '

alias ls='ls -ltrh --color=auto'
alias htop='htop -d 5'
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME'
alias torch='docker run --rm -it --gpus all pytorch/pytorch ipython'
alias runvidia='__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia'

export PATH=$PATH:/home/reza/.local/bin/
