package ui

import "github.com/charmbracelet/bubbles/key"

type keyMap struct {
	Up        key.Binding
	Down      key.Binding
	Enter     key.Binding
	Deploy    key.Binding
	DeployAll key.Binding
	Logs      key.Binding
	Shell     key.Binding
	Filter    key.Binding
	Traffic   key.Binding
	Help      key.Binding
	Refresh   key.Binding
	Quit      key.Binding
	Escape    key.Binding
}

var keys = keyMap{
	Up: key.NewBinding(
		key.WithKeys("up", "k"),
		key.WithHelp("k/\u2191", "up"),
	),
	Down: key.NewBinding(
		key.WithKeys("down", "j"),
		key.WithHelp("j/\u2193", "down"),
	),
	Enter: key.NewBinding(
		key.WithKeys("enter"),
		key.WithHelp("enter", "detail"),
	),
	Deploy: key.NewBinding(
		key.WithKeys("d"),
		key.WithHelp("d", "deploy"),
	),
	DeployAll: key.NewBinding(
		key.WithKeys("D"),
		key.WithHelp("D", "deploy all workers"),
	),
	Logs: key.NewBinding(
		key.WithKeys("l"),
		key.WithHelp("l", "logs"),
	),
	Shell: key.NewBinding(
		key.WithKeys("s"),
		key.WithHelp("s", "shell"),
	),
	Filter: key.NewBinding(
		key.WithKeys("/"),
		key.WithHelp("/", "filter"),
	),
	Traffic: key.NewBinding(
		key.WithKeys("t"),
		key.WithHelp("t", "traffic"),
	),
	Help: key.NewBinding(
		key.WithKeys("?"),
		key.WithHelp("?", "help"),
	),
	Refresh: key.NewBinding(
		key.WithKeys("r"),
		key.WithHelp("r", "refresh"),
	),
	Quit: key.NewBinding(
		key.WithKeys("q", "ctrl+c"),
		key.WithHelp("q", "quit"),
	),
	Escape: key.NewBinding(
		key.WithKeys("esc"),
		key.WithHelp("esc", "back"),
	),
}
