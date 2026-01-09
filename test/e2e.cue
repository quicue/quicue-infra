// End-to-end tests for quicue-infra patterns
//
// Run with: cue vet ./test/
// Export with: cue export ./test/ -e results

package test

import "quicue.ca/infra"

// =============================================================================
// Test Data: Mock Infrastructure Graph
// =============================================================================

_testGraph: {
	// Hypervisor nodes
	"pve1": {
		ip:     "10.0.0.1"
		node:   "pve1"
		"@type": VirtualizationPlatform: true
		owner:  "infra-team"
		cores:  32
		memory: 128000
		tags: {proxmox: true, production: true}
	}
	"pve2": {
		ip:     "10.0.0.2"
		node:   "pve2"
		"@type": VirtualizationPlatform: true
		owner:  "infra-team"
		cores:  32
		memory: 128000
		tags: {proxmox: true, production: true}
	}

	// Core services
	"dns-primary": {
		ip:          "10.0.1.10"
		host:        "pve1"
		vmid:        100
		"@type":     DNSServer: true
		owner:       "infra-team"
		cores:       2
		memory:      2048
		vlan:        10
		replica:     "dns-secondary"
		ports: {inbound: [53, 443], outbound: []}
		tags: {dns: true, critical: true}
		purpose:     "Primary DNS resolver"
	}
	"dns-secondary": {
		ip:          "10.0.1.11"
		host:        "pve2"
		vmid:        101
		"@type":     DNSServer: true
		owner:       "infra-team"
		cores:       2
		memory:      2048
		vlan:        10
		replica_of:  "dns-primary"
		ports: {inbound: [53, 443], outbound: []}
		tags: {dns: true, critical: true}
		purpose:     "Secondary DNS resolver"
	}
	"proxy": {
		ip:          "10.0.1.20"
		host:        "pve1"
		vmid:        102
		"@type":     ReverseProxy: true
		owner:       "infra-team"
		cores:       4
		memory:      4096
		vlan:        10
		ports: {inbound: [80, 443], outbound: [8080, 8443]}
		connects_to: {"web-prod": true, "api-prod": true}
		tags: {proxy: true, critical: true}
		purpose:     "Ingress reverse proxy"
	}

	// Application VMs
	"web-prod": {
		ip:          "10.0.2.100"
		host:        "pve1"
		vmid:        200
		owner:       "app-team"
		cores:       4
		memory:      8192
		vlan:        20
		version:     "v2.5.1"
		ports: {inbound: [8080], outbound: [5432, 6379]}
		connects_to: {"db-prod": true, "cache-prod": true}
		depends: {"dns-primary": true, "proxy": true}
		tags: {web: true, production: true}
		purpose:     "Production web frontend"
	}
	"api-prod": {
		ip:          "10.0.2.101"
		host:        "pve2"
		vmid:        201
		owner:       "app-team"
		cores:       4
		memory:      8192
		vlan:        20
		version:     "v3.1.0"
		ports: {inbound: [8443], outbound: [5432, 6379]}
		connects_to: {"db-prod": true, "cache-prod": true}
		depends: {"dns-primary": true, "proxy": true}
		tags: {api: true, production: true}
		purpose:     "Production API backend"
	}

	// Database
	"db-prod": {
		ip:          "10.0.3.50"
		host:        "pve2"
		vmid:        300
		owner:       "dba-team"
		cores:       8
		memory:      32768
		vlan:        30
		ports: {inbound: [5432], outbound: []}
		tags: {database: true, production: true, critical: true}
		purpose:     "Production PostgreSQL"
	}

	// Cache
	"cache-prod": {
		ip:          "10.0.3.60"
		host:        "pve1"
		vmid:        301
		owner:       "dba-team"
		cores:       4
		memory:      16384
		vlan:        30
		ports: {inbound: [6379], outbound: []}
		tags: {cache: true, production: true}
		purpose:     "Production Redis cache"
	}

	// LXC Containers
	"monitoring": {
		ip:           "10.0.1.30"
		host:         "pve1"
		container_id: 400
		owner:        "infra-team"
		cores:        2
		memory:       4096
		vlan:         10
		tags: {monitoring: true}
		purpose:      "Prometheus + Grafana"
	}

	// Orphan resource (no owner, no dependencies)
	"old-test-vm": {
		ip:   "10.0.9.99"
		host: "pve2"
		vmid: 999
		cores:  2
		memory: 2048
		vlan:   90
		cost:   50
	}

	// GPU workload
	"ml-worker": {
		ip:     "10.0.4.10"
		host:   "pve2"
		vmid:   500
		owner:  "ml-team"
		cores:  16
		memory: 65536
		vlan:   40
		gpu:    "NVIDIA RTX 4090"
		tags: {ml: true, gpu: true}
		purpose: "ML training workload"
	}
}

// Staging environment (for diff testing)
_stagingGraph: {
	"web-prod": {
		ip:      "10.1.2.100"
		host:    "stage1"
		vmid:    200
		owner:   "app-team"
		cores:   2           // Different from prod
		memory:  4096        // Different from prod
		vlan:    20
		version: "v2.6.0-rc1" // Different from prod
	}
	"api-prod": {
		ip:      "10.1.2.101"
		host:    "stage1"
		vmid:    201
		owner:   "app-team"
		cores:   2
		memory:  4096
		vlan:    20
		version: "v3.2.0-rc1"
	}
	// Missing: dns-primary, dns-secondary, proxy, db-prod, cache-prod, etc.
	// Extra in staging:
	"feature-test": {
		ip:    "10.1.2.200"
		host:  "stage1"
		vmid:  250
		owner: "app-team"
	}
}

// =============================================================================
// Test: Projections
// =============================================================================

_test_topology: infra.#TopologyProjection & {Resources: _testGraph}
_test_execution: infra.#ExecutionPlanProjection & {Resources: _testGraph}
_test_catalog: infra.#ServiceCatalogProjection & {Resources: _testGraph}
_test_health: infra.#HealthCheckProjection & {Resources: _testGraph}
_test_critical: infra.#CriticalResourcesProjection & {Resources: _testGraph}
_test_distribution: infra.#NodeDistributionProjection & {Resources: _testGraph}
_test_ssh: infra.#SSHConfigProjection & {Resources: _testGraph}
_test_gpu: infra.#GPUResourcesProjection & {Resources: _testGraph}
_test_lxc: infra.#LXCContainersProjection & {Resources: _testGraph}
_test_vms: infra.#VMsProjection & {Resources: _testGraph}
_test_status: infra.#StatusProjection & {Resources: _testGraph}
_test_impact: infra.#ImpactAnalysisProjection & {
	Resources: _testGraph
	Targets: ["pve1"]
}

// =============================================================================
// Test: Lookups
// =============================================================================

_test_lookup_ip: infra.#LookupByIP & {
	Resources: _testGraph
	Target:    "10.0.2.100"
}
_test_lookup_vlan: infra.#LookupByVLAN & {
	Resources: _testGraph
	Target:    20
}
_test_lookup_port: infra.#LookupByPort & {
	Resources: _testGraph
	Target:    5432
}
_test_lookup_owner: infra.#LookupByOwner & {
	Resources: _testGraph
	Target:    "infra-team"
}
_test_lookup_node: infra.#LookupByNode & {
	Resources: _testGraph
	Target:    "pve1"
}
_test_lookup_tag: infra.#LookupByTag & {
	Resources: _testGraph
	Target:    "critical"
}
_test_network_map: infra.#NetworkMap & {Resources: _testGraph}

// =============================================================================
// Test: Generators
// =============================================================================

_test_ansible: infra.#AnsibleInventory & {Resources: _testGraph}
_test_prometheus: infra.#PrometheusTargets & {
	Resources: _testGraph
	Port:      9100
}
_test_alertmanager: infra.#AlertManagerRoutes & {Resources: _testGraph}
_test_grafana: infra.#GrafanaDashboard & {
	Resources: _testGraph
	Title:     "Test Infrastructure"
}

// =============================================================================
// Test: Operations
// =============================================================================

_test_migration: infra.#MigrationPlan & {
	Resources: _testGraph
	Source:    "pve1"
	Target:    "pve2"
}
_test_orphans: infra.#OrphanDetection & {Resources: _testGraph}

// =============================================================================
// Test: Analysis
// =============================================================================

_test_env_diff: infra.#EnvironmentDiff & {
	SourceName: "prod"
	TargetName: "staging"
	Source:     _testGraph
	Target:     _stagingGraph
}
_test_change_sim_port: (infra.#ChangeSimulation & {Resources: _testGraph}).BlockPort & {
	port: 5432
}
_test_change_sim_takedown: (infra.#ChangeSimulation & {Resources: _testGraph}).TakeDown & {
	target: "db-prod"
}
_test_redundancy: infra.#RedundancyCheck & {Resources: _testGraph}

// =============================================================================
// Test: Justfile
// =============================================================================

_test_justfile: infra.#JustfileProjection & {
	InfraGraph: _testGraph
	ProjectActions: {
		validate: infra.#ProjectActionTemplates.validate
		fmt:      infra.#ProjectActionTemplates.fmt
	}
	ProjectName:        "test-infra"
	ProjectDescription: "Test infrastructure project"
}

// =============================================================================
// Assertions
// =============================================================================

// Topology assertions
_assert_topology_pve1_count: _test_topology.counts.pve1 & >=1
_assert_topology_pve2_count: _test_topology.counts.pve2 & >=1

// Execution plan assertions
_assert_exec_phase1_has_nodes: len(_test_execution.phases.phase1_bootstrap) & >=2
_assert_exec_phase2_has_core: len(_test_execution.phases.phase2_core) & >=1
_assert_exec_order_not_empty: len(_test_execution.order) & >=1

// Catalog assertions
_assert_catalog_has_dns: len(_test_catalog.catalog.DNSServer) & >=1
_assert_catalog_has_proxy: len(_test_catalog.catalog.ReverseProxy) & >=1

// Lookup assertions
_assert_lookup_ip_found: _test_lookup_ip.found & true
_assert_lookup_ip_result: _test_lookup_ip.result["web-prod"].ip & "10.0.2.100"
_assert_lookup_vlan_count: len(_test_lookup_vlan.result) & >=2
_assert_lookup_owner_count: len(_test_lookup_owner.result) & >=4

// Migration assertions
_assert_migration_vm_count: _test_migration.vm_count & >=1
_assert_migration_has_commands: len(_test_migration.commands) & >=1

// Orphan assertions
_assert_orphan_found: len(_test_orphans.zombies) & >=1

// Diff assertions
_assert_diff_missing: len(_test_env_diff.only_in_source) & >=1
_assert_diff_extra: len(_test_env_diff.only_in_target) & >=1
_assert_diff_parity: _test_env_diff.summary.parity_percentage & <=100

// Redundancy assertions
_assert_redundancy_has_replica: len(_test_redundancy.has_replica) & >=1
_assert_redundancy_has_spf: len(_test_redundancy.single_point_failures) & >=1

// GPU assertions
_assert_gpu_found: len(_test_gpu.names) & >=1
_assert_gpu_name: _test_gpu.names[0] & "ml-worker"

// LXC assertions
_assert_lxc_found: _test_lxc.count & >=1

// VM assertions
_assert_vm_count: _test_vms.count & >=5

// Generator assertions
_assert_ansible_has_hosts: len(_test_ansible.all.hosts) & >=1
_assert_prometheus_has_targets: len(_test_prometheus.targets) & >=1
_assert_grafana_has_panels: len(_test_grafana.dashboard.panels) & >=1

// Change simulation assertions
_assert_port_block_affected: len(_test_change_sim_port.affected_targets) & >=1
_assert_takedown_dependents: _test_change_sim_takedown.impact.direct & >=1

// =============================================================================
// Results Export
// =============================================================================

results: {
	projections: {
		topology: {
			layers:  [for k, _ in _test_topology.layers {k}]
			counts:  _test_topology.counts
		}
		execution_plan: {
			phase1_count: len(_test_execution.phases.phase1_bootstrap)
			phase2_count: len(_test_execution.phases.phase2_core)
			phase3_count: len(_test_execution.phases.phase3_apps)
			order:        _test_execution.order
		}
		service_catalog: {
			types:  [for k, _ in _test_catalog.catalog {k}]
			counts: _test_catalog.counts
		}
		critical_resources: _test_critical.names
		node_distribution:  _test_distribution.counts
		ssh_config_entries: [for k, _ in _test_ssh.entries {k}]
		gpu_resources:      _test_gpu.names
		lxc_containers:     _test_lxc.count
		vms:                _test_vms.count
		impact_on_pve1:     _test_impact.count
	}

	lookups: {
		by_ip: {
			target: "10.0.2.100"
			found:  _test_lookup_ip.found
			result: [for k, _ in _test_lookup_ip.result {k}]
		}
		by_vlan: {
			target: 20
			result: _test_lookup_vlan.result
		}
		by_port: {
			target: 5432
			result: _test_lookup_port.result
		}
		by_owner: {
			target: "infra-team"
			result: _test_lookup_owner.result
		}
		by_node: {
			target: "pve1"
			result: _test_lookup_node.result
		}
		by_tag: {
			target: "critical"
			result: _test_lookup_tag.result
		}
		network_map: {
			vlans: [for k, _ in _test_network_map.map {k}]
		}
	}

	generators: {
		ansible_host_count:      len(_test_ansible.all.hosts)
		ansible_groups:          [for k, _ in _test_ansible.all.children {k}]
		prometheus_target_count: len(_test_prometheus.targets)
		alertmanager_routes:     len(_test_alertmanager.routes)
		grafana_panel_count:     len(_test_grafana.dashboard.panels)
	}

	operations: {
		migration: {
			source:       "pve1"
			target:       "pve2"
			vm_count:     _test_migration.vm_count
			total_cores:  _test_migration.total_cores
			total_memory: _test_migration.total_memory
			commands:     len(_test_migration.commands)
			order:        _test_migration.order
		}
		orphan_detection: _test_orphans.summary
	}

	analysis: {
		environment_diff: {
			source_name:      "prod"
			target_name:      "staging"
			only_in_source:   _test_env_diff.only_in_source
			only_in_target:   _test_env_diff.only_in_target
			drifted_count:    len([for k, _ in _test_env_diff.differences {k}])
			parity:           _test_env_diff.summary
		}
		change_simulation: {
			block_port_5432: _test_change_sim_port.impact
			takedown_db:     _test_change_sim_takedown.impact
		}
		redundancy: _test_redundancy.summary
	}

	justfile: {
		has_output:    _test_justfile.Output != ""
		output_length: len(_test_justfile.Output)
	}
}
