package ui

import (
	"github.com/charmbracelet/lipgloss"

	"dreamwidth.org/dwtool/internal/model"
)

var (
	// Colors
	colorRed     = lipgloss.Color("1")
	colorGreen   = lipgloss.Color("2")
	colorYellow  = lipgloss.Color("3")
	colorBlue    = lipgloss.Color("4")
	colorMagenta = lipgloss.Color("5")
	colorCyan    = lipgloss.Color("6")
	colorWhite   = lipgloss.Color("7")
	colorGray    = lipgloss.Color("8")
	colorSubtle  = lipgloss.Color("241")
	colorDim     = lipgloss.Color("245")

	// Title bar
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(colorWhite)

	titleInfoStyle = lipgloss.NewStyle().
			Foreground(colorSubtle)

	// Column header
	headerStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(colorCyan)

	// Separator line (below header)
	separatorStyle = lipgloss.NewStyle().
			Foreground(colorSubtle)

	// Group header
	groupStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(colorMagenta)

	// Selected row
	selectedStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("229")).
			Background(lipgloss.Color("57"))

	// Status indicators
	statusActiveStyle = lipgloss.NewStyle().
				Foreground(colorGreen)

	statusDrainingStyle = lipgloss.NewStyle().
				Foreground(colorYellow)

	statusInactiveStyle = lipgloss.NewStyle().
				Foreground(colorRed)

	// Task counts
	taskCountOKStyle = lipgloss.NewStyle().
				Foreground(colorGreen)

	taskCountWarnStyle = lipgloss.NewStyle().
				Foreground(colorYellow)

	// Footer
	footerStyle = lipgloss.NewStyle().
			Foreground(colorSubtle)

	footerKeyStyle = lipgloss.NewStyle().
			Foreground(colorCyan)

	// Error message
	errorStyle = lipgloss.NewStyle().
			Foreground(colorRed)

	// Dim text
	dimStyle = lipgloss.NewStyle().
			Foreground(colorDim)

	// Image digest
	digestStyle = lipgloss.NewStyle().
			Foreground(colorSubtle)

	// Deploy view styles
	confirmStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(colorYellow)

	successStyle = lipgloss.NewStyle().
			Foreground(colorGreen)

	failureStyle = lipgloss.NewStyle().
			Foreground(colorRed)

	labelStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(colorCyan)
)

// colorizeStatus applies color to a pre-padded status string.
func colorizeStatus(padded, status string) string {
	switch status {
	case "ACTIVE":
		return statusActiveStyle.Render(padded)
	case "DRAINING":
		return statusDrainingStyle.Render(padded)
	case "INACTIVE":
		return statusInactiveStyle.Render(padded)
	default:
		return padded
	}
}

// colorizeTasks applies color to a pre-padded task count string.
func colorizeTasks(padded string, svc model.Service) string {
	if svc.Deploying || svc.PendingCount > 0 {
		return taskCountWarnStyle.Render(padded)
	}
	if svc.RunningCount == svc.DesiredCount && svc.DesiredCount > 0 {
		return taskCountOKStyle.Render(padded)
	}
	return taskCountWarnStyle.Render(padded)
}
