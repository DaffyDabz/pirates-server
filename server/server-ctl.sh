#!/bin/bash
# pirates-online cluster control (Astron + UberDOG + AI).
# Installed copy lives ABOVE the game tree: /opt/pirates-online/server-ctl.sh (same rule as Toontown).
# Mirrors /opt/toontown-test/server-ctl.sh. Ports 7100-7199 belong to this game:
#   7100 client agent (players connect here), 7199 message director, 7197 event logger.
# Everything this script writes stays under $DATA so the whole game can be backed up or moved.

DATA=/opt/pirates-online
GAME=$DATA/pirates-online-classic
PY=/opt/python39/bin/python3.9
RUN=$DATA/run
LOGS=$DATA/logs
ASTROND=$GAME/astron/astrond
ASTRON_CFG=$GAME/astron/config/astrond.yml
MD_PORT=7199
CA_PORT=7100
EV_PORT=7197
SS_CHANNEL=10000
DISTRICT="Abassa"

mkdir -p "$RUN" "$LOGS" "$GAME/astron/databases" "$GAME/astron/logs"

wait_port() {
  local port=$1 n=0
  while ! (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null; do
    n=$((n+1)); [ $n -ge 30 ] && return 1; sleep 1
  done
  return 0
}
is_running() { local pf=$RUN/$1.pid; [ -f "$pf" ] && kill -0 "$(cat "$pf")" 2>/dev/null; }
rotate_log() { [ -f "$LOGS/$1.log" ] && mv -f "$LOGS/$1.log" "$LOGS/$1.prev.log"; }

# 11-20: a python3.9 grew to 19 GB (all of WSL's memory) at 18:09, and the OOM kill inside init.scope took all of WSL
# down. It was a lane test with no cap (lanes/tick), not the AI, but a runaway server program would do the same.
# Each daemon now starts in its own systemd scope (pirates-NAME-<time>, out of init.scope), capped at 8 GB on both its
# address space (prlimit --as) and its cgroup (MemoryMax), so a runaway fails alone and the watcher brings it back.
# systemd-run --scope and prlimit both exec, so $! is still the daemon's own pid. No systemd = the prlimit cap only.
MEM_CAP=8000000000
capped() {  # capped NAME: sets CAPPED to the command prefix for daemon NAME
  CAPPED=(prlimit --as=$MEM_CAP --)
  if [ -d /run/systemd/system ]; then
    CAPPED=(systemd-run --quiet --collect --scope --unit="pirates-$1-$(date +%s)" -p MemoryMax=$MEM_CAP "${CAPPED[@]}")
  fi
}

start_astrond() {
  if is_running astrond; then echo "astrond already running"; return; fi
  rotate_log astrond
  cd "$GAME/astron" || exit 1
  capped astrond
  setsid nohup "${CAPPED[@]}" "$ASTROND" --loglevel info "$ASTRON_CFG" >"$LOGS/astrond.log" 2>&1 9>&- &
  echo $! >"$RUN/astrond.pid"
  if wait_port $MD_PORT; then echo "astrond up (md $MD_PORT, ca $CA_PORT)"
  else echo "astrond did not open $MD_PORT:"; tail -20 "$LOGS/astrond.log"; fi
}

start_uberdog() {
  if is_running uberdog; then echo "uberdog already running"; return; fi
  rotate_log uberdog
  cd "$GAME" || exit 1
  capped uberdog
  setsid nohup "${CAPPED[@]}" "$PY" -m pirates.uberdog.ServiceStart \
    --base-channel 1000000 --max-channels 999999 --stateserver $SS_CHANNEL \
    --astron-ip 127.0.0.1:$MD_PORT --eventlogger-ip 127.0.0.1:$EV_PORT \
    >"$LOGS/uberdog.log" 2>&1 9>&- &
  echo $! >"$RUN/uberdog.pid"
  sleep 5
  if is_running uberdog; then echo "uberdog up"
  else echo "uberdog died:"; tail -20 "$LOGS/uberdog.log"; fi
}

start_ai() {
  if is_running ai; then echo "ai already running (pid $(cat "$RUN/ai.pid"))"; return; fi
  # an AI from this tree with no pid file is a stray: say so loudly, never start a second one beside it
  local stray; stray=$(pgrep -f "pirates.ai.ServiceStart" | head -1)
  if [ -n "$stray" ]; then echo "ai STRAY pid $stray (no pid file); adopting it"; echo "$stray" >"$RUN/ai.pid"; return; fi
  rotate_log ai
  cd "$GAME" || exit 1
  # a segfault leaves a core file here (core_pattern "core"), for the C frame of the next gc crash (11-16 17:21)
  ulimit -c unlimited
  capped ai
  setsid nohup "${CAPPED[@]}" "$PY" -m pirates.ai.ServiceStart \
    --base-channel 401000000 --max-channels 999999 --stateserver $SS_CHANNEL \
    --astron-ip 127.0.0.1:$MD_PORT --eventlogger-ip 127.0.0.1:$EV_PORT \
    --district-name "$DISTRICT" \
    >"$LOGS/ai.log" 2>&1 9>&- &
  echo $! >"$RUN/ai.pid"
  sleep 8
  if is_running ai; then echo "ai up (district $DISTRICT)"
  else echo "ai died:"; tail -20 "$LOGS/ai.log"; fi
}

stop_one() {
  local name=$1 pattern=$2 pf=$RUN/$1.pid
  if [ -f "$pf" ]; then
    local pid; pid=$(cat "$pf")
    kill "$pid" 2>/dev/null
    for i in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill -9 "$pid" 2>/dev/null
    rm -f "$pf"
  fi
  # belt and braces: the pattern is unique to this game tree, so it can never hit Toontown
  pkill -9 -f "$pattern" 2>/dev/null
  echo "stopped $name"
}

status() {
  for p in astrond uberdog ai; do
    if is_running $p; then echo "$p: running (pid $(cat $RUN/$p.pid))"; else echo "$p: stopped"; fi
  done
  for port in $MD_PORT $CA_PORT; do
    if (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null; then echo "port $port: open"; else echo "port $port: closed"; fi
  done
  # the event logger listens on UDP, so a TCP connect can never see it; ask the socket table instead
  if ss -lun 2>/dev/null | grep -q ":$EV_PORT "; then echo "port $EV_PORT/udp: open"; else echo "port $EV_PORT/udp: closed"; fi
  # ready = the AI made the district (Astron takes connections before it does)
  if is_running ai && grep -q 'District (.*) is now ready' "$DATA/logs/ai.log" 2>/dev/null \
      && (exec 3<>/dev/tcp/127.0.0.1/$CA_PORT) 2>/dev/null; then
    echo "ready: yes"; else echo "ready: no (district not up)"; fi
}

# The watcher (pirates-watch.timer, every 30 s) brings a crashed server back. A deliberate stop
# (dev panel, or by hand) writes $RUN/held and the watcher leaves it down until the next start.
watch() {
  [ -f "$RUN/held" ] && return 0
  local dead="" p
  for p in astrond uberdog ai; do is_running $p || dead="$dead $p"; done
  [ -z "$dead" ] && return 0
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  for p in $dead; do
    # a pid file with no process = it crashed; keep its log before start rotates it away
    [ -f "$RUN/$p.pid" ] && [ -f "$LOGS/$p.log" ] && cp -f "$LOGS/$p.log" "$LOGS/$p.crash-$ts.log"
  done
  echo "$(date '+%F %T') watch: down:$dead -> start" >>"$LOGS/watch.log"
  # astrond gone means the others lost their link; bring the whole stack back cleanly
  case "$dead" in *astrond*) stop_one ai "pirates.ai.ServiceStart"; stop_one uberdog "pirates.uberdog.ServiceStart" ;; esac
  start_astrond; start_uberdog; start_ai
  ls -t "$LOGS"/*.crash-*.log 2>/dev/null | tail -n +21 | xargs -r rm -f
}

# One lock for start/stop/restart/watch (pir-test 11-17): start used to drop "held" first and then spend
# 5-35 s on astrond + uberdog, so the 30 s watcher saw "ai down" and started a second AI beside the
# restart's own ("ai already running", watch.log 21:13:37 before SMOKE-landfight's stalled login).
# Now held stays until the whole start is done, and the watcher skips while anything holds the lock.
# the daemons get 9>&- so they never inherit (and hold) the lock; ctl.lock was held by one AI 11-17 21:59
LOCK=$RUN/ctl2.lock
players() { ss -tn state established "( sport = :$CA_PORT )" 2>/dev/null | tail -n +2 | wc -l; }
case "$1" in
  start)   exec 9>"$LOCK"; flock 9; touch "$RUN/held"; start_astrond; start_uberdog; start_ai; rm -f "$RUN/held" ;;
  watch)   exec 9>"$LOCK"; flock -n 9 || exit 0; watch ;;
  stop)    exec 9>"$LOCK"; flock 9; touch "$RUN/held"; stop_one ai "pirates.ai.ServiceStart"; stop_one uberdog "pirates.uberdog.ServiceStart"; stop_one astrond "$ASTRON_CFG" ;;
  restart) n=$(players); if [ "$n" != 0 ] && [ -z "$FORCE" ]; then echo "restart refused: $n player(s) on :$CA_PORT (FORCE=1 to override)"; exit 2; fi
           "$0" stop; sleep 2; "$0" start ;;
  status)  status ;;
  logs)    tail -n ${2:-30} "$LOGS/astrond.log" "$LOGS/uberdog.log" "$LOGS/ai.log" ;;
  *) echo "usage: $0 {start|stop|restart|status|watch|logs [n]}"; exit 1 ;;
esac
