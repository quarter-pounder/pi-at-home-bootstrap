#!/bin/bash
# Test Prometheus queries for runner status
# Usage: ./test-runner-queries.sh [PROMETHEUS_URL]

PROMETHEUS_URL="${1:-http://localhost:9090}"
# Remove trailing slash if present
PROMETHEUS_URL="${PROMETHEUS_URL%/}"

echo "Testing Prometheus queries for runner status..."
echo "Prometheus URL: $PROMETHEUS_URL"
echo ""

# Helper function to query and display
query_prom() {
    local query="$1"
    local desc="$2"
    echo "Query: $desc"
    echo "Expression: $query"
    local response=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=$(echo "$query" | sed 's/ /%20/g' | sed 's/>/%3E/g' | sed 's/</%3C/g' | sed 's/=/%3D/g' | sed 's/{/%7B/g' | sed 's/}/%7D/g' | sed 's/\[/%5B/g' | sed 's/\]/%5D/g' | sed 's/|/%7C/g' | sed 's/+/%2B/g' | sed 's/,/%2C/g' | sed 's/:/%3A/g' | sed 's/\//%2F/g')")

    # Check if response is valid JSON
    if echo "$response" | jq . >/dev/null 2>&1; then
        if echo "$response" | jq -e '.status' >/dev/null 2>&1; then
            if [ "$(echo "$response" | jq -r '.status')" = "success" ]; then
                local result_count=$(echo "$response" | jq '.data.result | length')
                if [ "$result_count" -eq 0 ]; then
                    echo "  Result: No data (empty result set)"
                else
                    echo "$response" | jq -r '.data.result[] | "  Value: \(.value[1]) (timestamp: \(.value[0]))"'
                fi
            else
                echo "  Error: $(echo "$response" | jq -r '.error // .errorType // "Unknown error"')"
                echo "$response" | jq '.'
            fi
        else
            echo "  Invalid response format:"
            echo "$response" | head -20
        fi
    else
        echo "  Invalid JSON response:"
        echo "$response" | head -20
    fi
    echo ""
}

# Test queries
echo "=== 1. Woodpecker Runner ==="
query_prom 'count(container_last_seen{job="cadvisor",container_label_com_docker_compose_service="woodpecker-runner"} > (time() - 300))' "Container last seen count"
query_prom '(count(container_last_seen{job="cadvisor",container_label_com_docker_compose_service="woodpecker-runner"} > (time() - 300)) > 0) or vector(0)' "Status check with fallback"
query_prom 'sum(rate(container_cpu_usage_seconds_total{job="cadvisor",container_label_com_docker_compose_service="woodpecker-runner"}[2m]))' "CPU usage"

echo "=== 2. Forgejo Actions Runner ==="
query_prom 'count(container_last_seen{job="cadvisor",container_label_com_docker_compose_service="forgejo-actions-runner"} > (time() - 300))' "Container last seen count"
query_prom '(count(container_last_seen{job="cadvisor",container_label_com_docker_compose_service="forgejo-actions-runner"} > (time() - 300)) > 0) or vector(0)' "Status check with fallback"
query_prom 'sum(rate(container_cpu_usage_seconds_total{job="cadvisor",container_label_com_docker_compose_service="forgejo-actions-runner"}[2m]))' "CPU usage"

echo "=== 3. GitHub Actions Runner ==="
query_prom 'count(container_last_seen{job="cadvisor",container_label_com_docker_compose_service="github-actions-runner"} > (time() - 300))' "Container last seen count"
query_prom '(count(container_last_seen{job="cadvisor",container_label_com_docker_compose_service="github-actions-runner"} > (time() - 300)) > 0) or vector(0)' "Status check with fallback"

echo "=== 4. External Runner ==="
query_prom 'up{job="external-runner"}' "Up status"
query_prom 'sum(rate(node_cpu_seconds_total{job="external-runner",mode!="idle"}[2m]))' "CPU usage (non-idle)"
query_prom '(sum(rate(node_cpu_seconds_total{job="external-runner",mode!="idle"}[2m])) or vector(0)) >= 0.1' "CPU >= 0.1 comparison (returns nothing if false)"
query_prom '(sum(rate(node_cpu_seconds_total{job="external-runner",mode!="idle"}[2m])) or vector(0)) >= bool 0.1' "CPU >= 0.1 with bool (returns 0 or 1)"
query_prom '(max(up{job="external-runner"}) or vector(0)) * (1 + ((sum(rate(node_cpu_seconds_total{job="external-runner",mode!="idle"}[2m])) or vector(0)) >= bool 0.1))' "Full status expression with bool"

echo "=== 5. Table queries (with label_replace) ==="
query_prom 'label_replace((count(container_last_seen{job="cadvisor",container_label_com_docker_compose_service="woodpecker-runner"} > (time() - 300)) > 0) or vector(0), "runner", "Woodpecker Runner", "", "")' "Woodpecker with label_replace"
query_prom 'label_replace((count(container_last_seen{job="cadvisor",container_label_com_docker_compose_service="forgejo-actions-runner"} > (time() - 300)) > 0) or vector(0), "runner", "Forgejo Actions Runner", "", "")' "Forgejo with label_replace"
query_prom 'label_replace(max(up{job="external-runner"}) or vector(0), "runner", "External Runner", "", "")' "External with max and label_replace"
query_prom 'label_replace(up{job="external-runner"} or vector(0), "runner", "External Runner", "", "")' "External without max"

echo "=== 6. Check if containers exist ==="
query_prom 'container_last_seen{job="cadvisor",container_label_com_docker_compose_service=~"woodpecker-runner|forgejo-actions-runner|github-actions-runner"}' "All container_last_seen metrics"

echo "=== 6. Test edge cases ==="
query_prom '(sum(rate(container_cpu_usage_seconds_total{job="cadvisor",container_label_com_docker_compose_service="woodpecker-runner"}[2m])) or vector(0)) >= bool 0.1' "CPU comparison with bool when container missing"
query_prom '((count(container_last_seen{job="cadvisor",container_label_com_docker_compose_service="woodpecker-runner"} > (time() - 300)) > 0) or vector(0)) * (1 + ((sum(rate(container_cpu_usage_seconds_total{job="cadvisor",container_label_com_docker_compose_service="woodpecker-runner"}[2m])) or vector(0)) >= bool 0.1))' "Full Woodpecker expression"
query_prom '((count(container_last_seen{job="cadvisor",container_label_com_docker_compose_service="forgejo-actions-runner"} > (time() - 300)) > 0) or vector(0)) * (1 + ((sum(rate(container_cpu_usage_seconds_total{job="cadvisor",container_label_com_docker_compose_service="forgejo-actions-runner"}[2m])) or vector(0)) >= bool 0.1))' "Full Forgejo expression"

