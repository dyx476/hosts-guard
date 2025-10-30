#!/usr/bin/env bash
set -Eeuo pipefail
NEP_SVC="${1:-neptune}"
GUARD_BIN="/usr/local/bin/neptune_hosts_guard.sh"
GUARD_LOG_DIR="/var/log/neptune"
SUP_CONF="/etc/supervisor/conf.d/hosts_guard.conf"

install -d "$GUARD_LOG_DIR"

cat > "$GUARD_BIN" <<'GUARD'
#!/usr/bin/env bash
set -Eeuo pipefail
LOG="/var/log/neptune/hosts_guard.log"
NEP_SVC="${NEP_SVC:-neptune}"
SLEEP="${SLEEP:-60}"

IP1="62.60.246.192"; H1A="eu.poolhub.io";        H1B="62-60-246-192.sslip.io"
IP2="77.91.76.253"; H2A="77-91-76-253.sslip.io"; H2B="eu.poolhub.io"

need_fix(){ grep -q "^${IP1}[[:space:]]\+${H1A}\$" /etc/hosts && \
            grep -q "^${IP1}[[:space:]]\+${H1B}\$" /etc/hosts && \
            grep -q "^${IP2}[[:space:]]\+${H2A}\$" /etc/hosts && \
            grep -q "^${IP2}[[:space:]]\+${H2B}\$" /etc/hosts; }

write_hosts(){
  local hip="$(hostname -i 2>/dev/null || echo 127.0.1.1)"
  cat > /etc/hosts <<EOF
127.0.0.1       localhost
${hip}          $(hostname)
${IP1}   ${H1A}
${IP1}   ${H1B}
${IP2}   ${H2A}
${IP2}   ${H2B}
EOF
  command -v resolvectl >/dev/null && resolvectl flush-caches || true
}

restart_neptune(){ command -v supervisorctl >/dev/null 2>&1 && supervisorctl restart "${NEP_SVC}" || true; }

echo "$(date '+%F %T') [hosts_guard] start (every ${SLEEP}s)" >> "$LOG"

# initial fix
if ! need_fix; then
  echo "$(date '+%F %T') [hosts_guard] fix /etc/hosts (initial)" >> "$LOG"
  write_hosts
  restart_neptune
fi

# watch loop
while true; do
  if ! need_fix; then
    echo "$(date '+%F %T') [hosts_guard] fix /etc/hosts (drift)" >> "$LOG"
    write_hosts
    restart_neptune
    sleep 15
  fi
  sleep "$SLEEP"
done
GUARD
chmod +x "$GUARD_BIN"

cat > "$SUP_CONF" <<EOF
[program:hosts_guard]
command=/bin/bash -lc "$GUARD_BIN"
autostart=true
autorestart=true
startretries=999
stopasgroup=true
killasgroup=true
stdout_logfile=$GUARD_LOG_DIR/hosts_guard.out.log
stderr_logfile=$GUARD_LOG_DIR/hosts_guard.err.log
redirect_stderr=true
environment=NEP_SVC="$NEP_SVC",SLEEP="60"
EOF

supervisorctl reread || true
supervisorctl update || true
echo "OK: hosts_guard installed (program: hosts_guard, miner: $NEP_SVC)"
