# Onboarding a client

## 1. What the client must provide

- A service connection to their subscription.
  - For `action = check`: the Reader role and read access to the cluster.
  - For `action = install`: rights to create objects in the cluster.
  - For Azure Monitor with workload identity: also the right to create a role assignment.
- A storage account and container for the Terraform state, ideally in their subscription.
- The list of web addresses and ports to check.
- For each PostgreSQL server: the host name and a read-only login.
- For each Redis cache: the host name, port and an access key.
- Slack webhook(s) and channel names, and Telegram details if wanted.
- A network path from the cluster to every address, database and cache above.

### Read-only PostgreSQL login

Run once on each server, as an administrator:

```sql
CREATE ROLE monitoring WITH LOGIN PASSWORD '<a strong password>';
GRANT pg_monitor TO monitoring;
```

## 2. The client file

Copy `clients/example-client.tfvars` to `clients/<client>.tfvars` and fill it in.
It holds names and addresses only. No passwords.

## 3. The secret variable group

Create one Azure DevOps variable group per client and mark every value as secret.
Leave out the ones the client does not use.

| Variable | Value |
|---|---|
| `PG_PASSWORDS_JSON` | `{"main":"<password>"}` — one entry per name in `postgres_targets` |
| `REDIS_PASSWORDS_JSON` | `{"main":"<access key>"}` — one entry per name in `redis_targets` |
| `SLACK_WEBHOOK_URL` | Webhook for critical alerts |
| `SLACK_WEBHOOK_URL_WARNING` | Webhook for warnings (optional; falls back to the critical one) |
| `TELEGRAM_BOT_TOKEN` | Bot token (optional) |
| `TELEGRAM_CHAT_ID` | Chat id (optional) |
| `AZURE_MONITOR_CLIENT_ID` | Service-principal sign-in only |
| `AZURE_MONITOR_TENANT_ID` | Service-principal sign-in only |
| `AZURE_MONITOR_CLIENT_SECRET` | Service-principal sign-in only |

## 4. Pipeline parameters

| Parameter | Meaning |
|---|---|
| Service connection, subscription id | Where to sign in |
| AKS resource group, cluster name | Where the agent runs |
| Namespace | Default `monitoring` |
| Client file | Path to the file from step 2 |
| Secret variable group | Name of the group from step 3 |
| Action | `check` reads only; `install` installs or upgrades; `remove` uninstalls |
| Dry run | Plan only |
| Prometheus and Alertmanager | `auto` uses theirs if found, else installs ours; `existing`; `install` |
| Grafana | `auto`, `existing`, `install`, `none` |
| Allow one setting change on an existing Prometheus | Switches on the receiver the agent writes to. Restarts their Prometheus once |
| Install our alert rules | On by default |
| Also read the Azure Monitor API | Off by default |
| Azure Monitor sign-in | `service_principal` changes nothing on the cluster; `workload_identity` stores no password but needs the cluster's OIDC issuer |
| Send one test alert after install | A warning that resolves by itself after 5 minutes |
| State storage | Resource group, storage account, container |

## 5. Order of runs

1. `action = check` — read the discovery report with the client and agree the choices.
2. `action = install`, dry run ticked — send the plan to the client.
3. `action = install`, dry run unticked — approve when the plan matches.
4. Confirm the test alert arrived.

## 6. Azure Monitor with a service principal

The client creates an app registration, gives it the **Monitoring Reader** role on the
subscription, and gives us its client id, tenant id and a secret. Nothing is created
in their Azure and nothing changes on their cluster.

## 7. Removing

Run with `action = remove`, dry run first. It removes what this package installed.
If the pipeline switched on the receiver on an existing Prometheus, that setting stays;
the client can switch it off again.
