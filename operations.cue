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

	// VMs to migrate (on source node)
	_vms_to_move: [
		for name, res in Resources
		if (res.node != _|_ && res.node == Source) ||
			(res.host != _|_ && res.host == Source) {
			let _vmid = res.vmid | *res.vm_id | *0
			let _priority = res.priority | *5
			{
				name:     name
				vmid:     _vmid
				cores:    res.cores | *0
				memory:   res.memory | *0
				priority: _priority
			}
		},
	]

	// Sorted by priority (lower = migrate first)
	order: list.Sort(_vms_to_move, {x: {}, y: {}, less: x.priority < y.priority})

	// Generate commands
	commands: [
		for vm in order if vm.vmid > 0 {
			step:       "Migrate \(vm.name) (VMID \(vm.vmid))"
			pre_check:  "qm status \(vm.vmid)"
			migrate:    "qm migrate \(vm.vmid) \(Target) --online"
			post_check: "ssh \(Target) 'qm status \(vm.vmid)'"
			rollback:   "qm migrate \(vm.vmid) \(Source) --online"
		},
	]

	// Resource summary
	total_cores:  list.Sum([for vm in _vms_to_move {vm.cores}])
	total_memory: list.Sum([for vm in _vms_to_move {vm.memory}])
	vm_count:     len(_vms_to_move)
}

// #OrphanDetection - Find unused, unowned, or stale resources
#OrphanDetection: {
	Resources: [string]: {
		owner?:    string
		purpose?:  string
		depends?:  {[string]: true}
		used_by?:  {[string]: true}
		cost?:     number
		accessed?: string
		...
	}

	// Orphans: Not used by anything and no dependencies
	orphans: [
		for name, res in Resources
		if (res.used_by == _|_ || len([for k, _ in res.used_by {k}]) == 0)
		if (res.depends == _|_ || len([for k, _ in res.depends {k}]) == 0) {name},
	]

	// Zombies: No owner or unknown owner
	zombies: [
		for name, res in Resources
		if res.owner == _|_ || res.owner == "unknown" || res.owner == "" {name},
	]

	// Leaf nodes: Has dependencies but nothing uses them
	leaves: [
		for name, res in Resources
		if (res.used_by == _|_ || len([for k, _ in res.used_by {k}]) == 0)
		if res.depends != _|_ && len([for k, _ in res.depends {k}]) > 0 {name},
	]

	// Undocumented: No purpose field
	undocumented: [
		for name, res in Resources
		if res.purpose == _|_ || res.purpose == "" {name},
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
