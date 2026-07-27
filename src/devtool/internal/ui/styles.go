package ui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// Color palette — same terminal 256-color indices as dwtool.
var (
	colorRed    = lipgloss.Color("1")
	colorGreen  = lipgloss.Color("2")
	colorYellow = lipgloss.Color("3")
	colorCyan   = lipgloss.Color("6")
	colorWhite  = lipgloss.Color("7")
	colorSubtle = lipgloss.Color("241")
	colorDim    = lipgloss.Color("245")
)

// Styles
var (
	titleStyle     = lipgloss.NewStyle().Bold(true).Foreground(colorWhite)
	separatorStyle = lipgloss.NewStyle().Foreground(colorSubtle)
	headerStyle    = lipgloss.NewStyle().Bold(true).Foreground(colorCyan)
	footerStyle    = lipgloss.NewStyle().Foreground(colorSubtle)
	footerKeyStyle = lipgloss.NewStyle().Foreground(colorCyan)
	dimStyle       = lipgloss.NewStyle().Foreground(colorDim)
	errorStyle     = lipgloss.NewStyle().Foreground(colorRed)
	successStyle   = lipgloss.NewStyle().Foreground(colorGreen)
	warnStyle      = lipgloss.NewStyle().Foreground(colorYellow)
	focusStyle     = lipgloss.NewStyle().Bold(true).Foreground(colorWhite)
)

// padRight pads s with spaces to reach the given visible width.
// Uses lipgloss.Width to correctly measure strings containing ANSI codes.
func padRight(s string, width int) string {
	w := lipgloss.Width(s)
	if w >= width {
		return s
	}
	return s + strings.Repeat(" ", width-w)
}

func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
