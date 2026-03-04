package ui

import "github.com/charmbracelet/bubbles/key"

type keyMap struct {
	Up       key.Binding
	Down     key.Binding
	PageUp   key.Binding
	PageDown key.Binding
	Tab      key.Binding
	Restart  key.Binding
	Tidy     key.Binding
	Compile  key.Binding
	Build    key.Binding
	Follow   key.Binding
	Help     key.Binding
	Quit     key.Binding
	Escape   key.Binding
}

var keys = keyMap{
	Up:       key.NewBinding(key.WithKeys("up", "k"), key.WithHelp("k/↑", "scroll up")),
	Down:     key.NewBinding(key.WithKeys("down", "j"), key.WithHelp("j/↓", "scroll down")),
	PageUp:   key.NewBinding(key.WithKeys("pgup"), key.WithHelp("PgUp", "page up")),
	PageDown: key.NewBinding(key.WithKeys("pgdown"), key.WithHelp("PgDn", "page down")),
	Tab:      key.NewBinding(key.WithKeys("tab"), key.WithHelp("tab", "focus")),
	Restart:  key.NewBinding(key.WithKeys("r"), key.WithHelp("r", "restart")),
	Tidy:     key.NewBinding(key.WithKeys("t"), key.WithHelp("t", "tidy")),
	Compile:  key.NewBinding(key.WithKeys("c"), key.WithHelp("c", "compile")),
	Build:    key.NewBinding(key.WithKeys("b"), key.WithHelp("b", "build")),
	Follow:   key.NewBinding(key.WithKeys("f"), key.WithHelp("f", "follow")),
	Help:     key.NewBinding(key.WithKeys("?"), key.WithHelp("?", "help")),
	Quit:     key.NewBinding(key.WithKeys("q", "ctrl+c"), key.WithHelp("q", "quit")),
	Escape:   key.NewBinding(key.WithKeys("esc"), key.WithHelp("esc", "close")),
}
