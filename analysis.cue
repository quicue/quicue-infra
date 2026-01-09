// Analysis patterns for infrastructure comparison and risk assessment
//
// Environment diff, change simulation, redundancy checking
//
// Usage:
//   import "quicue.ca/infra"
//
//   diff: infra.#EnvironmentDiff & {Source: prod, Target: staging}

package infra

import "list"

// #EnvironmentDiff - Compare two environments and find differences
#EnvironmentDiff: {
	SourceName: string | *"source"
	TargetName: string | *"target"
	Source:     _
	Target:     _

	// Resources only in source
	only_in_source: [
		for name, _ in Source
		if Target[name] == _|_ {name},
	]

	// Resources only in target
	only_in_target: [
		for name, _ in Target
		if Source[name] == _|_ {name},
	]

	// Resources in both but different
	differences: {
		for name, src in Source
		if Target[name] != _|_ {
			let tgt = Target[name]
			if src != tgt {
				"\(name)": {
					// Compare common fields
					if src.cores != _|_ && tgt.cores != _|_ && src.cores != tgt.cores {
						cores: {source: src.cores, target: tgt.cores}
					}
					if src.memory != _|_ && tgt.memory != _|_ && src.memory != tgt.memory {
						memory: {source: src.memory, target: tgt.memory}
					}
					if src.disk != _|_ && tgt.disk != _|_ && src.disk != tgt.disk {
						disk: {source: src.disk, target: tgt.disk}
					}
					if src.image != _|_ && tgt.image != _|_ && src.image != tgt.image {
						image: {source: src.image, target: tgt.image}
					}
					if src.version != _|_ && tgt.version != _|_ && src.version != tgt.version {
						version: {source: src.version, target: tgt.version}
					}
				}
			}
		}
	}

	// Parity metrics
	_total: len([for k, _ in Source {k}])
	_missing: len(only_in_source)
	_extra: len(only_in_target)
	_drifted: len([for k, _ in differences {k}])

	summary: {
		total_in_source:    _total
		missing_in_target:  _missing
		extra_in_target:    _extra
		configuration_drift: _drifted
		parity_percentage:  (_total - _missing - _drifted) * 100 / _total
	}
}

// #ChangeSimulation - Simulate blocking a port or taking down a resource
#ChangeSimulation: {
	Resources: [string]: {
		ports?: {inbound?: [...int], outbound?: [...int]}
		connects_to?: {[string]: true}
		...
	}

	// Simulate blocking a port
	BlockPort: {
		port: int

		// Who uses this port outbound?
		affected_sources: [
			for name, res in Resources
			if res.ports != _|_
			if res.ports.outbound != _|_
			if list.Contains(res.ports.outbound, port) {name},
		]

		// Who listens on this port?
		affected_targets: [
			for name, res in Resources
			if res.ports != _|_
			if res.ports.inbound != _|_
			if list.Contains(res.ports.inbound, port) {name},
		]

		// Connections that would break
		broken_connections: [
			for name, res in Resources
			if res.ports != _|_
			if res.ports.outbound != _|_
			if list.Contains(res.ports.outbound, port)
			if res.connects_to != _|_ {
				source: name
				targets: [
					for target, _ in res.connects_to
					if Resources[target] != _|_
					if Resources[target].ports != _|_
					if Resources[target].ports.inbound != _|_
					if list.Contains(Resources[target].ports.inbound, port) {target},
				]
			},
		]

		impact: {
			sources_affected:      len(affected_sources)
			endpoints_unreachable: len(affected_targets)
			severity: [
				if len(affected_sources) > 3 {"critical"},
				if len(affected_sources) > 1 {"high"},
				if len(affected_sources) > 0 {"medium"},
				"none",
			][0]
		}
	}

	// Simulate taking down a resource
	TakeDown: {
		target: string

		// Who connects to this?
		direct_dependents: [
			for name, res in Resources
			if res.connects_to != _|_
			if res.connects_to[target] != _|_ {name},
		]

		// Cascade: Who depends on the direct dependents?
		cascade_level_2: [
			for name, res in Resources
			if res.connects_to != _|_
			if len([for dep in direct_dependents if res.connects_to[dep] != _|_ {dep}]) > 0 {name},
		]

		impact: {
			direct:  len(direct_dependents)
			cascade: len(cascade_level_2)
			total:   len(direct_dependents) + len(cascade_level_2)
		}
	}
}

// #RedundancyCheck - Find single points of failure without replicas
#RedundancyCheck: {
	Resources: [string]: {
		replica?:    string
		replica_of?: string
		depends?:    {[string]: true}
		...
	}

	// Resources with replicas (primary side)
	has_replica: [
		for name, res in Resources
		if res.replica != _|_ {name},
	]

	// Resources that ARE replicas
	is_replica: [
		for name, res in Resources
		if res.replica_of != _|_ {name},
	]

	// Resources without any redundancy (not primary, not replica)
	single_point_failures: [
		for name, res in Resources
		if res.replica == _|_
		if res.replica_of == _|_ {name},
	]

	// Count dependents for each SPF to assess risk
	spf_risk: [
		for spf in single_point_failures {
			name: spf
			dependent_count: len([
				for _, res in Resources
				if res.depends != _|_
				if res.depends[spf] != _|_ {1},
			])
		},
	]

	// High risk = SPF with dependents
	high_risk: [for r in spf_risk if r.dependent_count > 0 {r}]
	low_risk:  [for r in spf_risk if r.dependent_count == 0 {r}]

	_total:    len([for k, _ in Resources {k}])
	_with_red: len(has_replica)
	_is_rep:   len(is_replica)
	_spf:      len(single_point_failures)
	_high:     len(high_risk)

	summary: {
		total_resources:       _total
		with_redundancy:       _with_red + _is_rep
		single_point_failures: _spf
		high_risk_spf:         _high
		redundancy_coverage:   "\(_with_red + _is_rep)/\(_total)"
	}
}
