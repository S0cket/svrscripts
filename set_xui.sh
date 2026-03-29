#!/bin/bash

SERVER_IP=
SSH_PORT=1234
SSH_TCP_FORWARDING=1
UFW=0

XUI_PATH=
XUI_PORT=1235
XUI_USER=root
XUI_PASSWORD=toor001
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

if [ ! -f "/etc/ssh/sshd_config~" ]; then
	cp /etc/ssh/sshd_config /etc/ssh/sshd_config~
fi
if [ -n "$SSH_PORT" ]; then
	set_sshd_option "Port" "$SSH_PORT"
fi
if [ -n "$SSH_TCP_FORWARDING" ]; then
	if [ "$SSH_TCP_FORWARDING" -eq 1 ]; then
		set_sshd_option "AllowTcpForwarding" "yes"
	else
		set_sshd_option "AllowTcpForwarding" "no"
	fi	
fi

if [ -n "$(cat /etc/os-release | grep "Ubuntu 24.04")" ]; then
	systemctl daemon-reload
	systemctl restart ssh.socket
else
	systemctl reload ssh
fi

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


DATA=$(expect <<'EOF'
spawn ./x-ui.sh

set timeout 10
expect {
	-re {enter.*selection} {}
	timeout {interact}
}
send "1\r"

set timeout 300
expect {
	-re {customize.*port} {}
	timeout {interact}
}
set timeout 10
if {"$XUI_PORT" != ""} {
	send "y\r"
	expect {
		-re {port} {}
		timeout {interact}
	}
	send "$XUI_PORT\r"
}
else {
	send "n\r"
}

expect {
	-re {SSL.*Choose} {}
	timeout {interact}
}
send "3\r"

expect {
	-re {certificate.*issued.*for} {}
	timeout {interact}
}
send "$SERVER_IP\r"

expect {
	-re {\.crt} {}
	timeout {interact}
}
send "$XUI_HOME/ssl/server.crt\r"

expect {
	-re {\.key} {}
	timeout {interact}
}
send "$XUI_HOME/ssl/server.key\r"

expect {
	-re {main.*menu} {}
	timeout {interact}
}
send "\r"

expect {
	-re {enter.*selection} {}
	timeout {interact}
}
send "6\r"

expect {
	-re {sure.*username.*password} {}
	timeout {interact}
}
send "y\r"

expect {
	-re {username} {}
	timeout {interact}
}
send "$XUI_USER\r"

expect {
	-re {password} {}
	timeout {interact}
}
send "$XUI_PASSWORD\r"

expect {
	-re {disable.*two-factor} {}
	timeout {interact}
}
send "y\r"

expect {
	-re {restart} {}
	timeout {interact}
}
send "y\r"


expect {
	-re {main.*menu} {}
	timeout {interact}
}
send "\r"

expect {
	-re {enter.*selection} {}
	timeout {interact}
}
send "10\r"

expect {
	eof {puts $expect_out(buffer)}
	timeout {interact}
}


EOF
)

echo $DATA

cd "$OLD_PWD"