#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$ROOT_DIR"

source "$ROOT_DIR/common/utils.sh"

metadata_generate() {
  bash config-registry/generate-metadata.sh
}

is_managed_externally() {
  local domain="$1"
  local managed
  managed=$(yq -o=json ".domains[] | select(.name == \"$domain\") | .managed_externally // false" config-registry/env/domains.yml)
  managed=${managed//$'\n'/}
  [[ "$managed" == "true" ]]
}

metadata_diff() {
  local diff_found=0
  local domain
  for domain in $(yq '.domains[].name' config-registry/env/domains.yml); do
    if is_managed_externally "$domain"; then
      log_info "Skipping metadata diff for $domain (managed externally)"
      continue
    fi
    local cache="config-registry/state/metadata-cache/${domain}.yml"
    local canonical="domains/${domain}/metadata.yml"
    if [[ -f "$cache" && -f "$canonical" ]]; then
      if ! diff -u <(yq 'del(._meta.generated_at)' "$canonical") <(yq 'del(._meta.generated_at)' "$cache"); then
        diff_found=1
      fi
    elif [[ -f "$cache" && ! -f "$canonical" ]]; then
      log_warn "Missing metadata for $domain (new domain?)"
      diff_found=1
    fi
  done
  if (( diff_found == 0 )); then
    log_info "No metadata drift detected"
  fi
  return $diff_found
}

metadata_commit() {
  metadata_generate
  local domain
  for domain in $(yq '.domains[].name' config-registry/env/domains.yml); do
    if is_managed_externally "$domain"; then
      log_info "Skipping metadata commit for $domain (managed externally)"
      continue
    fi
    local cache="config-registry/state/metadata-cache/${domain}.yml"
    local target="domains/${domain}/metadata.yml"
    if [[ -f "$cache" ]]; then
      mkdir -p "$(dirname "$target")"
      if [[ ! -f "$target" ]]; then
        cp "$cache" "$target"
        log_info "Updated $target"
      elif ! cmp -s "$cache" "$target"; then
        cp "$cache" "$target"
        log_info "Updated $target"
      else
        log_info "No changes for $domain"
      fi
    fi
  done
}

metadata_check() {
  metadata_generate
  if ! metadata_diff; then
    log_error "Metadata drift detected"
    return 1
  fi
  return 0
}

usage() {
  cat <<USAGE
Usage: $0 {generate|diff|commit|check}
USAGE
}

command="${1:-}"
case "$command" in
  generate)
    metadata_generate
    ;;
  diff)
    metadata_diff
    ;;
  commit)
    metadata_commit
    ;;
  check)
    metadata_check
    ;;
  *)
    usage
    exit 1
    ;;
esac
