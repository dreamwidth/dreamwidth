package ui

import (
	"fmt"
	"strings"
)

// helpBinding represents a single keybinding for the help overlay.
type helpBinding struct {
	key  string
	desc string
}

// renderHelpOverlay renders the help overlay centered on the screen.
func renderHelpOverlay(width, height int) string {
	sections := []struct {
		title    string
		bindings []helpBinding
	}{
		{
			title: "Dashboard",
			bindings: []helpBinding{
				{"j/k", "move cursor up/down"},
				{"PgUp/Dn", "page up/down"},
				{"enter", "service detail"},
				{"d", "deploy service"},
					{"D", "deploy all workers"},
				{"ctrl+d", "deploy worker category"},
				{"t", "traffic weights (web only)"},
				{"l", "view logs"},
				{"s", "shell into service"},
				{"/", "filter services"},
				{"r", "refresh"},
				{"?", "toggle help"},
				{"q", "quit"},
			},
		},
		{
			title: "Service Detail",
			bindings: []helpBinding{
				{"j/k", "select task"},
				{"PgUp/Dn", "page up/down"},
				{"s", "shell into selected task"},
				{"d", "deploy service"},
				{"t", "traffic weights (web only)"},
				{"l", "view logs"},
				{"r", "refresh"},
				{"esc", "back to dashboard"},
			},
		},
		{
			title: "Logs",
			bindings: []helpBinding{
				{"j/k", "scroll up/down"},
				{"PgUp/Dn", "page up/down"},
				{"g/G", "jump to top/bottom"},
				{"f", "toggle follow mode"},
				{"/", "search"},
				{"n/N", "next/previous match"},
				{"esc", "back"},
			},
		},
		{
			title: "Traffic",
			bindings: []helpBinding{
				{"j/k", "select target group"},
				{"\u2190/\u2192", "adjust weight \u00b110"},
				{"1-4", "presets"},
				{"enter", "apply"},
				{"esc", "cancel"},
			},
		},
		{
			title: "Deploy",
			bindings: []helpBinding{
				{"j/k", "select image"},
				{"enter", "confirm selection"},
				{"Y", "confirm deploy (Shift+Y)"},
				{"esc", "cancel / back"},
			},
		},
	}

	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(labelStyle.Render("  Keybindings"))
	b.WriteString("\n\n")

	for _, section := range sections {
		b.WriteString(groupStyle.Render("  " + section.title))
		b.WriteString("\n")
		for _, bind := range section.bindings {
			key := padRight(bind.key, 10)
			b.WriteString(fmt.Sprintf("    %s %s\n",
				footerKeyStyle.Render(key),
				dimStyle.Render(bind.desc),
			))
		}
		b.WriteString("\n")
	}

	b.WriteString(dimStyle.Render("  Press ? or esc to close"))
	b.WriteString("\n")

	return b.String()
}
