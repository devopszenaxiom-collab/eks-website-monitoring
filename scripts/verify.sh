#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# verify.sh — after an install, check that the agent is running and its data
# is arriving in Prometheus. Optionally send one test alert.
#
# Read-only unless --send-test-alert is given, which posts a single alert named
# MonitoringAgentTestAlert to Alertmanager; it reaches the client's Slack as a
# warning and resolves by itself after 5 minutes.
#
# Usage:
#   verify.sh --namespace monitoring --prometheus-service zmon-prometheus \
#             --jobs "alloy blackbox postgres-exporter redis-exporter" \
#             [--prometheus-namespace <ns>] [--alertmanager-service zmon-alertmanager] \
#             [--send-test-alert] [--kubeconfig <path>]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

NAMESPACE="monitoring" PROM_NS="" PROM_SVC="" AM_SVC="" JOBS="" SEND_ALERT=false KUBECONFIG_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)            NAMESPACE="$2"; shift 2 ;;
    --prometheus-namespace) PROM_NS="$2"; shift 2 ;;
    --prometheus-service)   PROM_SVC="$2"; shift 2 ;;
    --alertmanager-service) AM_SVC="$2"; shift 2 ;;
    --jobs)                 JOBS="$2"; shift 2 ;;
    --send-test-alert)      SEND_ALERT=true; shift ;;
    --kubeconfig)           KUBECONFIG_PATH="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$PROM_SVC" && -n "$JOBS" ]] || { echo "Required: --prometheus-service and --jobs" >&2; exit 2; }
[[ -n "$KUBECONFIG_PATH" ]] && export KUBECONFIG="$KUBECONFIG_PATH"
PROM_NS="${PROM_NS:-$NAMESPACE}"
FAILED=0
ok()   { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILED=1; }

# Ask Prometheus through the Kubernetes API, so nothing has to be exposed.
query() {
  kubectl get --raw "/api/v1/namespaces/$PROM_NS/services/$PROM_SVC:9090/proxy/api/v1/query?query=$(jq -rn --arg q "$1" '$q|@uri')" \
    | jq -r '.data.result | length'
}

echo "1. Agent pod"
if kubectl -n "$NAMESPACE" rollout status deployment/monitoring-agent --timeout=180s >/dev/null 2>&1; then
  ok "monitoring-agent is running"
else
  fail "monitoring-agent did not become ready in 3 minutes"
fi

echo "2. Data arriving in Prometheus (waits up to 3 minutes per job)"
for job in $JOBS; do
  found=0
  for _ in $(seq 1 18); do
    if [[ "$(query "up{job=\"$job\"} == 1" 2>/dev/null || echo 0)" -gt 0 ]]; then found=1; break; fi
    sleep 10
  done
  if [[ $found -eq 1 ]]; then ok "job $job is reporting"; else fail "no data from job $job"; fi
done

echo "3. Checks that are failing right now (for information)"
for q in 'probe_success == 0' 'pg_up == 0' 'redis_up == 0'; do
  n=$(query "$q" 2>/dev/null || echo "?")
  echo "  INFO  $q -> $n series"
done

echo "4. Samples rejected by Prometheus"
if [[ "$(query 'rate(prometheus_remote_storage_samples_failed_total{job="alloy"}[5m]) > 0' 2>/dev/null || echo 0)" -eq 0 ]]; then
  ok "none rejected"
else
  fail "Prometheus is rejecting samples from the agent"
fi

if [[ "$SEND_ALERT" == "true" ]]; then
  echo "5. Test alert"
  if [[ -z "$AM_SVC" ]]; then
    fail "--send-test-alert needs --alertmanager-service"
  else
    ends=$(date -u -v+5M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ)
    body=$(jq -n --arg ends "$ends" '[{
      labels: { alertname: "MonitoringAgentTestAlert", severity: "warning" },
      annotations: { summary: "Test alert from the monitoring agent install",
                     description: "If you can read this, alerts reach this channel. It resolves by itself in 5 minutes." },
      endsAt: $ends }]')
    if echo "$body" | kubectl create --raw "/api/v1/namespaces/$PROM_NS/services/$AM_SVC:9093/proxy/api/v2/alerts" -f - >/dev/null 2>&1; then
      ok "test alert sent; confirm it arrived in the warning channel"
    else
      fail "could not send the test alert"
    fi
  fi
fi

if [[ $FAILED -eq 0 ]]; then echo "All checks passed."; else echo "Some checks failed."; exit 1; fi
