# quicue-infra

Infrastructure patterns for [quicue](https://github.com/quicue/quicue). Projections, generators, lookups, and operational patterns.

**Module:** `quicue.ca/infra`

## Install

```bash
# When published to registry
cue mod get quicue.ca/infra@v0.1.0

# Local development
mkdir -p cue.mod/pkg/quicue.ca
ln -sf /path/to/quicue-infra cue.mod/pkg/quicue.ca/infra
```

## Patterns

### Projections (from quicue core)

| Pattern | Purpose |
|---------|---------|
| `#TopologyProjection` | Group resources by node/host |
| `#SSHConfigProjection` | Generate SSH config entries |
| `#HealthCheckProjection` | Generate health check commands |
| `#ServiceCatalogProjection` | Group resources by @type |
| `#JustfileProjection` | Generate justfile from actions |

### Lookups

| Pattern | Usage |
|---------|-------|
| `#LookupByIP` | Find resource by IP address |
| `#LookupByVLAN` | Find resources on a VLAN |
| `#LookupByPort` | Find resources using a port |
| `#LookupByOwner` | Find resources by owner |
| `#LookupByNode` | Find resources on a node |
| `#NetworkMap` | Group all resources by VLAN |

### Operations

| Pattern | Usage |
|---------|-------|
| `#MigrationPlan` | Generate ordered migration commands |
| `#OrphanDetection` | Find unused/unowned resources |

### Analysis

| Pattern | Usage |
|---------|-------|
| `#EnvironmentDiff` | Compare prod vs staging |
| `#ChangeSimulation` | "Block port X, what breaks?" |
| `#RedundancyCheck` | Find SPOFs without replicas |

### Generators

| Pattern | Output |
|---------|--------|
| `#AnsibleInventory` | Ansible inventory YAML structure |
| `#PrometheusTargets` | Prometheus static_configs |
| `#AlertManagerRoutes` | AlertManager routing tree |
| `#GrafanaDashboard` | Basic Grafana dashboard JSON |

## Examples

### Reverse Lookup

```cue
import "quicue.ca/infra"

// Who owns 10.0.1.100?
byIP: infra.#LookupByIP & {
    Resources: infraGraph
    Target: "10.0.1.100"
}
// byIP.result = {"web-prod": {...}}
```

### Migration Plan

```cue
import "quicue.ca/infra"

// Evacuate pve1 to pve2
plan: infra.#MigrationPlan & {
    Resources: vms
    Source: "pve1"
    Target: "pve2"
}
// plan.commands = [{step: "...", migrate: "qm migrate ..."}]
```

### Environment Diff

```cue
import "quicue.ca/infra"

diff: infra.#EnvironmentDiff & {
    SourceName: "prod"
    TargetName: "staging"
    Source: prod_resources
    Target: staging_resources
}
// diff.only_in_source = ["web-2"]
// diff.differences.web-1.version = {source: "v2.5.1", target: "v2.6.0-rc1"}
```

## Related

- [quicue](https://github.com/quicue/quicue) - Core graph patterns
- [quicue-proxmox](https://github.com/quicue/quicue-proxmox) - Proxmox provider
- [quicue-docker](https://github.com/quicue/quicue-docker) - Docker provider
