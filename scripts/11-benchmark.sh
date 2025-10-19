#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RESET=$(tput sgr0)

echo "GitLab Performance Benchmark"
echo "============================="
echo ""

if ! docker ps | grep -q gitlab; then
  echo "GitLab is not running. Start it first."
  exit 1
fi

echo "${YELLOW}Running system benchmarks...${RESET}"
echo ""

echo "1. CPU Performance"
echo "   Running sysbench CPU test..."
if command -v sysbench >/dev/null; then
  sysbench cpu --cpu-max-prime=20000 run | grep "events per second"
else
  echo "   Installing sysbench..."
  sudo apt install -y sysbench >/dev/null 2>&1
  sysbench cpu --cpu-max-prime=20000 run | grep "events per second"
fi

echo ""
echo "2. Memory Performance"
sysbench memory --memory-total-size=2G run | grep "transferred"

echo ""
echo "3. Disk I/O Performance"
echo "   Testing /srv (GitLab data location)"
sudo sysbench fileio --file-total-size=1G prepare >/dev/null 2>&1
sudo sysbench fileio --file-total-size=1G --file-test-mode=rndrw run | grep -E "reads/s|writes/s"
sudo sysbench fileio --file-total-size=1G cleanup >/dev/null 2>&1

echo ""
echo "4. Docker Container Stats"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

echo ""
echo "5. GitLab Metrics"
if curl -sf http://localhost/-/health >/dev/null; then
  echo "   ${GREEN}✓${RESET} GitLab health check: OK"
else
  echo "   ${YELLOW}WARNING${RESET} GitLab health check: FAILED"
fi

echo ""
echo "6. System Info"
echo "   CPU: $(nproc) cores"
echo "   RAM: $(free -h | awk '/^Mem:/ {print $2}') total, $(free -h | awk '/^Mem:/ {print $3}') used"
echo "   Disk: $(df -h / | awk 'NR==2 {print $2}') total, $(df -h / | awk 'NR==2 {print $3}') used"
echo "   Temp: $(vcgencmd measure_temp | cut -d= -f2)"

echo ""
echo "7. GitLab Response Time Test"
echo "   Testing 10 requests to GitLab..."
for i in {1..10}; do
  curl -o /dev/null -s -w "%{time_total}s " http://localhost/-/health
done
echo ""

echo ""
echo "${GREEN}Benchmark complete!${RESET}"
echo ""
echo "Recommendations based on Pi 5 8GB:"
echo "  - CPU events/sec should be >500"
echo "  - Memory throughput should be >1000 MiB/sec"
echo "  - Disk read/write should be >50 MB/s (NVMe)"
echo "  - GitLab response time should be <1s"
echo "  - CPU temp should be <80°C under load"

