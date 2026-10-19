# Monitoring agent package

Version 0.1.0 — first build. **Not yet installed on any cluster.** See "What is tested" below.

One Grafana Alloy pod that watches a client's websites, PostgreSQL and Redis from
inside their own AKS cluster and alerts to their Slack or Telegram. Optionally it
also reads Azure Monitor.

## What it does

- Looks at the client's subscription and cluster first and changes nothing (`action = check`).
- Uses the client's existing Prometheus and Grafana, or installs ours.
- Installs the agent with the client's list of addresses, databases and caches.
- Works without the Azure Monitor API. Azure Monitor is a tick box.
- Removes everything it installed with `action = remove`.

## Folder layout

| Path | What it is |
|---|---|
| `pipeline/install.yml` | The Azure DevOps pipeline: Discover, Plan, Approve, Apply, Verify |
| `scripts/discover.sh` | Read-only look at the subscription and cluster; decides existing or install |
| `scripts/verify.sh` | After install: is the agent running, is data arriving, test alert |
| `terraform/` | Root Terraform that wires the modules together |
| `terraform/modules/agent/` | The agent (Alloy), its configuration and secret |
| `terraform/modules/base-stack/` | Prometheus, Alertmanager, Grafana — only when the client has none |
| `terraform/modules/azure-monitor/` | Managed identity and read-only role — only for workload identity |
| `terraform/modules/content/` | Alert rules and dashboards |
| `clients/example-client.tfvars` | Template for the one file that differs per client |
| `docs/onboarding.md` | What the client must provide and how to run the pipeline |

## How to use it

1. Copy `clients/example-client.tfvars`, rename it for the client, fill it in.
2. Create the client's secret variable group (names in `docs/onboarding.md`).
3. Run the pipeline with `action = check`. Read the discovery report on the Summary tab.
4. Run with `action = install` and `dryRun` ticked. Read the plan.
5. Run with `dryRun` unticked and approve.

## What is tested, and what is not

| Part | State |
|---|---|
| Terraform | `terraform validate` passes. A plan was produced in both modes (install: 11 resources, existing: 9). Never applied |
| Agent configuration | The rendered configuration, with probes, PostgreSQL, Redis and all nine Azure blocks, passes `alloy validate` (v1.20.1) |
| Helm charts | Both charts render with the package's values (`helm template`) |
| `discover.sh` | Run against sample data for four cases. Not run against a real subscription |
| `verify.sh` | Syntax checked only |
| `pipeline/install.yml` | Parses as YAML. Never run in Azure DevOps |
| Azure Monitor metric names | Taken from memory of Azure's metric lists. Must be checked against Azure before use |

## Known limits in 0.1.0

- AKS only. No virtual-machine install, no AWS, no Google Cloud.
- "Install ours" needs a cluster with no Prometheus operator. Next to an existing one it is refused.
- Grafana can be installed only together with our Prometheus.
- Dashboards reach an existing Grafana only if it runs the dashboard sidecar.
- Alert routes (Slack, Telegram) are set only when we install Alertmanager. With an existing one, the client's routes apply.
- Azure Monitor reads a fixed list of nine resource types. "Every type in the subscription" is not built.
- No alert rules for the Azure Monitor metrics yet.
- The saved Terraform plan is kept as a pipeline artifact between stages and contains the secret values. Restrict who can read the pipeline's artifacts.
# eks-website-monitoring
