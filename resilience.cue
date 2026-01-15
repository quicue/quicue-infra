// Resilience analysis patterns for infrastructure graphs
//
// Fan-in analysis, bottleneck detection, cascade failure simulation
//
// Usage:
//   import "quicue.ca/infra"
//
//   bottleneck: infra.#BottleneckAnalysis & {Resources: graph}
//   cascade: infra.#CascadeAnalysis & {Resources: graph, FailedResource: "dns"}

package infra

import "list"

// #FanIn - Count incoming dependencies for a single target
//
// Usage:
//   fanIn: #FanIn & {Resources: graph, Target: "dns"}
//   // fanIn.count = 5
//   // fanIn.dependents = ["web", "api", "auth", ...]
//
#FanIn: {
	Resources: [string]: {
		depends?:    [...string]
		depends_on?: {[string]: true}
		...
	}

	Target: string

	// Support both depends (list) and depends_on (struct) formats
	_hasDependency: {
		for rname, res in Resources {
			(rname): [
				// Check list format
				if res.depends != _|_ {list.Contains(res.depends, Target)},
				// Check struct format
				if res.depends_on != _|_ {res.depends_on[Target] != _|_},
				false,
			][0]
		}
	}

	dependents: [for rname, hasDep in _hasDependency if hasDep {rname}]
	count: len(dependents)
}

// #BottleneckAnalysis - Identify resources with high fan-in
//
// Resources with many dependents are potential bottlenecks/SPOFs.
// Higher fan-in = more things break when this fails.
//
// Usage:
//   analysis: #BottleneckAnalysis & {
//       Resources: graph
//       CriticalThreshold: 3  // fan-in >= 3 is critical
//   }
//   // analysis.critical = ["dns", "db"]
//   // analysis.ranked = [{name: "dns", fan_in: 5}, ...]
//
#BottleneckAnalysis: {
	Resources: [string]: {
		depends?:    [...string]
		depends_on?: {[string]: true}
		...
	}

	CriticalThreshold:  int | *3 // Fan-in at or above this is critical
	ImportantThreshold: int | *1 // Fan-in at or above this is important

	// Calculate fan-in for each resource
	_fanInMap: {
		for rname, _ in Resources {
			(rname): (#FanIn & {"Resources": Resources, Target: rname}).count
		}
	}

	// Ranked list (highest fan-in first)
	_ranked: [for rname, count in _fanInMap {{name: rname, fan_in: count}}]
	ranked: list.Sort(_ranked, {x: {}, y: {}, less: x.fan_in > y.fan_in})

	// Categorize by criticality
	critical: [
		for rname, count in _fanInMap
		if count >= CriticalThreshold {rname},
	]

	important: [
		for rname, count in _fanInMap
		if count >= ImportantThreshold && count < CriticalThreshold {rname},
	]

	leaves: [
		for rname, count in _fanInMap
		if count == 0 {rname},
	]

	// Helper: check if resource has dependencies
	_hasDeps: {
		for rname, res in Resources {
			(rname): [
				if res.depends != _|_ {len(res.depends) > 0},
				if res.depends_on != _|_ {len([for k, _ in res.depends_on {k}]) > 0},
				false,
			][0]
		}
	}

	// Resources with no outgoing dependencies (roots)
	roots: [for rname, hasDeps in _hasDeps if !hasDeps {rname}]

	summary: {
		total_resources:  len(Resources)
		critical_count:   len(critical)
		important_count:  len(important)
		leaf_count:       len(leaves)
		root_count:       len(roots)
		max_fan_in:       [if len(ranked) > 0 {ranked[0].fan_in}, 0][0]
		highest_fan_in:   [if len(ranked) > 0 {ranked[0].name}, ""][0]
	}
}

// #CascadeAnalysis - Simulate cascade failure from a resource going down
//
// Shows the domino effect: if X fails, what else fails in waves?
// Wave 0: initial failure, Wave 1: direct dependents, Wave 2+: indirect dependents
//
// Usage:
//   cascade: #CascadeAnalysis & {
//       Resources: graph
//       FailedResource: "san"
//   }
//   // cascade.waves = [{wave: 0, failed: ["san"]}, {wave: 1, failed: ["hypervisor", "database"]}, ...]
//   // cascade.total_affected = 8
//
#CascadeAnalysis: {
	Resources: [string]: {
		depends?:    [...string]
		depends_on?: {[string]: true}
		...
	}

	FailedResource: string
	MaxWaves:       int | *5 // Safety limit on cascade depth

	// Helper: check if resource depends on any in failed set
	_dependsOnAny: {
		for rname, res in Resources {
			(rname): {
				[failedSet=string]: bool
			}
		}
	}

	// Get dependencies as list for uniform handling
	_getDeps: {
		for rname, res in Resources {
			(rname): [
				// List format
				if res.depends != _|_ {res.depends},
				// Struct format - convert to list
				if res.depends_on != _|_ {[for k, _ in res.depends_on {k}]},
				[],
			][0]
		}
	}

	// Wave 0: initial failure
	_wave0: [FailedResource]

	// Wave 1: direct dependents of wave 0
	_wave1: [
		for rname, _ in Resources
		if !list.Contains(_wave0, rname)
		if len([for dep in _getDeps[rname] if list.Contains(_wave0, dep) {dep}]) > 0 {rname},
	]
	_failed1: list.Concat([_wave0, _wave1])

	// Wave 2: dependents of wave 0 + wave 1
	_wave2: [
		for rname, _ in Resources
		if !list.Contains(_failed1, rname)
		if len([for dep in _getDeps[rname] if list.Contains(_failed1, dep) {dep}]) > 0 {rname},
	]
	_failed2: list.Concat([_failed1, _wave2])

	// Wave 3: dependents of all previous waves
	_wave3: [
		for rname, _ in Resources
		if !list.Contains(_failed2, rname)
		if len([for dep in _getDeps[rname] if list.Contains(_failed2, dep) {dep}]) > 0 {rname},
	]
	_failed3: list.Concat([_failed2, _wave3])

	// Wave 4: dependents of all previous waves
	_wave4: [
		for rname, _ in Resources
		if !list.Contains(_failed3, rname)
		if len([for dep in _getDeps[rname] if list.Contains(_failed3, dep) {dep}]) > 0 {rname},
	]
	_failed4: list.Concat([_failed3, _wave4])

	// Wave 5: final wave
	_wave5: [
		for rname, _ in Resources
		if !list.Contains(_failed4, rname)
		if len([for dep in _getDeps[rname] if list.Contains(_failed4, dep) {dep}]) > 0 {rname},
	]

	// Output waves (filter empty ones)
	waves: [
		{wave: 0, failed: _wave0},
		if len(_wave1) > 0 {{wave: 1, failed: _wave1}},
		if len(_wave2) > 0 {{wave: 2, failed: _wave2}},
		if len(_wave3) > 0 {{wave: 3, failed: _wave3}},
		if len(_wave4) > 0 {{wave: 4, failed: _wave4}},
		if len(_wave5) > 0 {{wave: 5, failed: _wave5}},
	]

	// All affected resources (excluding the initial failure)
	all_affected: list.Concat([_wave1, _wave2, _wave3, _wave4, _wave5])
	_total_affected: len(all_affected) + 1 // +1 for the initial failure
	total_affected: _total_affected

	// Resources that survive
	survivors: [
		for rname, _ in Resources
		if !list.Contains(_failed4, rname)
		if !list.Contains(_wave5, rname) {rname},
	]

	summary: {
		initial_failure: FailedResource
		cascade_depth:   len(waves) - 1
		total_affected:  _total_affected
		survivor_count:  len(survivors)
		cascade_percent: [
			if len(Resources) > 0 {_total_affected * 100 / len(Resources)},
			0,
		][0]
	}
}

// #ResilienceScore - Calculate overall resilience metrics
//
// Combines bottleneck analysis with cascade simulation to produce a score.
// Lower score = more fragile infrastructure.
//
// Usage:
//   score: #ResilienceScore & {Resources: graph}
//   // score.score = 72
//   // score.assessment = "moderate"
//
#ResilienceScore: {
	Resources: [string]: {
		depends?:    [...string]
		depends_on?: {[string]: true}
		...
	}

	_bottleneck: #BottleneckAnalysis & {"Resources": Resources}

	// Calculate average cascade impact for critical resources
	_cascadeImpacts: [
		for crit in _bottleneck.critical {
			(#CascadeAnalysis & {"Resources": Resources, FailedResource: crit}).summary.cascade_percent
		},
	]
	_avgCascadeImpact: [
		if len(_cascadeImpacts) > 0 {list.Sum(_cascadeImpacts) / len(_cascadeImpacts)},
		0,
	][0]

	// Score components (0-100 scale)
	_criticalPenalty: [
		if len(Resources) > 0 {_bottleneck.summary.critical_count * 100 / len(Resources) * 2},
		0,
	][0]
	_cascadePenalty: _avgCascadeImpact

	// Final score (100 - penalties, clamped to 0-100)
	_rawScore: 100 - _criticalPenalty - _cascadePenalty
	score: [
		if _rawScore < 0 {0},
		if _rawScore > 100 {100},
		_rawScore,
	][0]

	assessment: [
		if score >= 80 {"robust"},
		if score >= 60 {"moderate"},
		if score >= 40 {"fragile"},
		"critical",
	][0]

	details: {
		critical_bottlenecks:  _bottleneck.critical
		avg_cascade_impact:    _avgCascadeImpact
		total_resources:       len(Resources)
		root_count:            _bottleneck.summary.root_count
		max_fan_in:            _bottleneck.summary.max_fan_in
	}

	recommendations: [
		if len(_bottleneck.critical) > 0 {
			"Add redundancy for critical bottlenecks: \(list.Concat([for c in _bottleneck.critical {[c]}]))"
		},
		if _avgCascadeImpact > 50 {
			"High cascade impact - consider decoupling dependencies"
		},
		if _bottleneck.summary.max_fan_in > 5 {
			"Resource '\(_bottleneck.summary.highest_fan_in)' has very high fan-in (\(_bottleneck.summary.max_fan_in)) - add failover"
		},
	]
}

// #WhatIfDown - Quick cascade check for multiple failure scenarios
//
// Usage:
//   scenarios: #WhatIfDown & {
//       Resources: graph
//       TestFailures: ["dns", "database", "san"]
//   }
//   // scenarios.impacts = [{resource: "dns", affected: 5}, ...]
//   // scenarios.worst_case = {resource: "san", affected: 8}
//
#WhatIfDown: {
	Resources: [string]: {
		depends?:    [...string]
		depends_on?: {[string]: true}
		...
	}

	TestFailures: [...string]

	impacts: [
		for target in TestFailures {
			let _cascade = #CascadeAnalysis & {"Resources": Resources, FailedResource: target}
			resource:        target
			affected:        _cascade.total_affected
			cascade_percent: _cascade.summary.cascade_percent
			waves:           len(_cascade.waves) - 1
		},
	]

	_sorted: list.Sort(impacts, {x: {}, y: {}, less: x.affected > y.affected})
	worst_case: [
		if len(_sorted) > 0 {_sorted[0]},
		{resource: "", affected: 0, cascade_percent: 0, waves: 0},
	][0]

	summary: {
		tested:           len(TestFailures)
		highest_impact:   worst_case.resource
		max_affected:     worst_case.affected
		avg_affected: [
			if len(impacts) > 0 {list.Sum([for i in impacts {i.affected}]) / len(impacts)},
			0,
		][0]
	}
}
