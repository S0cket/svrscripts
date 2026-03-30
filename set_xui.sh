#!/bin/bash

SERVER_IP=
SSH_PORT=1234
SSH_TCP_FORWARDING=1
UFW_ENABLE=0
UFW_OTHER_PORTS=(443) # (443 1234 7777)

XUI_PATH=/root/root/
XUI_PORT=
XUI_USER=
XUI_PASSWORD=
XUI_URL="https://github.com/MHSanaei/3x-ui/releases/download/v2.8.11/x-ui-linux-amd64.tar.gz"

XUI_DIR="/opt"
XUI_HOME="$XUI_DIR/x-ui"

#-----------------------------------------

_XUI_INSTALL_CMD=1
_XUI_SSL_CUSTOM=3
_XUI_RESET_USER_CMD=6
_XUI_STOP_CMD=12
_XUI_START_CMD=11
_XUI_INFO_CMD=10
_XUI_EXIT_CMD=0

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

apt-get update
apt-get install -y expect

expect <<EOF

spawn ./x-ui.sh

set timeout 10
expect {
	-re {enter.*selection} {}
	timeout {interact}
}
send "$_XUI_INSTALL_CMD\r"

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
} else {
	send "n\r"
}

expect {
	-re {SSL.*Choose} {}
	timeout {interact}
}
send "$_XUI_SSL_CUSTOM\r"

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
send "$_XUI_STOP_CMD\r"

expect {
	-re {return.*main.*menu} {}
	timeout {interact}
}
send "\r"

expect {
	-re {enter.*selection} {}
	timeout {interact}
}
send "$_XUI_EXIT_CMD\r"
EOF

if [ -n "$XUI_PATH" ]; then
	apt-get install -y sqlite3
	sqlite3 /etc/x-ui/x-ui.db "update settings set value=\"$XUI_PATH\" where key=\"webBasePath\";"
fi

expect <<EOF
spawn ./x-ui.sh
set timeout 10

expect {
	-re {enter.*selection} {}
	timeout {interact}
}
send "$_XUI_START_CMD\r"

expect {
	-re {return.*main.*menu} {}
	timeout {interact}
}
send "\r"

expect {
	-re {enter.*selection} {}
	timeout {interact}
}
send "$_XUI_EXIT_CMD\r"
EOF

_USER_INFO=$(
_XUI_RESET_USER_CMD="$_XUI_RESET_USER_CMD" _XUI_EXIT_CMD="$_XUI_EXIT_CMD" XUI_USER="$XUI_USER" XUI_PASSWORD="$XUI_PASSWORD" expect <<'EOF'
log_user 0
spawn ./x-ui.sh
set timeout 10
set user ""
set password ""

expect {
	-re {enter.*selection} {}
	timeout {exit 1}
}
send "$env(_XUI_RESET_USER_CMD)\r"

expect {
	-re {sure.*username.*password} {}
	timeout {exit 2}
}
send "y\r"

expect {
	-re {username} {}
	timeout {exit 3}
}
send "$env(XUI_USER)\r"

expect {
	-re {password} {}
	timeout {exit 4}
}
send "$env(XUI_PASSWORD)\r"

expect {
	-re {disable.*two-factor} {}
	timeout {exit 5}
}
send "y\r"

expect {
	-re {Panel login username has been reset to:[[:space:]]+([^[:space:]]+)} {
		set user $expect_out(1,string)
		exp_continue
	}
	-re {Panel login password has been reset to:[[:space:]]+([^[:space:]]+)} {
		set password $expect_out(1,string)
		exp_continue
	}
	-re {restart.*xray} {send "y\r"}
	timeout {exit 6}
}

expect {
	-re {return.*main.*menu} {}
	timeout {exit 7}
}
send "\r"

expect {
	-re {enter.*selection} {}
	timeout {exit 8}
}
send "$env(_XUI_EXIT_CMD)\r"

puts "username $user"
puts "password $password"
EOF
)

_SERVER_INFO=$(
_XUI_INFO_CMD="$_XUI_INFO_CMD" expect <<'EOF'
log_user 0
spawn ./x-ui.sh
set timeout 10
set port ""
set path ""
set url ""

expect {
	-re {enter.*selection} {}
	timeout {exit 9}
}
send "$env(_XUI_INFO_CMD)\r"
expect {
	-re {port:[[:space:]]+([0-9]+)} {
		set port $expect_out(1,string)
		exp_continue
	}
	-re {webBasePath:[[:space:]]+([^[:space:]]+)} {
		set path $expect_out(1,string)
		exp_continue
	}
	-re {Access URL:[[:space:]]+([^[:space:]]+)} {
		set url $expect_out(1,string)
		exp_continue
	}
	eof {}
}
puts "url $url"
puts "port $port"
puts "path $path"
EOF
)

echo
echo "$_SERVER_INFO"
echo
echo "$_USER_INFO"
echo


_SSH_PORT=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2}' /etc/ssh/sshd_config)
if [ -z "$_SSH_PORT" ]; then
	_SSH_PORT=22
fi

_XUI_PORT=$(echo "$_SERVER_INFO" | awk '/^port[[:space:]]+[0-9]+/{print $2}')
echo "$_XUI_PORT"

if [ "$UFW_ENABLE" -eq 1 ]; then
	apt-get install -y ufw
	ufw allow _SSH_PORT
	for port in "${UFW_OTHER_PORTS[@]}"; do
		ufw allow "$port"
	done

fi


cd "$OLD_PWD"