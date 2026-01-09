// Generator patterns for configuration file output
//
// Ansible inventory, Prometheus targets, and other config formats
//
// Usage:
//   import "quicue.ca/infra"
//
//   inventory: infra.#AnsibleInventory & {Resources: myInfraGraph}

package infra

// #AnsibleInventory - Generate Ansible inventory structure from resources
#AnsibleInventory: {
	Resources: [string]: {
		ip?:      string
		ssh_user?: string
		user?:    string
		tags?:    {[string]: true}
		vmid?:    int
		vm_id?:   int
		node?:    string
		host?:    string
		...
	}

	// Build hosts with ansible variables
	all: {
		hosts: {
			for name, res in Resources
			if res.ip != _|_ {
				"\(name)": {
					ansible_host: res.ip
					ansible_user: res.ssh_user | *res.user | *"root"
					if res.vmid != _|_ {vmid: res.vmid}
					if res.vm_id != _|_ {vmid: res.vm_id}
					if res.node != _|_ {pve_node: res.node}
					if res.host != _|_ {pve_node: res.host}
				}
			}
		}

		// Group by tags
		children: {
			// Extract unique tags
			let _all_tags = {
				for _, res in Resources
				if res.tags != _|_ {
					for tag, _ in res.tags {
						"\(tag)": true
					}
				}
			}
			for tag, _ in _all_tags {
				"\(tag)": hosts: {
					for name, res in Resources
					if res.tags != _|_
					if res.tags[tag] != _|_ {
						"\(name)": {}
					}
				}
			}
		}
	}
}

// #PrometheusTargets - Generate Prometheus static_configs targets
#PrometheusTargets: {
	Resources: [string]: {
		ip?:    string
		tags?:  {[string]: true}
		node?:  string
		host?:  string
		...
	}
	Port: int | *9100 // Default node_exporter port

	targets: [
		for name, res in Resources
		if res.ip != _|_ {
			targets: ["\(res.ip):\(Port)"]
			labels: {
				instance: name
				if res.node != _|_ {node: res.node}
				if res.host != _|_ {node: res.host}
				if res.tags != _|_ {
					for tag, _ in res.tags {
						"\(tag)": "true"
					}
				}
			}
		},
	]
}

// #AlertManagerRoutes - Generate AlertManager routing tree from resource metadata
#AlertManagerRoutes: {
	Resources: [string]: {
		owner?:     string
		severity?:  string
		team?:      string
		...
	}

	// Group by owner/team for routing
	_by_owner: {
		for _, res in Resources
		if res.owner != _|_ {
			"\(res.owner)": true
		}
	}

	routes: [
		for owner, _ in _by_owner {
			match: {owner: owner}
			receiver: "\(owner)-receiver"
			resources: [
				for name, res in Resources
				if res.owner != _|_
				if res.owner == owner {name},
			]
		},
	]
}

// #GrafanaDashboard - Generate basic Grafana dashboard JSON structure
#GrafanaDashboard: {
	Resources: [string]: {
		ip?:   string
		name?: string
		...
	}
	Title: string | *"Infrastructure Overview"

	dashboard: {
		title:         Title
		schemaVersion: 30
		panels: [
			for i, res in [for n, r in Resources if r.ip != _|_ {name: n, ip: r.ip}] {
				id:    i + 1
				title: res.name
				type:  "stat"
				targets: [{
					expr: "up{instance=\"\(res.ip):9100\"}"
				}]
				gridPos: {
					h: 4
					w: 6
					x: 0
					y: i * 4
				}
			},
		]
	}
}
