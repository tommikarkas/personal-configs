[[ -r "/usr/local/etc/profile.d/bash_completion.sh" ]] && . "/usr/local/etc/profile.d/bash_completion.sh"

export PATH=$(brew --prefix openvpn)/sbin:$PATH

if [ -r ~/.bashrc ]; then
   source ~/.bashrc
fi
