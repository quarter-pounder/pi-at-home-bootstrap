#!/usr/bin/env bash
set -euo pipefail

# This helper is intended to run directly on the host (cron/systemd) so that
# vcgencmd and /sys data can be collected without relying on a container.

TEXTFILE_DIR="${NODE_EXPORTER_TEXTFILE_DIR:-/srv/monitoring/node-exporter/textfile}"
OUTPUT_FILE="${TEXTFILE_DIR}/pi_telemetry.prom"
TMP_FILE="${OUTPUT_FILE}.tmp"

mkdir -p "${TEXTFILE_DIR}"

now() {
  date +%s
}

read_temperature() {
  local sys_path="/sys/class/thermal/thermal_zone0/temp"
  if [[ -f "${sys_path}" ]]; then
    local raw
    raw=$(cat "${sys_path}" 2>/dev/null || echo "")
    if [[ "${raw}" =~ ^[0-9]+$ ]]; then
      awk -v value="${raw}" 'BEGIN { printf "%.3f", value / 1000 }'
    fi
  fi
}

read_voltage() {
  if command -v vcgencmd >/dev/null 2>&1; then
    local vcgencmd_out
    vcgencmd_out=$(vcgencmd measure_volts core 2>/dev/null || true)
    if [[ "${vcgencmd_out}" =~ ([0-9]+\.[0-9]+)V ]]; then
      printf "%s" "${BASH_REMATCH[1]}"
    fi
  fi
}

render_throttle_flags() {
  if ! command -v vcgencmd >/dev/null 2>&1; then
    return
  fi

  local throttled_raw
  throttled_raw=$(vcgencmd get_throttled 2>/dev/null || true)
  if [[ ! "${throttled_raw}" =~ 0x([0-9a-fA-F]+) ]]; then
    return
  fi

  local mask_hex="${BASH_REMATCH[1]}"
  local mask_dec=$((16#${mask_hex}))

  declare -A FLAGS=(
    ["undervoltage_now"]=0x1
    ["frequency_capped_now"]=0x2
    ["throttled_now"]=0x4
    ["soft_temp_limit_now"]=0x8
    ["undervoltage_occurred"]=0x10000
    ["frequency_capped_occurred"]=0x20000
    ["throttled_occurred"]=0x40000
    ["soft_temp_limit_occurred"]=0x80000
  )

  for flag in "${!FLAGS[@]}"; do
    local flag_mask=${FLAGS["${flag}"]}
    local value=$(( (mask_dec & flag_mask) > 0 ? 1 : 0 ))
    printf 'pi_throttle_flags{flag="%s"} %d\n' "${flag}" "${value}"
  done
}

write_metrics() {
  local timestamp
  timestamp=$(now)
  local temperature
  temperature=$(read_temperature || true)
  local voltage
  voltage=$(read_voltage || true)

  {
    printf '# HELP pi_cpu_temperature_celsius Current SoC temperature in Celsius\n'
    printf '# TYPE pi_cpu_temperature_celsius gauge\n'
    printf 'pi_cpu_temperature_celsius %s\n' "${temperature:-NaN}"

    printf '# HELP pi_cpu_temperature_last_update_timestamp_seconds UNIX timestamp of last temperature sample\n'
    printf '# TYPE pi_cpu_temperature_last_update_timestamp_seconds gauge\n'
    printf 'pi_cpu_temperature_last_update_timestamp_seconds %s\n' "${timestamp}"

    printf '# HELP pi_core_voltage_volts Core voltage reported by vcgencmd\n'
    printf '# TYPE pi_core_voltage_volts gauge\n'
    printf 'pi_core_voltage_volts %s\n' "${voltage:-NaN}"

    printf '# HELP pi_core_voltage_last_update_timestamp_seconds UNIX timestamp of last voltage sample\n'
    printf '# TYPE pi_core_voltage_last_update_timestamp_seconds gauge\n'
    printf 'pi_core_voltage_last_update_timestamp_seconds %s\n' "${timestamp}"

    printf '# HELP pi_throttle_flags Raspberry Pi throttling & voltage status bits\n'
    printf '# TYPE pi_throttle_flags gauge\n'
    render_throttle_flags || printf 'pi_throttle_flags{flag="unknown"} NaN\n'

    printf '# HELP pi_throttle_last_update_timestamp_seconds UNIX timestamp of last throttle status sample\n'
    printf '# TYPE pi_throttle_last_update_timestamp_seconds gauge\n'
    printf 'pi_throttle_last_update_timestamp_seconds %s\n' "${timestamp}"
  } > "${TMP_FILE}"

  mv "${TMP_FILE}" "${OUTPUT_FILE}"
}

write_metrics

