// Operational patterns for infrastructure management
//
// Migration planning, orphan detection, cleanup recommendations
//
// Usage:
//   import "quicue.ca/infra"
//
//   plan: infra.#MigrationPlan & {Resources: vms, Source: "pve1", Target: "pve2"}

package infra

import "list"

// #MigrationPlan - Generate ordered migration commands for node evacuation
#MigrationPlan: {
	Resources: [string]: {
		node?:     string
		host?:     string
		vmid?:     int
		vm_id?:    int
		cores?:    int
		memory?:   int
		priority?: int
		...
	}
	Source: string
	Target: string

	// VMs to migrate (on source node via host field)
	_vms_to_move: [
		for name, res in Resources
		if res.host != _|_
		if res.host == Source {
			_name:     name
			_vmid:     res.vmid | *res.vm_id | *0
			_cores:    res.cores | *0
			_memory:   res.memory | *0
			_priority: res.priority | *5
		},
	]

	// Sorted by priority (lower = migrate first)
	order: list.Sort(_vms_to_move, {x: {}, y: {}, less: x._priority < y._priority})

	// Generate commands
	commands: [
		for vm in order if vm._vmid > 0 {
			step:       "Migrate \(vm._name) (VMID \(vm._vmid))"
			pre_check:  "qm status \(vm._vmid)"
			migrate:    "qm migrate \(vm._vmid) \(Target) --online"
			post_check: "ssh \(Target) 'qm status \(vm._vmid)'"
			rollback:   "qm migrate \(vm._vmid) \(Source) --online"
		},
	]

	// Resource summary
	total_cores:  list.Sum([for vm in _vms_to_move {vm._cores}])
	total_memory: list.Sum([for vm in _vms_to_move {vm._memory}])
	vm_count:     len(_vms_to_move)
}

// #OrphanDetection - Find unused, unowned, or stale resources
#OrphanDetection: {
	Resources: [string]: {...}

	// Helper: check if resource has used_by entries
	_has_users: {
		for name, res in Resources if res.used_by != _|_ {
			if len([for k, _ in res.used_by {k}]) > 0 {
				"\(name)": true
			}
		}
	}

	// Helper: check if resource has dependencies
	_has_deps: {
		for name, res in Resources if res.depends != _|_ {
			if len([for k, _ in res.depends {k}]) > 0 {
				"\(name)": true
			}
		}
	}

	// Orphans: Not used by anything and no dependencies
	orphans: [
		for name, _ in Resources
		if _has_users[name] == _|_
		if _has_deps[name] == _|_ {name},
	]

	// Zombies: No owner or unknown owner
	zombies: [
		for name, res in Resources
		if res.owner == _|_ {name},
	]
	_zombies_unknown: [
		for name, res in Resources
		if res.owner != _|_
		if res.owner == "unknown" || res.owner == "" {name},
	]

	// Leaf nodes: Has dependencies but nothing uses them
	leaves: [
		for name, _ in Resources
		if _has_users[name] == _|_
		if _has_deps[name] != _|_ {name},
	]

	// Undocumented: No purpose field
	undocumented: [
		for name, res in Resources
		if res.purpose == _|_ {name},
	]
	_undoc_empty: [
		for name, res in Resources
		if res.purpose != _|_
		if res.purpose == "" {name},
	]

	// Cost analysis
	_orphan_cost: list.Sum([
		for name, res in Resources
		if list.Contains(orphans, name)
		if res.cost != _|_ {res.cost},
	])
	_zombie_cost: list.Sum([
		for name, res in Resources
		if list.Contains(zombies, name)
		if res.cost != _|_ {res.cost},
	])
	_total_cost: list.Sum([
		for _, res in Resources
		if res.cost != _|_ {res.cost},
	])

	summary: {
		orphan_count:      len(orphans)
		zombie_count:      len(zombies)
		leaf_count:        len(leaves)
		undocumented_count: len(undocumented)
		estimated_waste:   _orphan_cost + _zombie_cost
		total_cost:        _total_cost
	}

	// Cleanup recommendations
	_orphan_recs: [
		for name in orphans {
			resource: name
			action:   "review_for_deletion"
			reason:   "orphan - not used and no dependencies"
		},
	]
	_zombie_recs: [
		for name in zombies
		if !list.Contains(orphans, name) {
			resource: name
			action:   "assign_owner"
			reason:   "zombie - no owner assigned"
		},
	]
	recommendations: list.Concat([_orphan_recs, _zombie_recs])
}
