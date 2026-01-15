// Overview patterns for infrastructure graph summaries
//
// Provides generic datacenter/cluster overview patterns that compute
// standard metrics from any infrastructure graph.
//
// Usage:
//   import infra "quicue.ca/infra"
//
//   overview: infra.#DCOverview & {
//       Graph: myInfraGraph
//       metadata: {name: "my-cluster", domain: "example.com"}
//   }

package infra

import patterns "quicue.ca/patterns"

// #DCOverview - Generic datacenter overview pattern
// Computes standard metrics from any infrastructure graph
#DCOverview: {
	// Required input - the infrastructure graph
	Graph: patterns.#InfraGraph

	// User-provided metadata (cluster-specific)
	metadata: {
		name:   string
		domain: string | *""
		[string]: _ // Allow additional metadata
	}

	// Computed from Graph (generic)
	metrics: patterns.#GraphMetrics & {"Graph": Graph}
	by_type: (patterns.#GroupByType & {"Graph": Graph}).groups
	criticality: (patterns.#CriticalityRank & {"Graph": Graph}).ranked

	roots:       Graph.roots
	leaves:      Graph.leaves
	layers:      Graph.topology
	layer_count: len(Graph.topology)

	// Summary for dashboards
	summary: {
		name:      metadata.name
		resources: metrics.total_resources
		roots:     metrics.root_count
		leaves:    metrics.leaf_count
		max_depth: metrics.max_depth
		edges:     metrics.total_edges
		layers:    layer_count
	}

	// Allow extensions
	...
}
