#!/bin/bash

SERVER_IP=
SSH_PORT=12348
SSH_TCP_FORWARDING=
UFW=0

XUI_PATH=
XUI_PORT=12346
XUI_USER=test
XUI_PASSWORD=testpass
XUI_URL="https://github.com/MHSanaei/3x-ui/releases/download/v2.8.11/x-ui-linux-amd64.tar.gz"

XUI_DIR="/opt"
XUI_HOME="$XUI_DIR/x-ui"

#-----------------------------------------

set_sshd_option() {
	local key="$1"
	local value="$2"
	local file="/etc/ssh/sshd_config"
	if grep -Eq "[[:space:]]*#?[[:space:]]*${key}[[:space:]]+" "$file"; then
		sed -E -i "s/^([[:space:]]*)#?([[:space:]]*${key}[[:space:]]+)[^#[:space:]]+(.*)$/\1\2${value}\3/" "$file"
	else
		echo "${key} ${value}" >> "$file"
	fi
}

OLD_PWD=$(pwd)
if [ -z "$SERVER_IP" ]; then
	SERVER_IP=$(curl https://ifconfig.me)
fi

systemctl stop ssh.socket
systemctl disable ssh.socket

cp /etc/ssh/sshd_config /etc/ssh/sshd_config~
if [ -z "$SSH_PORT" ]; then
	set_sshd_option "Port" "$SSH_PORT"
fi

if [ -z "$SSH_TCP_FORWARDING" ]; then
	if [ "$SSH_TCP_FORWARDING" -eq 1 ]; then
		set_sshd_option "AllowTcpForwarding" "yes"
	else
		set_sshd_option "AllowTcpForwarding" "no"
	fi	
fi
systemctl reload ssh

cd "$XUI_DIR"
wget $XUI_URL
arc_file="${XUI_URL##*/}"
case "$arc_file" in
	*.tar.gz) tar -xpzf "$arc_file" ;;
	*.tar.xz) tar -xpJf "$arc_file" ;;
	*.zip) unzip "$arc_file" ;;
	*) echo "Неизвестный формат файла $arc_file"; exit 1 ;;
esac
rm -rf "$arc_file"
mkdir -p "$XUI_HOME/ssl"
cd "$XUI_HOME/ssl"
openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
  -keyout "$XUI_HOME/ssl/server.key" \
  -out "$XUI_HOME/ssl/server.crt" \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:$SERVER_IP"
cd "$XUI_HOME"
chmod a+x x-ui.sh



cd "$OLD_PWD"
