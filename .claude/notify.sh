#!/usr/bin/env bash
# Cuentaria AFK orchestration — push notification to Jorge's phone via ntfy.
# Usage: .claude/notify.sh "message text"
# Subscribe on the phone: ntfy app -> subscribe to topic "cuentaria-afk-jc-k7w2p9"
set -euo pipefail
TOPIC="cuentaria-afk-jc-k7w2p9"
MSG="${1:-Cuentaria AFK: notification}"
curl -s -H "Title: Cuentaria AFK" -d "$MSG" "https://ntfy.sh/${TOPIC}" >/dev/null
