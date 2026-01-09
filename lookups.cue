// Reverse lookup patterns for infrastructure graphs
//
// Find resources by attribute value (IP, VLAN, port, owner, node)
//
// Usage:
//   import "quicue.ca/infra"
//
//   byIP: infra.#LookupByIP & {Resources: myInfraGraph, Target: "10.0.1.100"}

package infra

import "list"

// #LookupByIP - Find resources by IP address
#LookupByIP: {
	Resources: [string]: {ip?: string, ...}
	Target:    string

	result: {
		for name, res in Resources
		if res.ip != _|_
		if res.ip == Target {
			"\(name)": res
		}
	}
	found: len([for _, _ in result {1}]) > 0
}

// #LookupByVLAN - Find resources on a specific VLAN
#LookupByVLAN: {
	Resources: [string]: {vlan?: int, ...}
	Target:    int

	result: [
		for name, res in Resources
		if res.vlan != _|_
		if res.vlan == Target {name},
	]
}

// #LookupByPort - Find resources using a specific port
// Supports structured ports: {inbound: [...], outbound: [...]}
#LookupByPort: {
	Resources: [string]: {...}
	Target:    int

	// Check inbound ports
	_inbound: [
		for name, res in Resources
		if res.ports != _|_
		if res.ports.inbound != _|_
		if list.Contains(res.ports.inbound, Target) {name},
	]

	// Check outbound ports
	_outbound: [
		for name, res in Resources
		if res.ports != _|_
		if res.ports.outbound != _|_
		if list.Contains(res.ports.outbound, Target) {name},
	]

	// Combine and dedupe
	result: list.Concat([[for name in _inbound {name}], [for name in _outbound if !list.Contains(_inbound, name) {name}]])
}

// #LookupByOwner - Find resources owned by a team/person
#LookupByOwner: {
	Resources: [string]: {owner?: string, ...}
	Target:    string

	result: [
		for name, res in Resources
		if res.owner != _|_
		if res.owner == Target {name},
	]
}

// #LookupByNode - Find resources on a specific node/host
#LookupByNode: {
	Resources: [string]: {...}
	Target:    string

	_by_node: [
		for name, res in Resources
		if res.node != _|_
		if res.node == Target {name},
	]
	_by_host: [
		for name, res in Resources
		if res.host != _|_
		if res.host == Target {name},
	]
	result: list.Concat([_by_node, [for n in _by_host if !list.Contains(_by_node, n) {n}]])
}

// #LookupByTag - Find resources with a specific tag
#LookupByTag: {
	Resources: [string]: {tags?: {[string]: true}, ...}
	Target:    string

	result: [
		for name, res in Resources
		if res.tags != _|_
		if res.tags[Target] != _|_ {name},
	]
}

// #NetworkMap - Group resources by VLAN
#NetworkMap: {
	Resources: [string]: {vlan?: int, ip?: string, ...}

	// Extract unique VLANs
	_vlans: {
		for _, res in Resources
		if res.vlan != _|_ {
			"\(res.vlan)": true
		}
	}

	map: {
		for vlan, _ in _vlans {
			"vlan_\(vlan)": [
				for name, res in Resources
				if res.vlan != _|_
				if "\(res.vlan)" == vlan {
					_name: name
					_ip:   res.ip | *""
				},
			]
		}
	}
}
