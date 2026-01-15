// Cost modeling and chargeback patterns for infrastructure graphs
//
// Resource costing, team chargeback, what-if scenarios
//
// Usage:
//   import "quicue.ca/infra"
//
//   costs: infra.#ResourceCosts & {Resources: vms, Pricing: myPricing}
//   chargeback: infra.#Chargeback & {Resources: vms, Pricing: myPricing, GroupBy: "owner"}

package infra

import "list"

// #Pricing - Standard pricing model for compute resources
// Override with your actual rates
#Pricing: {
	core_cost:    *10.00 | number  // per vCPU per month
	memory_cost:  *5.00 | number   // per GB RAM per month
	storage_cost: *0.10 | number   // per GB disk per month
	backup_cost:  *0.05 | number   // per GB backed up per month
	license_cost: {
		windows:  *50.00 | number
		rhel:     *30.00 | number
		ubuntu:   *0.00 | number
		linux:    *0.00 | number
		debian:   *0.00 | number
		centos:   *0.00 | number
		rocky:    *0.00 | number
		alma:     *0.00 | number
		[string]: number  // other OSes must provide explicit cost
	}
}

// #ResourceCost - Calculate cost for a single resource
#ResourceCost: {
	Pricing: #Pricing
	Resource: {
		cores?:     int
		memory_gb?: int
		disk_gb?:   int
		memory?:    int // MB fallback
		disk?:      int // GB fallback
		os?:        string
		backup?:    bool
		...
	}

	// Normalize memory to GB
	_mem_gb: [
		if Resource.memory_gb != _|_ {Resource.memory_gb},
		if Resource.memory != _|_ {Resource.memory / 1024}, // MB to GB
		0,
	][0]

	// Normalize disk to GB
	_disk_gb: [
		if Resource.disk_gb != _|_ {Resource.disk_gb},
		if Resource.disk != _|_ {Resource.disk},
		0,
	][0]

	// Costs
	_cores: [if Resource.cores != _|_ {Resource.cores}, 0][0]
	_os: [if Resource.os != _|_ {Resource.os}, "linux"][0]
	_backup: [if Resource.backup != _|_ && Resource.backup {1}, 0][0]

	compute: _cores * Pricing.core_cost + _mem_gb * Pricing.memory_cost
	storage: _disk_gb * Pricing.storage_cost
	backup:  _disk_gb * Pricing.backup_cost * _backup
	license: Pricing.license_cost[_os]
	total:   compute + storage + backup + license
}

// #ResourceCosts - Calculate costs for all resources
//
// Usage:
//   costs: #ResourceCosts & {
//       Resources: {
//           web: {cores: 4, memory_gb: 8, disk_gb: 100, os: "ubuntu", backup: true}
//           db: {cores: 16, memory_gb: 64, disk_gb: 1000, os: "rhel", backup: true}
//       }
//       Pricing: #Pricing
//   }
//   // costs.costs.web.total = 95.0
//   // costs.summary.total_monthly = 1270.0
//
#ResourceCosts: {
	Resources: [string]: {
		cores?:     int
		memory_gb?: int
		disk_gb?:   int
		memory?:    int
		disk?:      int
		os?:        string
		backup?:    bool
		...
	}

	Pricing: #Pricing

	// Calculate cost per resource
	costs: {
		for name, res in Resources {
			(name): #ResourceCost & {"Pricing": Pricing, Resource: res}
		}
	}

	// Summary
	summary: {
		total_monthly: list.Sum([for _, c in costs {c.total}])
		by_category: {
			compute: list.Sum([for _, c in costs {c.compute}])
			storage: list.Sum([for _, c in costs {c.storage}])
			backup:  list.Sum([for _, c in costs {c.backup}])
			license: list.Sum([for _, c in costs {c.license}])
		}
		resource_count: len(Resources)
		avg_cost_per_resource: [
			if len(Resources) > 0 {total_monthly / len(Resources)},
			0,
		][0]
	}
}

// #Chargeback - Group costs by owner, team, or cost center
//
// Usage:
//   byOwner: #Chargeback & {
//       Resources: vms
//       Pricing: #Pricing
//       GroupBy: "owner"
//   }
//   // byOwner.groups["platform-team"].monthly_cost = 450.0
//   // byOwner.groups["platform-team"].resources = ["web-1", "web-2"]
//
#Chargeback: {
	Resources: [string]: {
		owner?:       string
		cost_center?: string
		team?:        string
		...
	}

	Pricing: #Pricing
	GroupBy: "owner" | "cost_center" | "team" | *"owner"

	_costs: (#ResourceCosts & {"Resources": Resources, "Pricing": Pricing}).costs

	// Get the grouping key for each resource
	_getGroup: {
		for name, res in Resources {
			(name): [
				if GroupBy == "owner" && res.owner != _|_ {res.owner},
				if GroupBy == "cost_center" && res.cost_center != _|_ {res.cost_center},
				if GroupBy == "team" && res.team != _|_ {res.team},
				"unassigned",
			][0]
		}
	}

	// Extract unique groups
	_groupSet: {
		for name, group in _getGroup {
			(group): true
		}
	}

	groups: {
		for group, _ in _groupSet {
			(group): {
				resources: [for name, g in _getGroup if g == group {name}]
				monthly_cost: list.Sum([for name, g in _getGroup if g == group {_costs[name].total}])
				breakdown: {
					compute: list.Sum([for name, g in _getGroup if g == group {_costs[name].compute}])
					storage: list.Sum([for name, g in _getGroup if g == group {_costs[name].storage}])
					backup:  list.Sum([for name, g in _getGroup if g == group {_costs[name].backup}])
					license: list.Sum([for name, g in _getGroup if g == group {_costs[name].license}])
				}
				resource_count: len(resources)
			}
		}
	}

	// Top spenders
	_groupList: [for group, data in groups {{name: group, cost: data.monthly_cost}}]
	_sorted: list.Sort(_groupList, {x: {}, y: {}, less: x.cost > y.cost})
	top_spenders: [for g in _sorted {g.name}]

	summary: {
		total_monthly: list.Sum([for _, g in groups {g.monthly_cost}])
		group_count:   len(groups)
		highest_cost: [
			if len(_sorted) > 0 {{group: _sorted[0].name, cost: _sorted[0].cost}},
			{group: "", cost: 0},
		][0]
	}
}

// #WhatIfCost - Calculate cost impact of adding resources
//
// Usage:
//   scenario: #WhatIfCost & {
//       CurrentResources: existing_vms
//       Pricing: #Pricing
//       Description: "Add 3 web servers"
//       AddResources: [
//           {cores: 4, memory_gb: 8, disk_gb: 100, os: "ubuntu", backup: true},
//           {cores: 4, memory_gb: 8, disk_gb: 100, os: "ubuntu", backup: true},
//           {cores: 4, memory_gb: 8, disk_gb: 100, os: "ubuntu", backup: true},
//       ]
//   }
//   // scenario.projected.additional_monthly = 285.0
//   // scenario.projected.increase_percent = 15.2
//
#WhatIfCost: {
	CurrentResources: [string]: {...}
	Pricing:          #Pricing
	Description:      string | *"What-if scenario"

	AddResources: [...{
		cores?:     int
		memory_gb?: int
		disk_gb?:   int
		memory?:    int
		disk?:      int
		os?:        string
		backup?:    bool
	}]

	// Current state
	_current: #ResourceCosts & {"Resources": CurrentResources, "Pricing": Pricing}

	// Calculate cost of new resources
	_newCosts: [
		for i, res in AddResources {
			(#ResourceCost & {"Pricing": Pricing, Resource: res}).total
		},
	]

	projected: {
		current_monthly:    _current.summary.total_monthly
		additional_monthly: list.Sum(_newCosts)
		projected_monthly:  current_monthly + additional_monthly
		increase_percent: [
			if current_monthly > 0 {additional_monthly / current_monthly * 100},
			0,
		][0]
		new_resource_count: len(AddResources)
	}

	breakdown: {
		per_new_resource: [
			for i, res in AddResources {
				index: i
				cost:  _newCosts[i]
			},
		]
		avg_new_cost: [
			if len(AddResources) > 0 {projected.additional_monthly / len(AddResources)},
			0,
		][0]
	}
}

// #CostTrend - Compare costs across time periods or configurations
//
// Usage:
//   trend: #CostTrend & {
//       Periods: {
//           "2024-Q1": {Resources: q1_vms, Pricing: pricing}
//           "2024-Q2": {Resources: q2_vms, Pricing: pricing}
//       }
//   }
//   // trend.periods["2024-Q1"].total = 5000.0
//   // trend.growth["2024-Q2"].change = 500.0
//
#CostTrend: {
	Periods: [string]: {
		Resources: [string]: {...}
		Pricing: #Pricing
	}

	// Calculate each period
	periods: {
		for pname, p in Periods {
			(pname): (#ResourceCosts & {"Resources": p.Resources, "Pricing": p.Pricing}).summary
		}
	}

	// Period names in order (alphabetical)
	_periodNames: [for p, _ in periods {p}]
	_sortedPeriods: list.Sort(_periodNames, {x: "", y: "", less: x < y})

	// Calculate period-over-period changes
	growth: {
		for i, pname in _sortedPeriods if i > 0 {
			let prev = _sortedPeriods[i-1]
			(pname): {
				previous:       prev
				previous_total: periods[prev].total_monthly
				current_total:  periods[pname].total_monthly
				change:         current_total - previous_total
				change_percent: [
					if previous_total > 0 {change / previous_total * 100},
					0,
				][0]
			}
		}
	}
}
