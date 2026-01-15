// Capacity planning patterns for infrastructure graphs
//
// Node utilization tracking, workload placement, rebalancing suggestions
//
// Usage:
//   import "quicue.ca/infra"
//
//   util: infra.#NodeUtilization & {Nodes: hypervisors, Workloads: vms}
//   fit: infra.#CanFit & {Nodes: hypervisors, Workloads: vms, Request: {cores: 8, memory: 16384, disk: 200}}

package infra

import "list"

// #NodeCapacity - Track capacity for a single hypervisor node
// Use within #NodeUtilization for full analysis
#NodeCapacity: {
	cores_total:   int & >0
	memory_total:  int & >0 // MB
	storage_total: int & >0 // GB

	// Computed usage (set by #NodeUtilization)
	cores_used:   int | *0
	memory_used:  int | *0
	storage_used: int | *0

	// Available
	cores_free:   cores_total - cores_used
	memory_free:  memory_total - memory_used
	storage_free: storage_total - storage_used

	// Utilization percentages
	cores_pct:   cores_used * 100 / cores_total
	memory_pct:  memory_used * 100 / memory_total
	storage_pct: storage_used * 100 / storage_total

	// Health status
	status: ("overloaded" | "busy" | "healthy") & [
		if cores_pct > 80 || memory_pct > 80 {"overloaded"},
		if cores_pct > 60 || memory_pct > 60 {"busy"},
		"healthy",
	][0]
}

// #NodeUtilization - Calculate per-node utilization from workloads
//
// Usage:
//   util: #NodeUtilization & {
//       Nodes: {pve1: {cores_total: 64, memory_total: 131072, storage_total: 2000}}
//       Workloads: {web: {node: "pve1", cores: 4, memory: 8192, disk: 100}}
//   }
//   // util.utilization.pve1.cores_pct = 6
//   // util.utilization.pve1.status = "healthy"
//
#NodeUtilization: {
	Nodes: [string]: {
		cores_total:   int
		memory_total:  int
		storage_total: int
		...
	}

	Workloads: [string]: {
		node?:  string
		host?:  string
		cores:  int
		memory: int
		disk:   int
		...
	}

	// Get effective node for a workload (supports both host and node fields)
	_getNode: {
		for wname, w in Workloads {
			(wname): [
				if w.host != _|_ {w.host},
				if w.node != _|_ {w.node},
				"",
			][0]
		}
	}

	// Calculate utilization per node
	utilization: {
		for nodeName, nodeSpec in Nodes {
			(nodeName): {
				#NodeCapacity & {
					cores_total:   nodeSpec.cores_total
					memory_total:  nodeSpec.memory_total
					storage_total: nodeSpec.storage_total

					cores_used:   list.Sum([for wname, w in Workloads if _getNode[wname] == nodeName {w.cores}])
					memory_used:  list.Sum([for wname, w in Workloads if _getNode[wname] == nodeName {w.memory}])
					storage_used: list.Sum([for wname, w in Workloads if _getNode[wname] == nodeName {w.disk}])
				}

				// Workload count
				vm_count: len([for wname, _ in Workloads if _getNode[wname] == nodeName {1}])
			}
		}
	}

	// Alerts
	alerts: {
		overloaded_nodes: [for nodeName, util in utilization if util.status == "overloaded" {nodeName}]
		busy_nodes:       [for nodeName, util in utilization if util.status == "busy" {nodeName}]
	}
}

// #ClusterCapacity - Aggregate capacity across all nodes
//
// Usage:
//   cluster: #ClusterCapacity & {Nodes: hypervisors, Workloads: vms}
//   // cluster.summary.free_cores = 48
//   // cluster.summary.overall_utilization.cores_pct = 25
//
#ClusterCapacity: {
	Nodes: [string]: {
		cores_total:   int
		memory_total:  int
		storage_total: int
		...
	}

	Workloads: [string]: {
		cores:  int
		memory: int
		disk:   int
		...
	}

	summary: {
		total_cores:   list.Sum([for _, n in Nodes {n.cores_total}])
		total_memory:  list.Sum([for _, n in Nodes {n.memory_total}])
		total_storage: list.Sum([for _, n in Nodes {n.storage_total}])

		used_cores:   list.Sum([for _, w in Workloads {w.cores}])
		used_memory:  list.Sum([for _, w in Workloads {w.memory}])
		used_storage: list.Sum([for _, w in Workloads {w.disk}])

		free_cores:   total_cores - used_cores
		free_memory:  total_memory - used_memory
		free_storage: total_storage - used_storage

		overall_utilization: {
			// Guard against division by zero
			cores_pct: [
				if total_cores > 0 {used_cores * 100 / total_cores},
				0,
			][0]
			memory_pct: [
				if total_memory > 0 {used_memory * 100 / total_memory},
				0,
			][0]
			storage_pct: [
				if total_storage > 0 {used_storage * 100 / total_storage},
				0,
			][0]
		}

		workload_count: len(Workloads)
		node_count:     len(Nodes)
	}
}

// #CanFit - Find nodes where a workload can fit
//
// Usage:
//   fit: #CanFit & {
//       Nodes: hypervisors
//       Workloads: vms
//       Request: {cores: 16, memory: 65536, disk: 500}
//   }
//   // fit.candidates = [{node: "pve2", headroom: 32}, ...]
//   // fit.best_fit = "pve2"
//
#CanFit: {
	Nodes: [string]: {
		cores_total:   int
		memory_total:  int
		storage_total: int
		...
	}

	Workloads: [string]: {
		node?:  string
		host?:  string
		cores:  int
		memory: int
		disk:   int
		...
	}

	Request: {
		cores:  int
		memory: int
		disk:   int
	}

	// Use #NodeUtilization to get current state
	_util: #NodeUtilization & {"Nodes": Nodes, "Workloads": Workloads}

	// Find nodes with enough capacity
	candidates: [
		for nodeName, util in _util.utilization
		if util.cores_free >= Request.cores
		if util.memory_free >= Request.memory
		if util.storage_free >= Request.disk {
			node:         nodeName
			cores_after:  util.cores_pct + (Request.cores * 100 / Nodes[nodeName].cores_total)
			memory_after: util.memory_pct + (Request.memory * 100 / Nodes[nodeName].memory_total)
			headroom:     util.cores_free - Request.cores
		},
	]

	// Best fit = node with most headroom after placement
	_sorted: list.Sort(candidates, {x: {}, y: {}, less: x.headroom > y.headroom})
	best_fit: [
		if len(_sorted) > 0 {_sorted[0].node},
		"", // No fit possible
	][0]

	can_place: len(candidates) > 0
}

// #BestFit - Find optimal placement for multiple workloads
//
// Usage:
//   placement: #BestFit & {
//       Nodes: hypervisors
//       Workloads: existing_vms
//       NewWorkloads: [
//           {name: "new-web", cores: 4, memory: 8192, disk: 100},
//           {name: "new-db", cores: 16, memory: 65536, disk: 500},
//       ]
//   }
//   // placement.placements = [{workload: "new-web", node: "pve2"}, ...]
//
#BestFit: {
	Nodes: [string]: {
		cores_total:   int
		memory_total:  int
		storage_total: int
		...
	}

	Workloads: [string]: {
		node?:  string
		host?:  string
		cores:  int
		memory: int
		disk:   int
		...
	}

	NewWorkloads: [...{
		name:   string
		cores:  int
		memory: int
		disk:   int
	}]

	// Sort by size (largest first for better bin packing)
	_sortedNew: list.Sort(NewWorkloads, {x: {}, y: {}, less: x.cores > y.cores})

	// Find placement for each (simple greedy - doesn't track cumulative placement)
	placements: [
		for w in _sortedNew {
			let _fit = #CanFit & {
				"Nodes":     Nodes
				"Workloads": Workloads
				Request: {cores: w.cores, memory: w.memory, disk: w.disk}
			}
			workload: w.name
			node:     _fit.best_fit
			possible: _fit.can_place
		},
	]

	// Summary
	placeable:   len([for p in placements if p.possible {1}])
	unplaceable: len([for p in placements if !p.possible {1}])
}

// #RebalanceSuggestions - Suggest moves to balance overloaded nodes
//
// Usage:
//   rebalance: #RebalanceSuggestions & {Nodes: hypervisors, Workloads: vms}
//   // rebalance.suggestions = [{vm: "web-1", from: "pve1", to: "pve2"}, ...]
//
#RebalanceSuggestions: {
	Nodes: [string]: {
		cores_total:   int
		memory_total:  int
		storage_total: int
		...
	}

	Workloads: [string]: {
		node?:  string
		host?:  string
		cores:  int
		memory: int
		disk:   int
		...
	}

	_util: #NodeUtilization & {"Nodes": Nodes, "Workloads": Workloads}

	// Get effective node for a workload
	_getNode: {
		for wname, w in Workloads {
			(wname): [
				if w.host != _|_ {w.host},
				if w.node != _|_ {w.node},
				"",
			][0]
		}
	}

	// Find workloads on overloaded nodes and suggest moves
	suggestions: [
		for wname, w in Workloads
		if _util.utilization[_getNode[wname]] != _|_
		if _util.utilization[_getNode[wname]].status == "overloaded" {
			let _fit = #CanFit & {
				"Nodes":     Nodes
				"Workloads": Workloads
				Request: {cores: w.cores, memory: w.memory, disk: w.disk}
			}
			// Exclude current node from candidates
			let _otherCandidates = [for c in _fit.candidates if c.node != _getNode[wname] {c}]
			if len(_otherCandidates) > 0 {
				vm:   wname
				from: _getNode[wname]
				to:   list.Sort(_otherCandidates, {x: {}, y: {}, less: x.headroom > y.headroom})[0].node
			}
		},
	]

	summary: {
		overloaded_nodes: len(_util.alerts.overloaded_nodes)
		suggested_moves:  len(suggestions)
	}
}
