# quicue-infra

Infrastructure patterns for quicue. Projections, generators, lookups, capacity planning, cost modeling, and operational analysis.

**Status:** [Active]

## Installation

```cue
import "quicue.ca/infra"
```

## Schemas

### Projections

Views of infrastructure data for specific purposes.

| Schema | Description |
|--------|-------------|
| `#DCOverview` | Datacenter overview with computed metrics, criticality ranking, and topology layers |
| `#StatusProjection` | Groups resources by status (running, stopped, etc.) |
| `#TopologyProjection` | Groups resources by host/node for deployment visualization |
| `#NodeDistributionProjection` | Resource counts per hypervisor node |
| `#LXCContainersProjection` | Lists all LXC containers with ID, node, and IP |
| `#VMsProjection` | Lists all VMs with ID, node, and IP |
| `#GPUResourcesProjection` | Lists resources with GPU passthrough |
| `#CriticalResourcesProjection` | Ranks resources by type criticality (DNS, proxy, platform) |
| `#HealthCheckProjection` | Generates health check commands per resource |
| `#ImpactAnalysisProjection` | Shows what depends on given target resources |
| `#ExecutionPlanProjection` | Phased deployment order (bootstrap, core, apps) |
| `#ServiceCatalogProjection` | Groups resources by service capability type |
| `#JustfileProjection` | Generates justfile recipes from infraGraph actions |
| `#SSHConfigProjection` | Generates SSH config entries from resources |

### Lookups

Query infrastructure by attribute value.

| Schema | Description |
|--------|-------------|
| `#LookupByIP` | Find resources by IP address |
| `#LookupByNode` | Find resources on a specific node/host |
| `#LookupByOwner` | Find resources owned by a team/person |
| `#LookupByPort` | Find resources using a specific port (inbound/outbound) |
| `#LookupByTag` | Find resources with a specific tag |
| `#LookupByVLAN` | Find resources on a specific VLAN |

### Capacity and Cost

Capacity planning and cost modeling.

| Schema | Description |
|--------|-------------|
| `#ClusterCapacity` | Aggregate capacity across all nodes |
| `#NodeCapacity` | Track capacity for a single hypervisor node |
| `#NodeUtilization` | Calculate per-node utilization from workloads |
| `#CanFit` | Find nodes where a workload can fit |
| `#BestFit` | Find optimal placement for multiple workloads |
| `#Pricing` | Standard pricing model for compute resources |
| `#ResourceCost` | Calculate cost for a single resource |
| `#ResourceCosts` | Calculate costs for all resources |
| `#Chargeback` | Group costs by owner, team, or cost center |
| `#CostTrend` | Compare costs across time periods |
| `#WhatIfCost` | Calculate cost impact of adding resources |

### Analysis and Planning

Risk assessment, change simulation, and operational planning.

| Schema | Description |
|--------|-------------|
| `#BottleneckAnalysis` | Identify resources with high fan-in (potential SPOFs) |
| `#CascadeAnalysis` | Simulate cascade failure from a resource going down |
| `#ChangeSimulation` | Simulate blocking ports or taking down resources |
| `#WhatIfDown` | Quick cascade check for multiple failure scenarios |
| `#MigrationPlan` | Generate ordered migration commands for node evacuation |
| `#RebalanceSuggestions` | Suggest moves to balance overloaded nodes |
| `#FanIn` | Count incoming dependencies for a single target |
| `#RedundancyCheck` | Find single points of failure without replicas |
| `#ResilienceScore` | Calculate overall resilience metrics (0-100 score) |
| `#OrphanDetection` | Find unused, unowned, or stale resources |
| `#EnvironmentDiff` | Compare two environments and find differences |

### Export Targets

Generate configuration for external tools.

| Schema | Description |
|--------|-------------|
| `#PrometheusTargets` | Generate Prometheus static_configs targets |
| `#AlertManagerRoutes` | Generate AlertManager routing tree from metadata |
| `#GrafanaDashboard` | Generate basic Grafana dashboard JSON structure |
| `#AnsibleInventory` | Generate Ansible inventory structure from resources |
| `#NetworkMap` | Group resources by VLAN for network visualization |

### Actions

Project-level action patterns.

| Schema | Description |
|--------|-------------|
| `#ProjectAction` | Schema for project-level actions |
| `#ProjectActionTemplates` | Common project action templates (validate, fmt, query, etc.) |

## Usage Examples

### Capacity Planning

```cue
import "quicue.ca/infra"

// Check if a new workload fits
fit: infra.#CanFit & {
    Nodes: {
        pve1: {cores_total: 64, memory_total: 131072, storage_total: 2000}
        pve2: {cores_total: 64, memory_total: 131072, storage_total: 2000}
    }
    Workloads: infraGraph
    Request: {cores: 16, memory: 65536, disk: 500}
}
// fit.best_fit = "pve2"
// fit.candidates = [{node: "pve2", headroom: 32}, ...]
```

### Cost Chargeback

```cue
import "quicue.ca/infra"

// Group costs by owner
chargeback: infra.#Chargeback & {
    Resources: infraGraph
    Pricing: infra.#Pricing & {
        core_cost:   15.00
        memory_cost: 8.00
    }
    GroupBy: "owner"
}
// chargeback.groups["platform-team"].monthly_cost = 450.0
// chargeback.top_spenders = ["platform-team", "dev-team", ...]
```

### Resilience Analysis

```cue
import "quicue.ca/infra"

// Calculate resilience score
score: infra.#ResilienceScore & {Resources: infraGraph}
// score.score = 72
// score.assessment = "moderate"
// score.recommendations = ["Add redundancy for critical bottlenecks: [dns, db]"]

// Test what-if scenarios
scenarios: infra.#WhatIfDown & {
    Resources: infraGraph
    TestFailures: ["dns", "database", "san"]
}
// scenarios.worst_case = {resource: "san", affected: 8}
```

---

Part of the [quicue](https://quicue.ca) ecosystem.
