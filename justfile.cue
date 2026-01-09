// Justfile generation patterns
//
// Generates justfile recipes from infraGraph actions and project actions
//
// Usage:
//   import "quicue.ca/infra"
//
//   _justfile: infra.#JustfileProjection & {
//       InfraGraph: myInfraGraph
//       ProjectActions: myProjectActions
//       ProjectName: "my-project"
//       ProjectDescription: "My infrastructure"
//   }
//   content: _justfile.Output

package infra

import "strings"

// #ProjectAction - Schema for project-level actions
#ProjectAction: {
	name:        string
	description: string
	command:     string
	category:    string
	args?: [...string]
	...
}

// #ProjectActionTemplates - Common project action templates
#ProjectActionTemplates: {
	validate: #ProjectAction & {
		name:        *"Validate" | string
		description: *"Validate CUE configuration" | string
		command:     *"cue vet -c=false ./cluster" | string
		category:    *"workflow" | string
	}

	fmt: #ProjectAction & {
		name:        *"Format" | string
		description: *"Format CUE files" | string
		command:     *"cue fmt ./cluster/*.cue" | string
		category:    *"workflow" | string
	}

	query: #ProjectAction & {
		name:        *"Query" | string
		description: *"Query CUE expression" | string
		command:     *"cue eval ./cluster -e '{{expr}}'" | string
		category:    *"query" | string
		args: ["expr"]
	}

	graph_resources: #ProjectAction & {
		name:        *"Graph Resources" | string
		description: *"List all resources in infraGraph" | string
		command:     *"cue eval ./cluster -e '[for k, _ in infraGraph {k}]'" | string
		category:    *"graph" | string
	}

	graph_export: #ProjectAction & {
		name:        *"Graph Export" | string
		description: *"Export infraGraph to JSON" | string
		command:     *"cue export ./cluster -e 'infraGraph' > infra-graph.json" | string
		category:    *"graph" | string
	}

	generate_justfile: #ProjectAction & {
		name:        *"Generate Justfile" | string
		description: *"Regenerate justfile from CUE" | string
		command:     *"cue cmd justfile ./cluster" | string
		category:    *"workflow" | string
	}

	// Allow extension
	...
}

// #JustfileProjection - Generate justfile content
#JustfileProjection: {
	InfraGraph: [string]: {...}
	ProjectActions: [string]: #ProjectAction
	ProjectName:        string
	ProjectDescription: string

	// Helper: indent multi-line commands (add 4 spaces to each line)
	_indentCommand: {
		input: string
		// Split, add indent to each line, rejoin
		_lines: strings.Split(input, "\n")
		output: strings.Join([for line in _lines {"    \(line)"}], "\n")
	}

	// Generate project action recipes - without args
	_projectRecipesNoArgs: {
		for name, action in ProjectActions if action.args == _|_ {
			let _cmd = (_indentCommand & {input: action.command}).output
			"\(name)": """
				# \(action.description)
				\(name):
				\(_cmd)
				"""
		}
	}

	// Generate project action recipes - with args
	_projectRecipesWithArgs: {
		for name, action in ProjectActions if action.args != _|_ {
			let _cmd = (_indentCommand & {input: action.command}).output
			let _argStr = strings.Join(action.args, " ")
			"\(name)": """
				# \(action.description)
				\(name) \(_argStr):
				\(_cmd)
				"""
		}
	}

	// Merge both recipe sets
	_projectRecipes: _projectRecipesNoArgs & _projectRecipesWithArgs

	// Generate resource action recipes
	_resourceRecipes: {
		for resName, res in InfraGraph if res.actions != _|_ {
			for actName, act in res.actions if act.command != _|_ {
				let _recipeName = strings.Replace(strings.Replace("\(resName)_\(actName)", "-", "_", -1), ".", "_", -1)
				let _cmd = (_indentCommand & {input: act.command}).output
				"\(_recipeName)": """
					# \(act.name | *actName) for \(resName)
					\(_recipeName):
					\(_cmd)
					"""
			}
		}
	}

	// Combine all recipes into final output
	_header: """
		# \(ProjectDescription)
		# Generated from CUE - do not edit directly

		set shell := ["bash", "-uc"]

		# Default recipe - show help
		default:
		    @just --list

		"""

	_projectSection: strings.Join([for _, r in _projectRecipes {r}], "\n\n")
	_resourceSection: strings.Join([for _, r in _resourceRecipes {r}], "\n\n")

	Output: _header + "\n# Project Actions\n\n" + _projectSection + "\n\n# Resource Actions\n\n" + _resourceSection
}
