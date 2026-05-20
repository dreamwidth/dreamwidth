package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"

	"dreamwidth.org/devtool/internal/ui"
)

func main() {
	ljHome := os.Getenv("LJHOME")
	if ljHome == "" {
		fmt.Fprintln(os.Stderr, "error: $LJHOME is not set")
		os.Exit(1)
	}

	app := ui.NewApp(ljHome)
	p := tea.NewProgram(app, tea.WithAltScreen())

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
