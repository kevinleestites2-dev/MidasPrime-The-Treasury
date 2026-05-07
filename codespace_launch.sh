#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║         PANTHEON CODESPACE LAUNCH SCRIPT v1.0               ║
# ║         One command. Full Pantheon online.                   ║
# ║         Ghost Operator Mode — watch from anywhere.          ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

PANTHEON_DIR="$HOME/pantheon"
LOG_DIR="$PANTHEON_DIR/logs"
PID_DIR="$PANTHEON_DIR/pids"

# ── COLORS ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║              🔱 PANTHEON AWAKENING SEQUENCE 🔱               ║"
  echo "║                   Ghost Operator Mode ON                     ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; }
heading() { echo -e "\n${BOLD}${CYAN}── $1 ──────────────────────────────────${NC}"; }

# ── PHASE 0: ENVIRONMENT ─────────────────────────────────────────────────────
phase0_env() {
  heading "PHASE 0 — ENVIRONMENT"

  mkdir -p "$LOG_DIR" "$PID_DIR"

  # Load .env if present
  if [ -f "$PANTHEON_DIR/.env" ]; then
    export $(grep -v '^#' "$PANTHEON_DIR/.env" | xargs)
    log ".env loaded"
  else
    warn "No .env found — some Primes may run in degraded mode"
  fi

  # Python check
  if ! command -v python3 &>/dev/null; then
    error "Python3 not found. Installing..."
    sudo apt-get update -qq && sudo apt-get install -y python3 python3-pip
  fi
  log "Python3: $(python3 --version)"

  # pip deps
  if [ -f "$PANTHEON_DIR/requirements.txt" ]; then
    log "Installing Python dependencies..."
    pip install -q -r "$PANTHEON_DIR/requirements.txt"
    log "Dependencies installed"
  fi
}

# ── PHASE 1: SPAWN PRIME ─────────────────────────────────────────────────────
spawn_prime() {
  local NAME=$1
  local SCRIPT=$2
  local ARGS=${3:-""}
  local PIDFILE="$PID_DIR/${NAME}.pid"
  local LOGFILE="$LOG_DIR/${NAME}.log"

  if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
    warn "$NAME already running (PID $(cat $PIDFILE)) — skipping"
    return
  fi

  if [ ! -f "$PANTHEON_DIR/$SCRIPT" ]; then
    warn "$NAME script not found: $SCRIPT — skipping"
    return
  fi

  nohup python3 "$PANTHEON_DIR/$SCRIPT" $ARGS > "$LOGFILE" 2>&1 &
  echo $! > "$PIDFILE"
  log "$NAME ONLINE (PID $!) → $LOGFILE"
  sleep 1
}

# ── PHASE 2: CORE REVENUE ENGINE ─────────────────────────────────────────────
phase2_revenue() {
  heading "PHASE 1 — CORE REVENUE ENGINE"
  spawn_prime "MidasPrime"   "midas_prime.py"
  spawn_prime "ZeusPrime"    "zeus_prime_v2.py"
  spawn_prime "ArbPrime"     "arb_prime.py"
  spawn_prime "BirdDog"      "bird_dog_engine.py"
  spawn_prime "StripeConduit" "stripe_conduit.py"
}

# ── PHASE 3: INTELLIGENCE LAYER ──────────────────────────────────────────────
phase3_intel() {
  heading "PHASE 2 — INTELLIGENCE LAYER"
  spawn_prime "ScoutPrime"    "scout_prime_v5.py"
  spawn_prime "OrionPrime"    "orion_prime.py"
  spawn_prime "DeepMeta"      "deep_meta.py"
  spawn_prime "AbsorbPrime"   "absorb_prime/absorb_prime.py"
  spawn_prime "ChronosPrime"  "chronos_prime.py"
}

# ── PHASE 4: DEFENSE & COMMS ─────────────────────────────────────────────────
phase4_defense() {
  heading "PHASE 3 — DEFENSE & COMMS"
  spawn_prime "SentinelPrime"  "sentinel_prime.py"
  spawn_prime "VanguardPrime"  "vanguard_prime.py"
  spawn_prime "AgentBrain"     "voice_prime/agent_brain.py"
}

# ── PHASE 5: ANYDESK BRIDGE (remote access from Red Magic) ───────────────────
phase5_anydesk() {
  heading "PHASE 4 — ANYDESK REMOTE BRIDGE"

  if command -v anydesk &>/dev/null; then
    nohup anydesk --tray > "$LOG_DIR/anydesk.log" 2>&1 &
    log "AnyDesk bridge ONLINE"
  else
    warn "AnyDesk not installed. Installing..."
    # Install AnyDesk headless
    wget -q https://download.anydesk.com/linux/anydesk_6.3.0-1_amd64.deb -O /tmp/anydesk.deb
    sudo dpkg -i /tmp/anydesk.deb 2>/dev/null || sudo apt-get install -f -y -qq
    nohup anydesk --tray > "$LOG_DIR/anydesk.log" 2>&1 &
    sleep 2
    log "AnyDesk bridge ONLINE"
  fi

  # Print AnyDesk ID for phone connection
  ANYDESK_ID=$(anydesk --get-id 2>/dev/null || echo "check AnyDesk manually")
  echo -e "${BOLD}${YELLOW}📱 AnyDesk ID: $ANYDESK_ID${NC}"
  echo -e "${YELLOW}   Connect from Red Magic → AnyDesk app → enter this ID${NC}"
}

# ── PHASE 6: STATUS BOARD ────────────────────────────────────────────────────
status_board() {
  heading "PANTHEON STATUS"
  echo ""
  printf "%-20s %-8s %-6s\n" "PRIME" "STATUS" "PID"
  printf "%-20s %-8s %-6s\n" "──────────────────" "──────" "─────"

  for PIDFILE in "$PID_DIR"/*.pid; do
    [ -f "$PIDFILE" ] || continue
    NAME=$(basename "$PIDFILE" .pid)
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" 2>/dev/null; then
      printf "${GREEN}%-20s %-8s %-6s${NC}\n" "$NAME" "ONLINE" "$PID"
    else
      printf "${RED}%-20s %-8s %-6s${NC}\n" "$NAME" "OFFLINE" "$PID"
    fi
  done

  echo ""
  echo -e "${CYAN}Logs: $LOG_DIR${NC}"
  echo -e "${CYAN}PIDs: $PID_DIR${NC}"
}

# ── KILL SWITCH ──────────────────────────────────────────────────────────────
kill_pantheon() {
  heading "SHUTDOWN SEQUENCE"
  for PIDFILE in "$PID_DIR"/*.pid; do
    [ -f "$PIDFILE" ] || continue
    NAME=$(basename "$PIDFILE" .pid)
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID"
      log "$NAME → OFFLINE"
    fi
    rm -f "$PIDFILE"
  done
  echo -e "${YELLOW}All Primes offline. Pantheon at rest.${NC}"
}

# ── MAIN ─────────────────────────────────────────────────────────────────────
case "${1:-launch}" in
  launch)
    banner
    phase0_env
    phase2_revenue
    phase3_intel
    phase4_defense
    phase5_anydesk
    status_board
    echo ""
    echo -e "${BOLD}${GREEN}🔱 PANTHEON ONLINE. Ghost Operator Mode ACTIVE. 🔱${NC}"
    echo ""
    ;;
  status)
    status_board
    ;;
  kill)
    kill_pantheon
    ;;
  restart)
    kill_pantheon
    sleep 2
    bash "$0" launch
    ;;
  *)
    echo "Usage: $0 [launch|status|kill|restart]"
    ;;
esac
