#!/usr/bin/env bash
# Obelo installer — sets up Obelo (and optionally ntfy and nightly backups) on a Linux
# server with Docker. Interactive: it asks before every change and skips anything already done,
# so it's safe to re-run. It never overwrites an existing .env.
#
#   git clone <repo-url> obelo && cd obelo && ./install.sh
#
# Options:
#   --env-only   only create .env (don't install Docker or start anything)
#   --help       show this help
set -euo pipefail

cd "$(dirname "$0")"
REPO_DIR="$(pwd)"

# ── Output helpers ───────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; RESET=$'\e[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; RESET=''
fi
step()  { printf '\n%s▸ %s%s\n' "$BOLD$BLUE" "$*" "$RESET"; }
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
die()   { printf '\n%s✗ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

# ask VAR "Question" [default]
ask() {
  local __var=$1 __prompt=$2 __default=${3:-} __reply
  if [ -n "$__default" ]; then
    read -r -p "  $__prompt [$__default]: " __reply || true
    __reply=${__reply:-$__default}
  else
    read -r -p "  $__prompt: " __reply || true
  fi
  printf -v "$__var" '%s' "$__reply"
}

# ask_secret VAR "Question" — input isn't echoed
ask_secret() {
  local __var=$1 __prompt=$2 __reply
  read -r -s -p "  $__prompt: " __reply || true
  echo
  printf -v "$__var" '%s' "$__reply"
}

# confirm "Question" [Y|N] — returns 0 for yes
confirm() {
  local __default=${2:-Y} __reply __hint='[Y/n]'
  [ "$__default" = N ] && __hint='[y/N]'
  read -r -p "  $1 $__hint " __reply || true
  __reply=${__reply:-$__default}
  [[ $__reply =~ ^[Yy] ]]
}

# Answers filled in by ask/ask_secret (declared here so it's clear where they come from)
ai_choice='' key='' m='' u='' v='' admin_user='' backup_dir='' sso_issuer='' sso_id='' sso_secret=''

gen_secret() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 32
  else head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; fi
}

port_in_use() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$1\$"
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    return 1
  fi
}

server_ip() {
  hostname -I 2>/dev/null | awk '{print $1}' || true
}

# ── .env helpers (values are passed through the environment, so no escaping issues) ──
ENV_FILE="$REPO_DIR/.env"

env_get() {
  [ -f "$ENV_FILE" ] || return 0
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

# env_set KEY VALUE — replaces KEY=… in .env, or appends it
env_set() {
  local tmp
  tmp=$(mktemp)
  KEY="$1" VAL="$2" awk '
    BEGIN { key = ENVIRON["KEY"]; val = ENVIRON["VAL"]; done = 0 }
    index($0, key "=") == 1 { print key "=" val; done = 1; next }
    { print }
    END { if (!done) print key "=" val }
  ' "$ENV_FILE" > "$tmp"
  cat "$tmp" > "$ENV_FILE"
  rm -f "$tmp"
}

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

ENV_ONLY=0
for arg in "$@"; do
  case $arg in
    --env-only) ENV_ONLY=1 ;;
    -h|--help)  usage ;;
    *) die "Unknown option: $arg (see --help)" ;;
  esac
done

[ -f docker-compose.yml ] && [ -f .env.example ] || die "Run this from the Obelo folder (where docker-compose.yml is)."

printf '%sObelo installer%s\n' "$BOLD" "$RESET"
info "Each step asks before changing anything. Press Enter to accept the [default]."

# ── 1. Preflight ─────────────────────────────────────────────────────────────
step "Checking the system"
OS=$(uname -s)
if [ "$OS" != Linux ]; then
  warn "This is $OS; the installer is written for Linux servers. --env-only works anywhere."
  [ "$ENV_ONLY" = 1 ] || confirm "Continue anyway?" N || exit 1
else
  ok "Linux ($(uname -m))"
fi
for tool in curl awk sed; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is required but not installed."
done
command -v openssl >/dev/null 2>&1 || warn "openssl not found; using /dev/urandom for secrets."
SUDO=''
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 && SUDO='sudo'
fi
if [ "$ENV_ONLY" = 0 ]; then
  free_mb=$(df -Pm . | awk 'NR==2 {print $4}')
  if [ "${free_mb:-0}" -lt 3000 ]; then
    warn "Only ${free_mb} MB free here; building the image needs about 3 GB."
    confirm "Continue anyway?" N || exit 1
  else
    ok "$((free_mb / 1024)) GB free disk space"
  fi
fi

# ── 2. Docker ────────────────────────────────────────────────────────────────
DOCKER=(docker)
if [ "$ENV_ONLY" = 0 ]; then
  step "Docker"
  if ! command -v docker >/dev/null 2>&1; then
    warn "Docker isn't installed."
    info "It can be installed with Docker's official script (https://get.docker.com)."
    confirm "Install Docker now? (uses sudo)" || die "Docker is required. Install it, then re-run ./install.sh"
    curl -fsSL https://get.docker.com | $SUDO sh
    if [ -n "$SUDO" ]; then
      $SUDO usermod -aG docker "$USER" && ok "Added $USER to the docker group (takes effect at your next login)"
    fi
  fi
  if ! docker info >/dev/null 2>&1; then
    if [ -n "$SUDO" ] && $SUDO docker info >/dev/null 2>&1; then
      DOCKER=("$SUDO" docker)
      info "Using sudo for Docker for now (log out and back in to use it without sudo)."
    else
      die "Docker is installed but not running. Start it (e.g. 'sudo systemctl start docker') and re-run."
    fi
  fi
  "${DOCKER[@]}" compose version >/dev/null 2>&1 || die "The Docker Compose plugin is missing. Install 'docker-compose-plugin' and re-run."
  ok "$("${DOCKER[@]}" --version | cut -d, -f1), $("${DOCKER[@]}" compose version --short 2>/dev/null | sed 's/^/Compose /')"
fi
dc() { "${DOCKER[@]}" compose "$@"; }

# ── 3. Configuration (.env) ──────────────────────────────────────────────────
step "Configuration (.env)"
CREATED_ENV=0
if [ -f "$ENV_FILE" ]; then
  ok ".env already exists — leaving it as is"
else
  cp .env.example "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  CREATED_ENV=1

  db_pw=$(gen_secret)
  env_set POSTGRES_PASSWORD "$db_pw"
  env_set DATABASE_URL "postgresql://obelo:$db_pw@db:5432/obelo"
  env_set SESSION_SECRET "$(gen_secret)"
  env_set NOTE_LOCK_SECRET "$(gen_secret)"
  env_set UPLOADS_ENCRYPTION_KEY "$(gen_secret)"
  env_set CREDENTIALS_ENCRYPTION_KEY "$(gen_secret)"
  ok "Generated the database password and encryption keys"

  echo
  info "The public address people will use, e.g. https://obelo.example.com"
  ask app_url "Obelo URL" "https://obelo.example.com"
  app_url=${app_url%/}
  env_set APP_URL "$app_url"
  if [[ $app_url == https://* ]]; then
    env_set NODE_ENV production
  else
    warn "Without https://, login only works in development mode (secure cookies need HTTPS)."
    if confirm "Use development mode for now? (fine for trying it out on your network)"; then
      env_set NODE_ENV development
    else
      env_set NODE_ENV production
    fi
  fi

  app_port=3001
  while port_in_use "$app_port"; do app_port=$((app_port + 1)); done
  ask app_port "Port for Obelo on this server (your reverse proxy points here)" "$app_port"
  while port_in_use "$app_port"; do
    warn "Port $app_port is already in use."
    ask app_port "Choose another port" "$((app_port + 1))"
  done
  env_set APP_PORT "$app_port"

  # AI
  echo
  if confirm "Set up AI features (AI Chat and natural-language Capture)?" N; then
    info "1) Anthropic (Claude)   2) OpenAI   3) Local / OpenAI-compatible (Ollama, LM Studio, …)"
    ask ai_choice "Provider" "1"
    case $ai_choice in
      2) env_set AI_PROVIDER openai
         ask_secret key "OpenAI API key"; env_set AI_API_KEY "$key"
         info "Enter model IDs from your OpenAI account's model list."
         ask m "Chat model"; env_set AI_CHAT_MODEL "$m"
         ask m "Capture model (a small, fast one is fine)" "$m"; env_set AI_CAPTURE_MODEL "$m" ;;
      3) env_set AI_PROVIDER openai-compatible
         ask u "Server URL" "http://$(server_ip):11434/v1"; env_set AI_BASE_URL "$u"
         ask_secret key "API key (leave blank if none)"; env_set AI_API_KEY "$key"
         ask m "Chat model" "llama3.1:8b"; env_set AI_CHAT_MODEL "$m"
         ask m "Capture model" "$m"; env_set AI_CAPTURE_MODEL "$m"
         info "Tip: raise your model server's context window (see the README's AI section)." ;;
      *) env_set AI_PROVIDER anthropic
         ask_secret key "Anthropic API key"; env_set AI_API_KEY "$key"
         ask m "Chat model" "claude-sonnet-5"; env_set AI_CHAT_MODEL "$m"
         ask m "Capture model" "claude-haiku-4-5"; env_set AI_CAPTURE_MODEL "$m" ;;
    esac
    ok "AI configured"
  fi

  # Email
  if confirm "Set up email (SMTP) for reminder emails and the daily digest?" N; then
    ask v "SMTP host" "smtp.example.com"; env_set SMTP_HOST "$v"
    ask v "SMTP port" "587"; env_set SMTP_PORT "$v"
    if [ "$v" = 465 ]; then env_set SMTP_SECURE true; else env_set SMTP_SECURE false; fi
    ask v "SMTP username"; env_set SMTP_USER "$v"
    ask_secret v "SMTP password"; env_set SMTP_PASS "$v"
    ask v "From address" "$(env_get SMTP_USER)"; env_set SMTP_FROM "$v"
    ok "Email configured"
  fi

  # Pushover
  if confirm "Set up Pushover (paid push app)? ntfy, the free option, comes next." N; then
    ask v "Pushover application token"; env_set PUSHOVER_APP_TOKEN "$v"
    ok "Pushover configured (each user adds their own user key in Settings)"
  fi

  # SSO (optional: people can always sign in with a username and password)
  echo
  info "People sign in with a username and password. Single sign-on (any"
  info "OpenID Connect provider) is optional and adds a button to the login page."
  if confirm "Set up single sign-on now?" N; then
    info "Use this redirect URI in your provider: $app_url/auth/oidc/callback"
    ask sso_issuer "Issuer URL (e.g. https://auth.example.com/application/o/obelo/)"
    ask sso_id "Client ID"
    ask_secret sso_secret "Client secret"
    if [ -n "$sso_issuer" ] && [ -n "$sso_id" ] && [ -n "$sso_secret" ]; then
      env_set OIDC_ISSUER "$sso_issuer"
      env_set OIDC_CLIENT_ID "$sso_id"
      env_set OIDC_CLIENT_SECRET "$sso_secret"
      ok "Single sign-on configured"
    else
      warn "Something was left blank, so single sign-on was skipped. Add the OIDC_* settings to .env later."
    fi
  fi

  # Google Calendar
  if confirm "Set up Google Calendar sync?" N; then
    info "Use this redirect URI in Google Cloud Console: $app_url/calendar/auth/google/callback"
    ask v "Google OAuth client ID"; env_set GOOGLE_CLIENT_ID "$v"
    ask_secret v "Google OAuth client secret"; env_set GOOGLE_CLIENT_SECRET "$v"
    ok "Google Calendar configured"
  fi

  ok "Wrote .env (permissions 600). Change any setting later by editing it."
fi

if [ "$ENV_ONLY" = 1 ]; then
  echo
  ok "Done (--env-only). Start Obelo with: docker compose up -d --build (or docker compose pull app && docker compose up -d, once a release image exists)"
  exit 0
fi

APP_URL=$(env_get APP_URL)
APP_PORT=$(env_get APP_PORT); APP_PORT=${APP_PORT:-3001}
IP=$(server_ip); IP=${IP:-<server-ip>}
# APP_PORT may include a bind address (e.g. 127.0.0.1:3001): use that host, and the bare port
if [[ $APP_PORT == *:* ]]; then IP=${APP_PORT%:*}; APP_PORT=${APP_PORT##*:}; fi

# ── 4. ntfy (optional) ───────────────────────────────────────────────────────
step "Push notifications with ntfy (free, optional)"
NTFY_URL_SET=$(env_get NTFY_URL)
NTFY_DIR="$HOME/ntfy"
NTFY_PORT=''
NTFY_PUBLIC=''
if [ -n "$NTFY_URL_SET" ]; then
  ok "ntfy is already configured ($NTFY_URL_SET)"
elif confirm "Set up a self-hosted ntfy server? (free push notifications; needs its own subdomain)" N; then
  default_host=$(echo "$APP_URL" | sed -E 's#^(https?://)[^.]+\.#\1ntfy.#')
  ask NTFY_PUBLIC "Public ntfy URL" "$default_host"
  NTFY_PUBLIC=${NTFY_PUBLIC%/}
  ask NTFY_DIR "Folder for ntfy (kept separate from Obelo)" "$NTFY_DIR"
  NTFY_PORT=2586
  while port_in_use "$NTFY_PORT"; do NTFY_PORT=$((NTFY_PORT + 1)); done
  ask NTFY_PORT "Port for ntfy on this server (your reverse proxy points here)" "$NTFY_PORT"
  while port_in_use "$NTFY_PORT"; do
    warn "Port $NTFY_PORT is already in use."
    ask NTFY_PORT "Choose another port" "$((NTFY_PORT + 1))"
  done

  if [ -f "$NTFY_DIR/compose.yml" ]; then
    warn "$NTFY_DIR/compose.yml already exists — using it as is."
  else
    mkdir -p "$NTFY_DIR"
    cat > "$NTFY_DIR/compose.yml" <<EOF
# ntfy push notification server for Obelo (created by Obelo's install.sh)
services:
  ntfy:
    image: binwiederhier/ntfy
    command: serve
    restart: unless-stopped
    ports:
      - "$NTFY_PORT:80"
    volumes:
      - ./server.yml:/etc/ntfy/server.yml:ro
      - cache:/var/cache/ntfy
      - lib:/var/lib/ntfy
    healthcheck:
      test: ["CMD-SHELL", "wget -q --tries=1 http://localhost:80/v1/health -O - | grep -Eo \"\\\\\"healthy\\\\\"\\\\s*:\\\\s*true\" || exit 1"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 20s

volumes:
  cache:
  lib:
EOF
    cat > "$NTFY_DIR/server.yml" <<EOF
base-url: "$NTFY_PUBLIC"
behind-proxy: true
cache-file: "/var/cache/ntfy/cache.db"
cache-duration: "12h"
auth-file: "/var/lib/ntfy/user.db"
# Nobody can publish or read unless allowed (Obelo publishes; phones read vt-* topics)
auth-default-access: "deny-all"
# Instant notifications on iPhone: relays a wake-up signal (message ID only) via ntfy.sh
upstream-base-url: "https://ntfy.sh"
EOF
    ok "Created $NTFY_DIR/compose.yml and server.yml"
  fi

  ( cd "$NTFY_DIR" && dc up -d ) >/dev/null
  for _ in $(seq 1 30); do
    curl -fsS "http://127.0.0.1:$NTFY_PORT/v1/health" 2>/dev/null | grep -q '"healthy":true' && break
    sleep 2
  done
  curl -fsS "http://127.0.0.1:$NTFY_PORT/v1/health" 2>/dev/null | grep -q '"healthy":true' \
    || die "ntfy didn't start. Check: cd $NTFY_DIR && docker compose logs"
  ok "ntfy is running on port $NTFY_PORT"

  # Runs the ntfy CLI inside the container: ntfy_cli [exec options…] -- <ntfy args…>
  ntfy_cli() {
    local opts=()
    while [ "$1" != -- ]; do opts+=("$1"); shift; done
    shift
    ( cd "$NTFY_DIR" && dc exec -T "${opts[@]}" ntfy ntfy "$@" )
  }
  if ! ntfy_cli -- user list 2>/dev/null | grep -q '^user obelo'; then
    ntfy_cli -e NTFY_PASSWORD="$(gen_secret)" -- user add --role=user obelo >/dev/null
  fi
  ntfy_cli -- access obelo 'vt-*' write-only >/dev/null
  ntfy_cli -- access everyone 'vt-*' read-only >/dev/null
  token=$(ntfy_cli -- token add obelo 2>&1 | grep -oE 'tk_[A-Za-z0-9]+' | head -n 1)
  [ -n "$token" ] || die "Couldn't create the ntfy token. Check: cd $NTFY_DIR && docker compose logs"
  env_set NTFY_URL "$NTFY_PUBLIC"
  env_set NTFY_TOKEN "$token"
  ok "Locked ntfy down (only Obelo can publish) and added its token to .env"
fi

# ── 5. Start Obelo ───────────────────────────────────────────────────────
step "Starting Obelo"
if confirm "Start Obelo now? (it downloads the ready-made app if there is one, otherwise it builds it, which takes a few minutes)"; then
  if dc pull app >/dev/null 2>&1; then
    ok "Downloaded the ready-made Obelo image"
    dc up -d
  else
    info "No ready-made image available, building Obelo from the code (a few minutes)…"
    dc up -d --build
  fi
  info "Waiting for Obelo to answer on port $APP_PORT…"
  for _ in $(seq 1 90); do
    curl -fs -o /dev/null "http://127.0.0.1:$APP_PORT/auth/login" && break
    sleep 2
  done
  if curl -fs -o /dev/null "http://127.0.0.1:$APP_PORT/auth/login"; then
    ok "Obelo is running"
    dc logs app 2>/dev/null | grep -E 'AI provider|AI disabled|Uploads:|WARNING' | sed 's/^[^|]*| */    /' | tail -n 4 || true
  else
    die "Obelo didn't come up. Check: docker compose logs app"
  fi
else
  warn "Skipped. Start it later with: docker compose up -d --build"
fi

# ── 6. First admin ───────────────────────────────────────────────────────────
step "Admin account"
if curl -fs -o /dev/null "http://127.0.0.1:$APP_PORT/auth/login"; then
  info "Create the first (admin) account in your browser: a one-time setup page at"
  info "  ${BOLD}$APP_URL/auth/setup${RESET}   (once your reverse proxy is in place; see below)"
  if [ -n "$(env_get OIDC_ISSUER)" ]; then
    info "Or make someone who signs in with single sign-on the admin instead. That replaces the setup page."
    if confirm "Create an admin from an SSO email now?" N; then
      ask admin_user "The email on their SSO account"
      if [ -n "$admin_user" ]; then
        dc exec app node scripts/make-admin.js "$admin_user" || warn "That didn't work. You can still use the setup page, or run scripts/make-admin.js later."
      else
        warn "No email entered; skipped."
      fi
    fi
  fi
else
  warn "Obelo isn't running, so there is no admin account yet. Once it is, open $APP_URL/auth/setup."
fi

# ── 7. Backups (optional) ────────────────────────────────────────────────────
step "Nightly backups (database + uploaded files)"
if crontab -l 2>/dev/null | grep -qF "$REPO_DIR/scripts/backup.sh"; then
  ok "A nightly backup is already scheduled"
elif [ "${DOCKER[0]}" != docker ]; then
  warn "Backups run Docker without sudo, which works after you log out and back in."
  info "Then re-run ./install.sh to set them up (it skips everything already done)."
elif confirm "Schedule a nightly backup? (strongly recommended)"; then
  ask backup_dir "Backup folder (ideally a NAS or second disk)" "$HOME/obelo-backups"
  mkdir -p "$backup_dir"
  if "$REPO_DIR/scripts/backup.sh" "$backup_dir"; then
    line="15 3 * * * $REPO_DIR/scripts/backup.sh $backup_dir >> $HOME/obelo-backup.log 2>&1"
    # 'crontab -l' fails when the user has no crontab yet, so don't let it abort the script
    { crontab -l 2>/dev/null || true; echo "# Obelo nightly backup (database + uploads), keeps 14 days"; echo "$line"; } | crontab -
    ok "Test backup succeeded; scheduled daily at 03:15 (log: ~/obelo-backup.log)"
  else
    warn "The test backup failed, so nothing was scheduled. Fix the error above and re-run."
  fi
fi

# ── 8. Summary ───────────────────────────────────────────────────────────────
step "All set — remaining steps"
info "${BOLD}1. Point your reverse proxy at Obelo${RESET} (HTTPS required for login):"
info "     $APP_URL  →  http://$IP:$APP_PORT"
ntfy_url=$(env_get NTFY_URL)
if [ -n "$ntfy_url" ]; then
  info "     $ntfy_url  →  http://$IP:${NTFY_PORT:-2586}   ${DIM}(no login page in front of it)${RESET}"
fi
info "   Cloudflare Tunnel: add these as public hostnames (type HTTP). Caddy/nginx: see the README."
if [ "$CREATED_ENV" = 1 ]; then
  info "${BOLD}2. Save your keys${RESET} somewhere safe (a password manager). Backups don't include them,"
  info "   and without them locked notes, encrypted uploads and calendar logins can't be restored:"
  info "     grep -E '^(SESSION_SECRET|NOTE_LOCK_SECRET|UPLOADS_ENCRYPTION_KEY|CREDENTIALS_ENCRYPTION_KEY|POSTGRES_PASSWORD)=' $ENV_FILE"
fi
info "${BOLD}3. Create your admin account${RESET} at $APP_URL/auth/setup (or sign in, if you made one above), then explore Settings."
info "   Locked out later? docker compose exec app node scripts/set-password.js <username>"
info "Update later with: git pull && docker compose build app && docker compose up -d app"
info "   (or, to download the ready-made image instead of building: docker compose pull app && docker compose up -d app)"
echo
