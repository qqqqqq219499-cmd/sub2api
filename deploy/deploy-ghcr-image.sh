#!/usr/bin/env bash
set -euo pipefail

COMPOSE_DIR="/opt/sub2api"
SERVICE="sub2api"
HEALTH_URL="http://127.0.0.1:8080/health"
TIMEOUT_SECONDS=120
IMAGE=""
EXPECTED_VERSION=""
EXPECTED_COMMIT=""
SKIP_PULL=0

usage() {
  cat <<'EOF'
Usage:
  deploy-ghcr-image.sh --image ghcr.io/owner/sub2api:tag [options]

Options:
  --image <image>              Required target image.
  --compose-dir <dir>          Compose directory. Default: /opt/sub2api
  --service <name>             Compose service. Default: sub2api
  --health-url <url>           Health URL. Default: http://127.0.0.1:8080/health
  --expected-version <version> Optional version string expected from /app/sub2api --version.
  --expected-commit <sha>      Optional commit string expected from /app/sub2api --version.
  --timeout <seconds>          Health wait timeout. Default: 120
  --skip-pull                  Do not docker pull before switching.
  -h, --help                   Show this help.
EOF
}

log() {
  printf '[deploy] %s\n' "$*"
}

die() {
  printf '[deploy][error] %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --image)
      IMAGE="${2:-}"
      shift 2
      ;;
    --compose-dir)
      COMPOSE_DIR="${2:-}"
      shift 2
      ;;
    --service)
      SERVICE="${2:-}"
      shift 2
      ;;
    --health-url)
      HEALTH_URL="${2:-}"
      shift 2
      ;;
    --expected-version)
      EXPECTED_VERSION="${2:-}"
      shift 2
      ;;
    --expected-commit)
      EXPECTED_COMMIT="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --skip-pull)
      SKIP_PULL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ -n "$IMAGE" ] || die "--image is required"
[ -d "$COMPOSE_DIR" ] || die "compose directory not found: $COMPOSE_DIR"
[ -f "$COMPOSE_DIR/docker-compose.yml" ] || die "docker-compose.yml not found in $COMPOSE_DIR"
command -v docker >/dev/null 2>&1 || die "docker is not installed"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
command -v curl >/dev/null 2>&1 || die "curl is required"

FILE_SUDO=()
if [ ! -w "$COMPOSE_DIR" ] || [ ! -w "$COMPOSE_DIR/docker-compose.yml" ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    FILE_SUDO=(sudo)
  else
    die "compose files are not writable; run as root or configure passwordless sudo"
  fi
fi

DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    die "docker is not accessible; run as a docker-enabled user or configure passwordless sudo for docker"
  fi
fi

cd "$COMPOSE_DIR"

replace_image() {
  local compose_file="$1"
  local service="$2"
  local image="$3"
  local tmp_file
  tmp_file="$(mktemp)"
  python3 - "$compose_file" "$service" "$image" "$tmp_file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
service = sys.argv[2]
image = sys.argv[3]
tmp_path = Path(sys.argv[4])
lines = path.read_text().splitlines()
service_re = re.compile(rf"^  {re.escape(service)}:\s*$")
next_service_re = re.compile(r"^  [A-Za-z0-9_.-]+:\s*$")
image_re = re.compile(r"^(\s+image:\s*).*$")

in_service = False
old_image = None
changed = False
out = []
for line in lines:
    if service_re.match(line):
        in_service = True
        out.append(line)
        continue
    if in_service and next_service_re.match(line):
        in_service = False
    if in_service:
        match = image_re.match(line)
        if match:
            old_image = line.split("image:", 1)[1].strip()
            line = f"{match.group(1)}{image}"
            changed = True
    out.append(line)

if not changed:
    raise SystemExit(f"image line for service {service!r} not found")

tmp_path.write_text("\n".join(out) + "\n")
print(old_image or "")
PY
  "${FILE_SUDO[@]}" cp "$tmp_file" "$compose_file"
  rm -f "$tmp_file"
}

wait_healthy() {
  local service="$1"
  local timeout="$2"
  local deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -le "$deadline" ]; do
    local status
    status="$("${DOCKER[@]}" inspect "$service" --format '{{.State.Health.Status}}' 2>/dev/null || true)"
    log "health=${status:-unknown}"
    if [ "$status" = "healthy" ]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

rollback() {
  local old_image="$1"
  local backup="$2"
  log "rolling back to ${old_image}"
  "${FILE_SUDO[@]}" cp "$backup" docker-compose.yml
  "${DOCKER[@]}" compose up -d --no-deps --force-recreate "$SERVICE" || true
  wait_healthy "$SERVICE" 60 || true
}

if [ "$SKIP_PULL" -eq 0 ]; then
  log "pulling $IMAGE"
  "${DOCKER[@]}" pull "$IMAGE"
fi

BACKUP="docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)"
"${FILE_SUDO[@]}" cp docker-compose.yml "$BACKUP"
log "backup=$COMPOSE_DIR/$BACKUP"

OLD_IMAGE="$(replace_image docker-compose.yml "$SERVICE" "$IMAGE")"
log "old_image=$OLD_IMAGE"
log "new_image=$IMAGE"

if ! "${DOCKER[@]}" compose up -d --no-deps --force-recreate "$SERVICE"; then
  rollback "$OLD_IMAGE" "$BACKUP"
  die "docker compose up failed"
fi

if ! wait_healthy "$SERVICE" "$TIMEOUT_SECONDS"; then
  "${DOCKER[@]}" logs --tail 120 "$SERVICE" || true
  rollback "$OLD_IMAGE" "$BACKUP"
  die "service did not become healthy"
fi

if ! curl -fsS -m 10 "$HEALTH_URL" >/tmp/sub2api-health-check.out; then
  "${DOCKER[@]}" logs --tail 120 "$SERVICE" || true
  rollback "$OLD_IMAGE" "$BACKUP"
  die "health URL failed: $HEALTH_URL"
fi
log "health_url_ok=$(cat /tmp/sub2api-health-check.out)"

VERSION_OUTPUT="$("${DOCKER[@]}" exec "$SERVICE" /app/sub2api --version 2>&1 || true)"
printf '%s\n' "$VERSION_OUTPUT"

if [ -n "$EXPECTED_VERSION" ] && ! printf '%s' "$VERSION_OUTPUT" | grep -q "Sub2API ${EXPECTED_VERSION}"; then
  rollback "$OLD_IMAGE" "$BACKUP"
  die "expected version ${EXPECTED_VERSION} not found"
fi

if [ -n "$EXPECTED_COMMIT" ] && ! printf '%s' "$VERSION_OUTPUT" | grep -q "$EXPECTED_COMMIT"; then
  rollback "$OLD_IMAGE" "$BACKUP"
  die "expected commit ${EXPECTED_COMMIT} not found"
fi

log "deploy_ok image=$IMAGE backup=$COMPOSE_DIR/$BACKUP"
