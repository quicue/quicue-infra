// Projection patterns for infrastructure graph views
//
// Projections are computed views of the infraGraph that group, filter,
// or transform resources for specific purposes (deployment order, monitoring, etc.)
//
// Usage:
//   import "quicue.ca/infra"
//
//   topology: infra.#TopologyProjection & {Resources: myInfraGraph}

package infra

// #TopologyProjection - Groups resources by dependency depth
// layer0: no dependencies (roots), layer1: depends only on layer0, etc.
#TopologyProjection: {
	Resources: [string]: {...}

	// Compute layers based on node field (for Proxmox, node = hypervisor)
	layers: {
		// Resources with host field
		for name, res in Resources if res.host != _|_ {
			"\(res.host)": (name): res
		}
		// Resources with node field (but no host)
		for name, res in Resources if res.host == _|_ && res.node != _|_ {
			"\(res.node)": (name): res
		}
		// Resources with neither
		for name, res in Resources if res.host == _|_ && res.node == _|_ {
			"unassigned": (name): res
		}
	}

	// Resource count per layer
	counts: {
		for layer, members in layers {
			"\(layer)": len(members)
		}
	}
}

// #ExecutionPlanProjection - Phased deployment order
// phase1_bootstrap: infrastructure (nodes), phase2_core: core services, phase3_apps: applications
#ExecutionPlanProjection: {
	Resources: [string]: {...}

	phases: {
		// Phase 1: Nodes/hypervisors (VirtualizationPlatform type)
		phase1_bootstrap: {
			for name, res in Resources if res["@type"] != _|_ {
				if res["@type"].VirtualizationPlatform != _|_ {
					"\(name)": res
				}
			}
		}

		// Phase 2: Core infrastructure (DNS, proxy, secrets)
		phase2_core: {
			for name, res in Resources if res["@type"] != _|_ {
				if res["@type"].DNSServer != _|_ || res["@type"].ReverseProxy != _|_ || res["@type"].Vault != _|_ {
					"\(name)": res
				}
			}
		}

		// Phase 3: Everything else
		phase3_apps: {
			let _phase1 = {for n, _ in phases.phase1_bootstrap {(n): true}}
			let _phase2 = {for n, _ in phases.phase2_core {(n): true}}
			for name, res in Resources if _phase1[name] == _|_ && _phase2[name] == _|_ {
				"\(name)": res
			}
		}
	}

	// Ordered list for deployment
	order: [
		for name, _ in phases.phase1_bootstrap {name},
		for name, _ in phases.phase2_core {name},
		for name, _ in phases.phase3_apps {name},
	]
}

// #ServiceCatalogProjection - Groups resources by service capability
#ServiceCatalogProjection: {
	Resources: [string]: {...}

	catalog: {
		for name, res in Resources if res["@type"] != _|_ {
			for t, _ in res["@type"] {
				"\(t)": (name): res
			}
		}
	}

	// Count per service type
	counts: {
		for svc, members in catalog {
			"\(svc)": len(members)
		}
	}
}

// #HealthCheckProjection - Generates health check commands per resource
#HealthCheckProjection: {
	Resources: [string]: {...}

	checks: {
		for name, res in Resources if res.ip != _|_ {
			"\(name)": {
				ping: "ping -c 1 \(res.ip)"
				if res.actions != _|_ && res.actions.pct_status != _|_ {
					status: res.actions.pct_status.command
				}
				if res.actions != _|_ && res.actions.qm_status != _|_ {
					status: res.actions.qm_status.command
				}
			}
		}
	}
}

// #CriticalResourcesProjection - Ranks resources by dependent count
// Uses @type to identify critical infrastructure
#CriticalResourcesProjection: {
	Resources: [string]: {...}

	// Resources with critical types
	critical: {
		for name, res in Resources if res["@type"] != _|_ {
			if res["@type"].VirtualizationPlatform != _|_ {
				"\(name)": {resource: res, type: "VirtualizationPlatform"}
			}
			if res["@type"].DNSServer != _|_ {
				"\(name)": {resource: res, type: "DNSServer"}
			}
			if res["@type"].ReverseProxy != _|_ {
				"\(name)": {resource: res, type: "ReverseProxy"}
			}
		}
	}

	// List critical resource names
	names: [for name, _ in critical {name}]
}

// #NodeDistributionProjection - Resources per hypervisor node
#NodeDistributionProjection: {
	Resources: [string]: {...}

	distribution: {
		// Resources with host field
		for name, res in Resources if res.host != _|_ {
			"\(res.host)": (name): res
		}
		// Resources with node field (but no host)
		for name, res in Resources if res.host == _|_ && res.node != _|_ {
			"\(res.node)": (name): res
		}
	}

	// Count per node
	counts: {
		for node, members in distribution {
			"\(node)": len(members)
		}
	}
}

// #SSHConfigProjection - Generates SSH config entries
#SSHConfigProjection: {
	Resources: [string]: {...}

	entries: {
		for name, res in Resources if res.ip != _|_ {
			"\(name)": {
				let _user = res.ssh_user | *"root"
				Host:     name
				HostName: res.ip
				User:     _user
			}
		}
	}

	// Generate SSH config file content
	config: {
		for name, entry in entries {
			"\(name)": """
				Host \(entry.Host)
				    HostName \(entry.HostName)
				    User \(entry.User)
				"""
		}
	}
}

// #GPUResourcesProjection - Lists resources with GPU passthrough
#GPUResourcesProjection: {
	Resources: [string]: {...}

	gpuResources: {
		for name, res in Resources if res.gpu != _|_ || res.hardware != _|_ && res.hardware.gpu != _|_ {
			"\(name)": {
				resource: res
				gpu:      res.gpu | *res.hardware.gpu
			}
		}
	}

	// List of resource names with GPUs
	names: [for name, _ in gpuResources {name}]
}

// #LXCContainersProjection - Lists all LXC containers
#LXCContainersProjection: {
	Resources: [string]: {...}

	containers: {
		// With container_id
		for name, res in Resources if res.container_id != _|_ {
			"\(name)": {
				id:   res.container_id
				node: res.host | *res.node | *"unknown"
				ip:   res.ip | *""
			}
		}
		// With lxcid (but no container_id)
		for name, res in Resources if res.container_id == _|_ && res.lxcid != _|_ {
			"\(name)": {
				id:   res.lxcid
				node: res.host | *res.node | *"unknown"
				ip:   res.ip | *""
			}
		}
	}

	// Count
	count: len(containers)
}

// #VMsProjection - Lists all VMs
#VMsProjection: {
	Resources: [string]: {...}

	vms: {
		for name, res in Resources if res.vmid != _|_ || res.vm_id != _|_ {
			let _id = res.vm_id | *res.vmid
			let _host = res.host | *res.node | *""
			"\(name)": {
				id:   _id
				node: _host
				ip:   res.ip | *""
			}
		}
	}

	// Count
	count: len(vms)
}

// #StatusProjection - Groups resources by status
#StatusProjection: {
	Resources: [string]: {...}

	by_status: {
		for name, res in Resources if res.status != _|_ {
			"\(res.status)": (name): res
		}
	}

	// Count per status
	counts: {
		for status, members in by_status {
			"\(status)": len(members)
		}
	}
}

// #ImpactAnalysisProjection - Shows what depends on given targets
// Usage: pattern & {Targets: ["technitium", "caddy"]}
#ImpactAnalysisProjection: {
	Resources: [string]: {...}
	Targets: [...string]

	// Resources on target nodes (by host field)
	_by_host: {
		for name, res in Resources if res.host != _|_ {
			for target in Targets if res.host == target {
				"\(name)": {
					resource:   res
					depends_on: target
				}
			}
		}
	}

	// Resources on target nodes (by node field, if no host)
	_by_node: {
		for name, res in Resources if res.host == _|_ && res.node != _|_ {
			for target in Targets if res.node == target {
				"\(name)": {
					resource:   res
					depends_on: target
				}
			}
		}
	}

	affected: _by_host & _by_node

	// Count of affected resources
	count: len(affected)
}
