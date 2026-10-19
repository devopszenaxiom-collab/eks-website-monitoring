#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# discover.sh — look at a client's subscription and cluster, change nothing.
#
# Reads what is running, decides how the package should be installed, and
# writes three files into the output directory:
#   discovery.json               everything that was found (machine readable)
#   discovery.md                 the report a person reads before approving
#   discovery.auto.tfvars.json   the choices, in the form Terraform takes
#
# Read-only: it only runs "list", "show" and "get" commands. It needs Reader on
# the subscription and read access to the cluster.
#
# Usage:
#   discover.sh --subscription <id> --resource-group <rg> --cluster <name> \
#               [--namespace monitoring] [--prometheus auto|existing|install] \
#               [--grafana auto|existing|install|none] [--out ./out] \
#               [--kubeconfig <path>]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SUBSCRIPTION="" RG="" CLUSTER="" NAMESPACE="monitoring"
PROM_CHOICE="auto" GRAFANA_CHOICE="auto" OUT="./out" KUBECONFIG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)   SUBSCRIPTION="$2"; shift 2 ;;
    --resource-group) RG="$2"; shift 2 ;;
    --cluster)        CLUSTER="$2"; shift 2 ;;
    --namespace)      NAMESPACE="$2"; shift 2 ;;
    --prometheus)     PROM_CHOICE="$2"; shift 2 ;;
    --grafana)        GRAFANA_CHOICE="$2"; shift 2 ;;
    --out)            OUT="$2"; shift 2 ;;
    --kubeconfig)     KUBECONFIG_PATH="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$SUBSCRIPTION" && -n "$RG" && -n "$CLUSTER" ]] || {
  echo "Required: --subscription, --resource-group, --cluster" >&2; exit 2; }
for tool in az kubectl jq; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 2; }
done
[[ -n "$KUBECONFIG_PATH" ]] && export KUBECONFIG="$KUBECONFIG_PATH"

mkdir -p "$OUT"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
k() { kubectl --request-timeout=30s "$@"; }
# Save a command's JSON output to a file; on any failure save the fallback
# instead of stopping, so one missing permission does not hide the rest.
save() { local file="$1" fallback="$2"; shift 2; "$@" > "$TMP/$file" 2>/dev/null || echo "$fallback" > "$TMP/$file"; }

echo "Reading subscription $SUBSCRIPTION ..." >&2
az account show --subscription "$SUBSCRIPTION" -o json > "$TMP/account.json"
az aks show --subscription "$SUBSCRIPTION" -g "$RG" -n "$CLUSTER" -o json > "$TMP/aks.json"
save resources.json '[]' az resource list --subscription "$SUBSCRIPTION" \
  --query "[].{type:type,name:name,rg:resourceGroup,location:location}" -o json
save postgres.json '[]' az postgres flexible-server list --subscription "$SUBSCRIPTION" \
  --query "[].{name:name,host:fullyQualifiedDomainName,version:version,state:state}" -o json
save redis.json '[]' az redis list --subscription "$SUBSCRIPTION" \
  --query "[].{name:name,host:hostName,port:sslPort,sku:sku.name}" -o json
save appgw.json '[]' az network application-gateway list --subscription "$SUBSCRIPTION" \
  --query "[].{name:name,rg:resourceGroup}" -o json
save public_ips.json '[]' az network public-ip list --subscription "$SUBSCRIPTION" \
  --query "[].{name:name,ip:ipAddress,fqdn:dnsSettings.fqdn}" -o json

echo "Reading cluster $CLUSTER ..." >&2
k get nodes -o json > "$TMP/nodes.json"
NS_EXISTS=$(k get namespace "$NAMESPACE" -o name >/dev/null 2>&1 && echo true || echo false)
HAS_CRD=$(k get crd prometheuses.monitoring.coreos.com -o name >/dev/null 2>&1 && echo true || echo false)
echo '{"items":[]}' > "$TMP/proms.json"; echo '{"items":[]}' > "$TMP/ams.json"
if [[ "$HAS_CRD" == "true" ]]; then
  save proms.json '{"items":[]}' k get prometheuses.monitoring.coreos.com -A -o json
  save ams.json   '{"items":[]}' k get alertmanagers.monitoring.coreos.com -A -o json
fi
save deploys.json '{"items":[]}' k get deployments -A -o json
save pods.json    '{"items":[]}' k get pods -A -o json

# ── Summarise ────────────────────────────────────────────────────────────────
jq -n \
  --arg namespace "$NAMESPACE" --arg prom_choice "$PROM_CHOICE" --arg grafana_choice "$GRAFANA_CHOICE" \
  --argjson ns_exists "$NS_EXISTS" --argjson has_crd "$HAS_CRD" \
  --slurpfile account "$TMP/account.json" --slurpfile resources "$TMP/resources.json" \
  --slurpfile aks "$TMP/aks.json" --slurpfile postgres "$TMP/postgres.json" \
  --slurpfile redis "$TMP/redis.json" --slurpfile appgw "$TMP/appgw.json" \
  --slurpfile public_ips "$TMP/public_ips.json" --slurpfile nodes "$TMP/nodes.json" \
  --slurpfile proms "$TMP/proms.json" --slurpfile ams "$TMP/ams.json" \
  --slurpfile deploys "$TMP/deploys.json" --slurpfile pods "$TMP/pods.json" '
  def cpu_m: if test("m$") then (.[:-1] | tonumber) else (tonumber * 1000) end;
  def mem_mi:
    if   test("Ki$") then (.[:-2] | tonumber) / 1024
    elif test("Mi$") then (.[:-2] | tonumber)
    elif test("Gi$") then (.[:-2] | tonumber) * 1024
    elif test("M$")  then (.[:-1] | tonumber) * 0.9537
    elif test("G$")  then (.[:-1] | tonumber) * 953.7
    else (tonumber / 1048576) end;

  $account[0] as $account | $resources[0] as $resources | $aks[0] as $aks
  | $postgres[0] as $postgres | $redis[0] as $redis | $appgw[0] as $appgw
  | $public_ips[0] as $public_ips | $nodes[0] as $nodes | $proms[0] as $proms
  | $ams[0] as $ams | $deploys[0] as $deploys | $pods[0] as $pods

  | ($proms.items | map({
      namespace: .metadata.namespace,
      name: .metadata.name,
      receiver: (.spec.enableRemoteWriteReceiver // false),
      replicas: (.spec.replicas // 1),
      rule_labels: (.spec.ruleSelector.matchLabels // {}),
      remote_write_url: "http://prometheus-operated.\(.metadata.namespace).svc:9090/api/v1/write"
    })) as $prom_list
  | ($deploys.items | map(select(
        (.metadata.labels["app.kubernetes.io/name"] // "") == "grafana"
        or (.metadata.name | test("grafana")))) | map({
      namespace: .metadata.namespace,
      name: .metadata.name,
      dashboard_sidecar: ([.spec.template.spec.containers[].name] | any(test("dashboard")))
    })) as $grafana_list
  | ($deploys.items | map(select(.metadata.name | test("blackbox|postgres-exporter|redis-exporter|alloy")))
      | map({namespace: .metadata.namespace, name: .metadata.name})) as $collectors
  | ([$nodes.items[].status.allocatable.cpu | cpu_m] | add // 0) as $alloc_cpu
  | ([$nodes.items[].status.allocatable.memory | mem_mi] | add // 0) as $alloc_mem
  | ([$pods.items[] | select(.status.phase == "Running") | .spec.containers[]
        | (.resources.requests.cpu // "0") | cpu_m] | add // 0) as $req_cpu
  | ([$pods.items[] | select(.status.phase == "Running") | .spec.containers[]
        | (.resources.requests.memory // "0") | mem_mi] | add // 0) as $req_mem

  # What the choices come to.
  | (if   $prom_choice == "install"  then "install"
     elif $prom_choice == "existing" then "existing"
     elif ($prom_list | length) >= 1 then "existing" else "install" end) as $prom_mode
  | (if   $grafana_choice != "auto"  then $grafana_choice
     elif ($grafana_list | length) >= 1 then "existing"
     elif $prom_mode == "install"    then "install" else "none" end) as $grafana_mode
  | ($prom_list[0] // null) as $prom

  | {
      subscription: { id: $account.id, name: $account.name },
      cluster: {
        name: $aks.name,
        version: $aks.kubernetesVersion,
        location: $aks.location,
        oidc_issuer: ($aks.oidcIssuerProfile.enabled // false),
        nodes: ($nodes.items | length),
        allocatable: { cpu_m: ($alloc_cpu | floor), memory_mi: ($alloc_mem | floor) },
        requested:   { cpu_m: ($req_cpu | floor),   memory_mi: ($req_mem | floor) },
        free:        { cpu_m: (($alloc_cpu - $req_cpu) | floor), memory_mi: (($alloc_mem - $req_mem) | floor) }
      },
      namespace: { name: $namespace, exists: $ns_exists },
      inventory: {
        total: ($resources | length),
        by_type: ($resources | group_by(.type) | map({type: .[0].type, count: length}) | sort_by(-.count))
      },
      suggested: {
        postgres: $postgres,
        redis: $redis,
        application_gateways: $appgw,
        public_addresses: ($public_ips | map(select(.fqdn != null or .ip != null)))
      },
      tools: {
        prometheus_operator: $has_crd,
        prometheus: $prom_list,
        alertmanager: ($ams.items | map({namespace: .metadata.namespace, name: .metadata.name})),
        grafana: $grafana_list,
        existing_collectors: $collectors
      },
      decisions: {
        prometheus_mode: $prom_mode,
        grafana_mode: $grafana_mode,
        create_namespace: ($ns_exists | not),
        existing_prometheus_remote_write_url: (if $prom_mode == "existing" then ($prom.remote_write_url // "") else "" end),
        existing_prometheus_rule_labels: (if $prom_mode == "existing" then ($prom.rule_labels // {}) else {} end)
      },
      problems: ([
        (if $prom_choice == "existing" and ($prom_list | length) == 0
           then "Use existing Prometheus was chosen, but no Prometheus was found in the cluster." else empty end),
        (if $prom_mode == "install" and $has_crd
           then "Install ours was chosen but a Prometheus operator is already in this cluster. Two operators in one cluster conflict, and this version does not support that. Choose Use existing." else empty end),
        (if $grafana_mode == "install" and $prom_mode == "existing"
           then "Installing Grafana is only supported together with installing Prometheus in this version. Use an existing Grafana, or none." else empty end),
        (if $prom_mode == "install" and (($alloc_mem - $req_mem) < 3072)
           then "Less than 3 GiB of unreserved memory in the cluster. Prometheus, Alertmanager and Grafana may not fit." else empty end),
        (if (($alloc_mem - $req_mem) < 512)
           then "Less than 512 MiB of unreserved memory in the cluster. The agent may not fit." else empty end)
      ]),
      warnings: ([
        (if $prom_mode == "existing" and ($prom_list | length) > 1
           then "More than one Prometheus was found. The first one is used; set existing_prometheus_remote_write_url in the client file to pick another." else empty end),
        (if $prom_mode == "existing" and ($prom != null) and ($prom.receiver | not)
           then "The existing Prometheus does not accept pushed data yet. It needs the remote-write receiver switched on, which restarts it once. Tick the setting-change parameter to let the pipeline do it." else empty end),
        (if ($collectors | length) > 0
           then "Collectors already run in this cluster (\($collectors | map(.name) | join(", "))). If they watch the same things as the agent, every alert will arrive twice." else empty end),
        (if $grafana_mode == "existing" and ($grafana_list | length) > 0 and ($grafana_list[0].dashboard_sidecar | not)
           then "The existing Grafana has no dashboard sidecar. Our dashboards will be created as ConfigMaps but must be imported by hand." else empty end),
        (if ($aks.oidcIssuerProfile.enabled // false) | not
           then "The cluster has no OIDC issuer. Azure Monitor can still be used with the service-principal sign-in; workload identity is not available." else empty end)
      ])
    }' > "$OUT/discovery.json"

jq '.decisions' "$OUT/discovery.json" > "$OUT/discovery.auto.tfvars.json"

# ── The report a person reads ────────────────────────────────────────────────
jq -r '
  "# Discovery report\n",
  "- Subscription: **\(.subscription.name)** (`\(.subscription.id)`)",
  "- Cluster: **\(.cluster.name)**, Kubernetes \(.cluster.version), \(.cluster.nodes) nodes, \(.cluster.location)",
  "- Unreserved capacity: \(.cluster.free.cpu_m)m CPU, \(.cluster.free.memory_mi) MiB memory",
  "- Namespace `\(.namespace.name)`: \(if .namespace.exists then "exists" else "will be created" end)",
  "- OIDC issuer: \(if .cluster.oidc_issuer then "on" else "off" end)\n",
  "## Monitoring tools found\n",
  "| Tool | Found | Detail |", "|---|---|---|",
  "| Prometheus | \(if (.tools.prometheus|length)>0 then "Yes" else "No" end) | \(.tools.prometheus | map("\(.namespace)/\(.name), accepts pushed data: \(.receiver)") | join("; ")) |",
  "| Alertmanager | \(if (.tools.alertmanager|length)>0 then "Yes" else "No" end) | \(.tools.alertmanager | map("\(.namespace)/\(.name)") | join("; ")) |",
  "| Grafana | \(if (.tools.grafana|length)>0 then "Yes" else "No" end) | \(.tools.grafana | map("\(.namespace)/\(.name)") | join("; ")) |",
  "| Collectors already running | \(if (.tools.existing_collectors|length)>0 then "Yes" else "No" end) | \(.tools.existing_collectors | map("\(.namespace)/\(.name)") | join("; ")) |\n",
  "## What this run will do\n",
  "- Prometheus and Alertmanager: **\(if .decisions.prometheus_mode == "install" then "install ours" else "use the existing one" end)**",
  "- Grafana: **\(.decisions.grafana_mode)**",
  (if .decisions.prometheus_mode == "existing" then "- The agent will write to `\(.decisions.existing_prometheus_remote_write_url)`" else empty end),
  "",
  "## Things that could be watched\n",
  "Suggestions only. Nothing is watched until it is in the client file.\n",
  "| Kind | Name | Address |", "|---|---|---|",
  (.suggested.postgres[] | "| PostgreSQL | \(.name) | \(.host) |"),
  (.suggested.redis[] | "| Redis | \(.name) | \(.host):\(.port) |"),
  (.suggested.application_gateways[] | "| Application Gateway | \(.name) | probe the sites behind it |"),
  (.suggested.public_addresses[] | "| Public address | \(.name) | \(.fqdn // .ip) |"),
  "",
  "## Resources in the subscription (\(.inventory.total))\n",
  "| Type | Count |", "|---|---|",
  (.inventory.by_type[] | "| \(.type) | \(.count) |"),
  "",
  "## Problems (the install stops on these)\n",
  (if (.problems|length)==0 then "None." else (.problems[] | "- \(.)") end),
  "",
  "## Warnings\n",
  (if (.warnings|length)==0 then "None." else (.warnings[] | "- \(.)") end)
' "$OUT/discovery.json" > "$OUT/discovery.md"

echo "Wrote $OUT/discovery.json, $OUT/discovery.md, $OUT/discovery.auto.tfvars.json" >&2
PROBLEMS=$(jq '.problems | length' "$OUT/discovery.json")
if [[ "$PROBLEMS" -gt 0 ]]; then
  echo "Discovery found $PROBLEMS problem(s); see $OUT/discovery.md" >&2
  exit 3
fi
