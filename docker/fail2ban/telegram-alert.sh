#!/bin/bash

IP="$1"
JAIL="$2"

curl -s -X POST \
"https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
-d chat_id="${CHAT_ID}" \
-d text="
[Fail2ban Alert]

Jail : ${JAIL}
IP : ${IP}

Action : BANNED
"