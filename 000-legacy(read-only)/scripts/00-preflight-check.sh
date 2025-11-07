#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# --- Color (TTY-safe) ---
if [[ -t 1 ]]; then
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); BLUE=$(tput setaf 4); RESET=$(tput sgr0)
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

echo "Running pre-flight checks..."
echo ""

ERRORS=0
WARNINGS=0

# ---------- helpers ----------
ok()   { echo "${GREEN}✓${RESET} $*"; }
warn() { echo "${YELLOW}WARNING${RESET} $*"; ((WARNINGS++)); }
bad()  { echo "${RED}✗${RESET} $*"; ((ERRORS++)); }

need_cmd() {
  local c=$1; local pkg=${2:-$1}
  if command -v "$c" >/dev/null 2>&1; then ok "Command: $c"; else bad "Missing command: $c (install: $pkg)"; fi
}

bytes_free() { df -B1 "${1:-.}" | awk 'NR==2{print $4}'; }

# ---------- OS / arch / resources ----------
check_os() {
  if [[ ! -f /etc/os-release ]]; then bad "Cannot detect OS"; return; fi
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" == "ubuntu" ]]; then
    ok "OS: Ubuntu ${VERSION_ID:-unknown}"
  else
    warn "OS: ${ID:-unknown} ${VERSION_ID:-} (Ubuntu recommended)"
  fi
}

check_arch() {
  local a; a=$(uname -m)
  if [[ "$a" == "aarch64" ]]; then ok "Architecture: ARM64"; else bad "Architecture: $a (ARM64 required)"; fi
}

check_memory() {
  local mem_gb; mem_gb=$(free -g | awk '/^Mem:/{print $2}')
  if (( mem_gb >= 4 )); then ok "Memory: ${mem_gb}GB"; elif (( mem_gb >= 2 )); then warn "Memory: ${mem_gb}GB (4GB+ recommended)"; else bad "Memory: ${mem_gb}GB (insufficient)"; fi
}

check_disk() {
  local free_b; free_b=$(bytes_free .)
  if (( free_b >= 100000000000 )); then ok "Disk space: $((free_b/1024/1024/1024))GB available";
  elif (( free_b >= 20000000000 )); then warn "Disk space: $((free_b/1024/1024/1024))GB (50GB+ recommended)";
  else bad "Disk space: $((free_b/1024/1024/1024))GB (insufficient)"; fi
}

# ---------- connectivity / tools ----------
check_internet() {
  if curl -fsSL --max-time 5 https://github.com >/dev/null 2>&1 && \
     curl -fsSL --max-time 5 https://cdimage.ubuntu.com >/dev/null 2>&1; then
    ok "Internet connectivity"
  else
    bad "No reliable internet connectivity"
  fi
}

check_tools() {
  need_cmd curl curl
  need_cmd wget wget
  need_cmd envsubst gettext-base
  need_cmd dd coreutils
  need_cmd lsblk util-linux
  need_cmd blkdiscard util-linux
  need_cmd partprobe parted
  need_cmd rsync rsync
  need_cmd mkfs.vfat dosfstools || true
  need_cmd mkfs.ext4 e2fsprogs || true
  need_cmd pv pv || true
  need_cmd nvme nvme-cli || true
  need_cmd rpi-eeprom-config rpi-eeprom || true
  need_cmd vcgencmd "raspi-config/firmware tools" || true
}

# ---------- .env & cloud-init validation ----------
check_env_and_templates() {
  if [[ -f .env ]]; then
    ok ".env file exists"
    # export all .env vars so envsubst can see them
    set -a; # shellcheck disable=SC1091
    source .env; set +a

    # required variables for first boot
    local required=(HOSTNAME USERNAME SSH_PUBLIC_KEY TIMEZONE LOCALE UBUNTU_VERSION NVME_DEVICE GITLAB_ROOT_PASSWORD GRAFANA_ADMIN_PASSWORD)
    local missing=()
    for v in "${required[@]}"; do
      [[ -n "${!v:-}" ]] || missing+=("$v")
    done
    if (( ${#missing[@]} )); then bad "Missing required .env variables: ${missing[*]}"; else ok "Core .env variables present"; fi

    # basic key sanity
    if [[ "${SSH_PUBLIC_KEY:-}" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\s+[A-Za-z0-9+/=]+(\s+.+)?$ ]]; then
      ok "SSH public key format"
    else
      bad "SSH_PUBLIC_KEY looks invalid"
    fi

    # discourage defaults in production
    if [[ "${GITLAB_ROOT_PASSWORD:-change_this_secure_password}" == "change_this_secure_password" ]] || \
       [[ "${GRAFANA_ADMIN_PASSWORD:-change_this_secure_password}" == "change_this_secure_password" ]]; then
      warn "Default passwords detected (change before going live)"
    fi
  else
    bad ".env file not found"
    return
  fi

  # templates present?
  local tdir="cloudinit"
  local need=(user-data.template network-config.template meta-data.template)
  local missing_t=()
  for f in "${need[@]}"; do
    [[ -f "$tdir/$f" ]] || missing_t+=("$f")
  done
  if (( ${#missing_t[@]} )); then bad "Missing cloud-init templates: ${missing_t[*]}"; else ok "Cloud-init templates present"; fi

  # unresolved variables scan: list ${VAR} that have no default in template and not exported
  unresolved=0
  for tpl in "$tdir"/{user-data,network-config,meta-data}.template; do
    [[ -f "$tpl" ]] || continue
    # extract ${VAR} or ${VAR:-default}
    vars=$(grep -o '\${[A-Za-z_][A-Za-z0-9_:-]*}' "$tpl" | sed 's/[${}]//g' | cut -d:- -f1 | sort -u || true)
    for v in $vars; do
      if [[ -z "${!v:-}" ]]; then
        # check if template provides a default with :-
        if grep -q "\${$v:-" "$tpl"; then
          continue
        else
          echo "${YELLOW}TEMPLATE${RESET} $tpl: unresolved variable $v"
          unresolved=1
        fi
      fi
    done
  done
  (( unresolved == 0 )) && ok "Template variables resolved (or have defaults)" || warn "Some template variables rely on runtime defaults"
}

# ---------- sudo ----------
check_sudo() {
  if sudo -n true 2>/dev/null; then ok "Sudo access (passwordless)"
  elif sudo -v 2>/dev/null; then ok "Sudo access (with password)"
  else bad "No sudo access"; fi
}

# ---------- hardware / NVMe / EEPROM ----------
check_pi_model() {
  local model="unknown"
  [[ -f /proc/device-tree/model ]] && model=$(tr -d '\0' </proc/device-tree/model || true)
  echo "Detected model: ${BLUE}${model}${RESET}"
  if [[ "$model" != *"Raspberry Pi"* ]]; then warn "Non-Raspberry Pi environment detected"; fi
}

check_nvme() {
  local nvme="${NVME_DEVICE:-}"
  if [[ -z "$nvme" ]]; then
    # try auto-detect
    nvme=$(lsblk -dpno NAME,TYPE | awk '$2=="disk" && $1 ~ /nvme/ {print $1; exit}' || true)
  fi
  if [[ -z "$nvme" ]]; then bad "No NVMe device detected"; return; fi

  export NVME_DEVICE="$nvme"
  ok "NVMe device: $NVME_DEVICE"

  if lsblk -no SIZE "$NVME_DEVICE" | grep -q '^0B$'; then
    bad "NVMe appears as 0B (reseat drive / check power)"
  fi

  if command -v nvme >/dev/null 2>&1; then
    nvme smart-log "$NVME_DEVICE" >/dev/null 2>&1 && ok "NVMe SMART accessible" || warn "NVMe SMART not available"
  fi
}

check_eeprom() {
  if command -v rpi-eeprom-config >/dev/null 2>&1; then
    local cfg; cfg=$(rpi-eeprom-config 2>/dev/null || true)
    local order; order=$(grep -E '^BOOT_ORDER=' <<<"$cfg" | cut -d= -f2 || true)
    if [[ -n "$order" ]]; then
      echo "EEPROM BOOT_ORDER: ${BLUE}${order}${RESET}"
      if [[ "$order" != "0xf416" ]]; then
        warn "Recommended BOOT_ORDER for Pi 5 is 0xf416 (NVMe→USB→SD). Will be set during flash."
      else
        ok "EEPROM boot order already optimal"
      fi
    else
      warn "EEPROM BOOT_ORDER not found"
    fi
  else
    warn "rpi-eeprom-config not available; cannot verify boot order"
  fi
}

# ---------- run checks ----------
check_os
check_arch
check_memory
check_disk
check_internet
check_tools
check_sudo
check_pi_model

# Load .env if present (exporting for template checks)
if [[ -f .env ]]; then set -a; # shellcheck disable=SC1091
  source .env; set +a; fi
check_nvme
check_env_and_templates
check_eeprom

echo ""
if (( ERRORS == 0 )); then
  echo "${GREEN}✓ All checks passed.${RESET} Ready to proceed."
  if (( WARNINGS > 0 )); then
    echo "${YELLOW}Note:${RESET} $WARNINGS warning(s) reported."
  fi
  exit 0
else
  echo "${RED}✗ $ERRORS error(s) found.${RESET} Fix issues before continuing."
  if (( WARNINGS > 0 )); then
    echo "${YELLOW}Also:${RESET} $WARNINGS warning(s) reported."
  fi
  exit 1
fi
