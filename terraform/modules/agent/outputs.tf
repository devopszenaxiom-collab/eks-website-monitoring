output "release_name" {
  value = helm_release.agent.name
}

output "jobs" {
  description = "Job labels this agent writes, for the verify step."
  value = compact([
    "alloy",
    length(local.http_probes) > 0 ? "blackbox" : "",
    length(local.tcp_probes) > 0 ? "blackbox-tcp" : "",
    length(var.postgres_targets) > 0 ? "postgres-exporter" : "",
    length(var.redis_targets) > 0 ? "redis-exporter" : "",
  ])
}
