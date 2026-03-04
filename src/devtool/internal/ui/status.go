package ui

import (
	"fmt"
	"time"
)

const leftPaneWidth = 36

func (a App) renderStatusPane(height int) []string {
	lines := make([]string, 0, height)

	// STARMAN header
	lines = append(lines, padRight("  "+headerStyle.Render("STARMAN"), leftPaneWidth))
	lines = append(lines, padRight("", leftPaneWidth))

	// Status indicator
	var statusRendered string
	if a.restarting {
		statusRendered = warnStyle.Render("● Restarting…")
	} else if a.status.Running {
		statusRendered = successStyle.Render("● Running")
	} else {
		statusRendered = errorStyle.Render("● Stopped")
	}
	lines = append(lines, renderField("Status", statusRendered))

	// PID
	if a.status.PID > 0 {
		lines = append(lines, renderField("PID", fmt.Sprintf("%d", a.status.PID)))
	} else {
		lines = append(lines, renderField("PID", dimStyle.Render("—")))
	}

	// Static fields
	lines = append(lines, renderField("URL", fmt.Sprintf("http://localhost:%d", a.status.Port)))

	// Uptime
	if a.status.Running && !a.status.StartedAt.IsZero() {
		lines = append(lines, renderField("Uptime", formatDuration(time.Since(a.status.StartedAt))))
	} else {
		lines = append(lines, renderField("Uptime", dimStyle.Render("—")))
	}

	// Blank separator
	lines = append(lines, padRight("", leftPaneWidth))

	// LAST RUN section
	lines = append(lines, padRight("  "+headerStyle.Render("LAST RUN"), leftPaneWidth))
	if a.lastRun != nil {
		var result string
		if a.lastRun.passed {
			result = successStyle.Render("PASS")
		} else {
			result = errorStyle.Render("FAIL")
		}
		lines = append(lines, padRight("    "+a.lastRun.name+": "+result, leftPaneWidth))
	} else {
		lines = append(lines, padRight("    "+dimStyle.Render("(none)"), leftPaneWidth))
	}

	// Message
	if a.message != "" {
		lines = append(lines, padRight("", leftPaneWidth))
		lines = append(lines, padRight("  "+warnStyle.Render(a.message), leftPaneWidth))
	}

	// Pad to fill height
	for len(lines) < height {
		lines = append(lines, padRight("", leftPaneWidth))
	}

	return lines[:height]
}

func renderField(label, value string) string {
	prefix := fmt.Sprintf("    %-9s", label+":")
	return padRight(prefix+value, leftPaneWidth)
}

func formatDuration(d time.Duration) string {
	d = d.Round(time.Minute)
	h := int(d.Hours())
	m := int(d.Minutes()) % 60
	if h > 0 {
		return fmt.Sprintf("%dh %dm", h, m)
	}
	return fmt.Sprintf("%dm", m)
}

