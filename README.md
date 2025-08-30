# Kubernetes Cluster Resource Utilization Script

This script collects and summarizes **CPU and Memory utilization** across a Kubernetes cluster, helping operators identify **over-requesting** and **under-requesting** of resources. It leverages `kubectl`, `metrics-server`, and `jq` to provide a detailed view of allocatable resources, requests, limits, actual usage, and efficiency.

---

## 📖 Features

- Gathers **allocatable CPU and memory** from all nodes.
- Aggregates **resource requests and limits** across all pods and containers.
- Collects **actual usage** from `kubectl top nodes` (requires metrics-server).
- Converts usage and requests into **cores and gigabytes** for readability.
- Computes **percentages**:
  - Requests vs. allocatable  
  - Limits vs. allocatable  
  - Actual usage vs. allocatable  
- Calculates **efficiency** metrics:
  - CPU Request Efficiency (% of requested CPU actually being used)  
  - Memory Request Efficiency (% of requested memory actually being used)  
- Highlights:
  - **Top 5 CPU-consuming pods**  
  - **Top 5 memory-consuming pods**  
  - **Pods with no resource requests defined**  
- Exports a **CSV summary** (`/tmp/k8s-utilization.csv`) for further analysis.

---

## 📂 Output Example

When executed, the script prints a cluster summary:

```

Cluster Resource Utilization Summary

CPU Allocatable:   32.00 cores
CPU Requested:     24.50 cores (76.5%)
CPU Limited:       30.00 cores (93.7%)
CPU In Use:        8.20 cores (25.6%)
CPU Request Efficiency: 33.5% (Higher is better; low = over-provisioned)

Memory Allocatable:   128.00 GB
Memory Requested:     85.00 GB (66.4%)
Memory Limited:       120.00 GB (93.7%)
Memory In Use:        95.00 GB (74.2%)
Memory Request Efficiency: 111.7% (High = usage exceeds request → potential under-requesting)

Interpretation:

* CPU is significantly over-provisioned.
* Memory is under-requested; actual usage exceeds requests.
* Efficiency metrics highlight tuning opportunities.

````

It also shows:
- Top CPU and memory pods
- Pods with no requests set
- CSV file location for data export

---

## Requirements

- **Kubernetes CLI (`kubectl`)** with access to the cluster  
- **Metrics Server** installed and functional (`kubectl top nodes` must work)  
- **jq** installed for JSON parsing  

---

## Usage

1. Clone or copy the script.
2. Make it executable:
   ```bash
   chmod +x cluster-utilization.sh
   ```

3. Run it against your cluster:

   ```bash
   ./cluster-utilization.sh
   ```
4. Review the console output and check `/tmp/k8s-utilization.csv` for CSV metrics.

---

## Use Cases

* Detect **over-provisioned CPU requests** that waste cluster capacity.
* Identify **under-requested memory** that could cause OOM kills.
* Provide insights for **capacity planning** and **resource tuning**.
* Generate **CSV data** for dashboards, spreadsheets, or GitOps pipelines.

---
# Grafana Dashboard: Kubernetes Cluster Resource Utilization

This Grafana dashboard provides a **visual counterpart** to the Kubernetes resource utilization script. It presents **allocatable resources, requests, limits, usage, and efficiency** in real time using Prometheus metrics, making it easier to monitor and tune cluster performance.

---

## Features

- **High-level cluster metrics**
  - **CPU Allocatable (cores)** → Total CPU capacity across nodes.  
  - **CPU Requested (cores)** → Sum of all container CPU requests in the cluster (namespace filterable).  
  - **CPU Used (cores)** → Actual CPU usage from Prometheus container metrics.  
  - **CPU Request Efficiency (%)** → Ratio of actual usage vs. requested CPU. Low values indicate over-provisioning.  

- **Top resource consumers**
  - **Top 5 Pods by CPU Usage** → Identifies CPU-heavy workloads.  
  - **Top 5 Pods by Memory Usage** → Identifies memory-heavy workloads.  

- **Resource hygiene**
  - **Pods with No Resource Requests** → Lists workloads missing explicit CPU/memory requests, which may cause scheduling or QoS issues.  

- **Namespace selector**
  - Dashboard includes a **namespace variable**, allowing you to filter metrics per namespace or view the entire cluster.  

---

## Panels Overview

| Panel                          | Description                                                                 |
|--------------------------------|-----------------------------------------------------------------------------|
| **CPU Allocatable (cores)**    | Total available CPU cores in the cluster.                                   |
| **CPU Requested (cores)**      | Sum of CPU requests from pods/containers (namespace filterable).            |
| **CPU Used (cores)**           | Actual usage, averaged over 5 minutes, reported by Prometheus.              |
| **CPU Request Efficiency (%)** | Actual CPU used ÷ CPU requested × 100. Highlights over/under provisioning. |
| **Top 5 Pods by CPU Usage**    | Table showing the pods with the highest CPU consumption.                    |
| **Top 5 Pods by Memory Usage** | Table showing the pods with the highest memory consumption.                 |
| **Pods with No Requests**      | Table of pods missing CPU/memory requests (potential risk).                 |

---

## Requirements

- **Prometheus** installed and scraping:
  - `kube-state-metrics` (for allocatable and requests/limits)  
  - `cAdvisor` or equivalent (for CPU/memory usage metrics)  
- **Grafana** v8+  
- Access to the **Kubernetes metrics**:  
  - `kube_node_status_allocatable_cpu_cores`  
  - `kube_pod_container_resource_requests_cpu_cores`  
  - `container_cpu_usage_seconds_total`  
  - `container_memory_usage_bytes`  

---

## Usage

1. Import the JSON file into Grafana (`Dashboards → Import`).  
2. Select your **Prometheus datasource**.  
3. Use the **namespace filter** at the top to drill into specific workloads.  

---

## Use Cases

- **Capacity planning** → Ensure allocatable resources meet demand.  
- **Efficiency analysis** → Detect over-requested CPU/memory and reclaim wasted resources.  
- **Pod-level insights** → Quickly find the heaviest CPU/memory consumers.  
- **Policy enforcement** → Identify pods without resource requests to improve scheduling stability.  

---

## Benefits

- Complements the **CLI script** by providing real-time visualization.  
- Easy-to-read panels for **SREs, Platform Engineers, and DevOps teams**.  
- Supports **namespace scoping** for multi-tenant clusters.  
- Provides a foundation for **alerts** (e.g., efficiency dropping below threshold).  

---

**This dashboard + script combination gives both on-demand snapshots and continuous monitoring of Kubernetes resource utilization.**