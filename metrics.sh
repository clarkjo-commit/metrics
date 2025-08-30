#!/bin/bash

set -euo pipefail

echo "Gathering Cluster Resource Data..."

command -v jq >/dev/null || { echo "jq is required"; exit 1; }

if ! kubectl top nodes >/dev/null 2>&1; then
  echo "metrics-server not responding or not installed."
  exit 1
fi

# Allocatable Resources
alloc=$(kubectl get nodes -o json | jq -r '
  reduce .items[] as $node (
    {"cpu":0, "memory":0};
    . + {
      "cpu": (
        if $node.status.allocatable.cpu | test("m") then
          .cpu + ($node.status.allocatable.cpu | sub("m"; "") | tonumber)
        else
          .cpu + ($node.status.allocatable.cpu | tonumber * 1000)
        end
      ),
      "memory": (
        .memory + ($node.status.allocatable.memory | sub("Ki"; "") | tonumber)
      )
    }
  )')

ALLOC_CPU=$(echo "$alloc" | jq .cpu)
ALLOC_MEM=$(echo "$alloc" | jq .memory)

# Requested and Limited Resources
resources=$(kubectl get pods --all-namespaces -o json | jq '
  [ .items[] | select(.spec.containers != null) | .spec.containers[] | select(.resources != null) ]
  | reduce .[] as $container (
    {"cpu_requests":0, "cpu_limits":0, "mem_requests":0, "mem_limits":0};
    . + {
      "cpu_requests": (
        if $container.resources.requests.cpu? != null then
          if $container.resources.requests.cpu | test("m") then
            .cpu_requests + ($container.resources.requests.cpu | sub("m"; "") | tonumber)
          else
            .cpu_requests + ($container.resources.requests.cpu | tonumber * 1000)
          end
        else .cpu_requests end
      ),
      "cpu_limits": (
        if $container.resources.limits.cpu? != null then
          if $container.resources.limits.cpu | test("m") then
            .cpu_limits + ($container.resources.limits.cpu | sub("m"; "") | tonumber)
          else
            .cpu_limits + ($container.resources.limits.cpu | tonumber * 1000)
          end
        else .cpu_limits end
      ),
      "mem_requests": (
        if $container.resources.requests.memory? != null then
          if $container.resources.requests.memory | test("Mi") then
            .mem_requests + ($container.resources.requests.memory | sub("Mi"; "") | tonumber * 1024)
          elif $container.resources.requests.memory | test("Gi") then
            .mem_requests + ($container.resources.requests.memory | sub("Gi"; "") | tonumber * 1024 * 1024)
          elif $container.resources.requests.memory | test("Ki") then
            .mem_requests + ($container.resources.requests.memory | sub("Ki"; "") | tonumber)
          else .mem_requests end
        else .mem_requests end
      ),
      "mem_limits": (
        if $container.resources.limits.memory? != null then
          if $container.resources.limits.memory | test("Mi") then
            .mem_limits + ($container.resources.limits.memory | sub("Mi"; "") | tonumber * 1024)
          elif $container.resources.limits.memory | test("Gi") then
            .mem_limits + ($container.resources.limits.memory | sub("Gi"; "") | tonumber * 1024 * 1024)
          elif $container.resources.limits.memory | test("Ki") then
            .mem_limits + ($container.resources.limits.memory | sub("Ki"; "") | tonumber)
          else .mem_limits end
        else .mem_limits end
      )
    }
  )')

CPU_REQ=$(echo "$resources" | jq .cpu_requests)
CPU_LIM=$(echo "$resources" | jq .cpu_limits)
MEM_REQ=$(echo "$resources" | jq .mem_requests)
MEM_LIM=$(echo "$resources" | jq .mem_limits)

# Actual Usage
CPU_USAGE=0
MEM_USAGE_MIB=0

while read -r _ cpu mem _; do
  cpu_value=$(echo "$cpu" | sed 's/m//')
  mem_value=$(echo "$mem" | sed 's/Mi//')

  [[ "$cpu_value" =~ ^[0-9]+$ ]] && CPU_USAGE=$((CPU_USAGE + cpu_value))
  [[ "$mem_value" =~ ^[0-9]+$ ]] && MEM_USAGE_MIB=$((MEM_USAGE_MIB + mem_value))
done < <(kubectl top nodes --no-headers | awk '{print $1, $2, $4}')

# Conversions
ALLOC_CPU_CORES=$(awk "BEGIN {printf \"%.2f\", $ALLOC_CPU/1000}")
CPU_REQ_CORES=$(awk "BEGIN {printf \"%.2f\", $CPU_REQ/1000}")
CPU_LIM_CORES=$(awk "BEGIN {printf \"%.2f\", $CPU_LIM/1000}")
CPU_USE_CORES=$(awk "BEGIN {printf \"%.2f\", $CPU_USAGE/1000}")

ALLOC_MEM_GB=$(awk "BEGIN {printf \"%.2f\", $ALLOC_MEM/1024/1024}")
MEM_REQ_GB=$(awk "BEGIN {printf \"%.2f\", $MEM_REQ/1024/1024}")
MEM_LIM_GB=$(awk "BEGIN {printf \"%.2f\", $MEM_LIM/1024/1024}")
MEM_USE_GB=$(awk "BEGIN {printf \"%.2f\", $MEM_USAGE_MIB/1024}")

# Percentages
MEM_USE_BYTES=$((MEM_USAGE_MIB * 1024 * 1024))
ALLOC_MEM_BYTES=$((ALLOC_MEM * 1024))
MEM_USE_PCT=$(awk "BEGIN {printf \"%.1f\", ($MEM_USE_BYTES/$ALLOC_MEM_BYTES)*100}")

CPU_REQ_PCT=$(awk "BEGIN {printf \"%.1f\", ($CPU_REQ/$ALLOC_CPU)*100}")
CPU_LIM_PCT=$(awk "BEGIN {printf \"%.1f\", ($CPU_LIM/$ALLOC_CPU)*100}")
CPU_USE_PCT=$(awk "BEGIN {printf \"%.1f\", ($CPU_USAGE/$ALLOC_CPU)*100}")

MEM_REQ_PCT=$(awk "BEGIN {printf \"%.1f\", ($MEM_REQ/$ALLOC_MEM)*100}")
MEM_LIM_PCT=$(awk "BEGIN {printf \"%.1f\", ($MEM_LIM/$ALLOC_MEM)*100}")

# Efficiency
CPU_EFFICIENCY=$(awk -v use=$CPU_USAGE -v req=$CPU_REQ 'BEGIN {
  if (req == 0) print 0;
  else printf "%.1f", (use / req * 100)
}')

MEM_EFFICIENCY=$(awk -v use=$MEM_USAGE_MIB -v req_kib=$MEM_REQ 'BEGIN {
  req_mib = req_kib / 1024;
  if (req_mib == 0) print 0;
  else printf "%.1f", (use / req_mib * 100)
}')

# Output
cat <<EOF

Cluster Resource Utilization Summary

  CPU Allocatable:   ${ALLOC_CPU_CORES} cores
  CPU Requested:     ${CPU_REQ_CORES} cores (${CPU_REQ_PCT}%)
  CPU Limited:       ${CPU_LIM_CORES} cores (${CPU_LIM_PCT}%)
  CPU In Use:        ${CPU_USE_CORES} cores (${CPU_USE_PCT}%)
  CPU Request Efficiency: ${CPU_EFFICIENCY}% (Higher is better; low = over-provisioned)

  Memory Allocatable:   ${ALLOC_MEM_GB} GB
  Memory Requested:     ${MEM_REQ_GB} GB (${MEM_REQ_PCT}%)
  Memory Limited:       ${MEM_LIM_GB} GB (${MEM_LIM_PCT}%)
  Memory In Use:        ${MEM_USE_GB} GB (${MEM_USE_PCT}%)
  Memory Request Efficiency: ${MEM_EFFICIENCY}% (High = usage exceeds request → potential under-requesting)

Interpretation:

  - CPU is significantly over-provisioned. Actual usage is only ${CPU_USE_PCT}% of allocatable,
    but ${CPU_REQ_PCT}% is requested. Consider tuning default CPU requests.

  - Memory is under-requested. Actual usage (${MEM_USE_PCT}%) exceeds the requested value (${MEM_REQ_PCT}%).
    This indicates risk of OOM kills under pressure.

  - Request Efficiency:
      - CPU: ${CPU_EFFICIENCY}% → Low values indicate over-provisioning
      - Memory: ${MEM_EFFICIENCY}% → High values indicate under-requesting
EOF

# Top 5 CPU Pods
echo -e "\nTop 5 Over-requested CPU Pods (by usage):"
kubectl top pods -A --no-headers | sort -k3 -nr | head -n 5 | awk '{printf "%-32s %-60s %-8s %-8s\n", $1, $2, $3, $4}'

# Top 5 Memory Pods
echo -e "\nTop 5 Over-requested Memory Pods (by usage):"
kubectl top pods -A --no-headers | sort -k4 -nr | head -n 5 | awk '{printf "%-32s %-60s %-8s %-8s\n", $1, $2, $3, $4}'

# No Requests
echo -e "\nPods With No Resource Requests Defined (first 5):"
no_requests=$(kubectl get pods -A -o json | jq -r '
  .items[] | select([.spec.containers[].resources.requests?] | length == 0) 
  | "\(.metadata.namespace)/\(.metadata.name)"' | head -n 5)
if [[ -z "$no_requests" ]]; then
  echo "  None found."
else
  echo "$no_requests"
fi

# CSV
CSV_OUT="/tmp/k8s-utilization.csv"
echo "cluster_metric,cpu_allocatable,cpu_requested,cpu_used,memory_allocatable_gb,memory_requested_gb,memory_used_gb" > "$CSV_OUT"
echo "total,${ALLOC_CPU_CORES},${CPU_REQ_CORES},${CPU_USE_CORES},${ALLOC_MEM_GB},${MEM_REQ_GB},${MEM_USE_GB}" >> "$CSV_OUT"
echo -e "\nCSV summary written to $CSV_OUT"

