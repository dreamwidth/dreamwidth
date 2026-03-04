package ui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

func (a App) renderLogPanes(height, width int) []string {
	lines := make([]string, 0, height)

	accessFocused := a.focus == focusAccessLog
	errorFocused := a.focus == focusErrorLog

	// Access log: header (1) + separator (1)
	// Error log: divider (1) + header (1) + separator (1)
	accessHeaderLines := 2
	errorHeaderLines := 3
	totalOverhead := accessHeaderLines + errorHeaderLines

	contentArea := height - totalOverhead
	if contentArea < 2 {
		contentArea = 2
	}
	accessContentHeight := contentArea / 2
	errorContentHeight := contentArea - accessContentHeight

	// --- Access log ---
	lines = append(lines, renderLogHeader("ACCESS LOG", accessFocused, a.accessFollow, width))
	lines = append(lines, renderLogDivider(width))

	accessLines := renderLogContent(
		a.accessTailer.Lines(), a.accessScroll, accessContentHeight, width, a.accessFollow,
	)
	lines = append(lines, accessLines...)

	// --- Divider between panes ---
	lines = append(lines, renderLogDivider(width))

	// --- Error log ---
	lines = append(lines, renderLogHeader("ERROR LOG", errorFocused, a.errorFollow, width))
	lines = append(lines, renderLogDivider(width))

	errorLines := renderLogContent(
		a.errorTailer.Lines(), a.errorScroll, errorContentHeight, width, a.errorFollow,
	)
	lines = append(lines, errorLines...)

	// Pad to exact height
	for len(lines) < height {
		lines = append(lines, padRight("", width))
	}
	return lines[:height]
}

func renderLogHeader(name string, focused, following bool, width int) string {
	prefix := "  "
	if focused {
		prefix = " " + focusStyle.Render(">")
	}

	header := prefix + " " + headerStyle.Render(name)

	followIndicator := ""
	if following {
		followIndicator = dimStyle.Render("[FOLLOW]")
	}

	headerW := lipgloss.Width(header)
	followW := lipgloss.Width(followIndicator)
	gap := width - headerW - followW
	if gap < 1 {
		gap = 1
	}

	return header + strings.Repeat(" ", gap) + followIndicator
}

func renderLogDivider(width int) string {
	if width <= 1 {
		return ""
	}
	return separatorStyle.Render(" " + strings.Repeat("─", width-1))
}

func (a App) renderCommandPane(height, width int) []string {
	lines := make([]string, 0, height)

	// Header
	if a.cmd.running {
		nameStyled := warnStyle.Render("RUNNING: " + a.cmd.name)
		followText := ""
		if a.cmd.follow {
			followText = dimStyle.Render("[FOLLOW]")
		}
		nameW := lipgloss.Width(nameStyled)
		followW := lipgloss.Width(followText)
		gap := width - nameW - followW - 2
		if gap < 1 {
			gap = 1
		}
		lines = append(lines, "  "+nameStyled+strings.Repeat(" ", gap)+followText)
	} else {
		var resultStyled string
		if a.cmd.err == nil {
			resultStyled = successStyle.Render("PASS")
		} else {
			resultStyled = errorStyle.Render("FAIL")
		}
		header := "  " + headerStyle.Render("DONE: "+a.cmd.name) + " " + resultStyled
		lines = append(lines, padRight(header, width))
	}

	// Separator
	lines = append(lines, renderLogDivider(width))

	// Content (reuse log content renderer)
	contentHeight := height - 2
	content := renderLogContent(a.cmd.lines, a.cmd.scroll, contentHeight, width, a.cmd.follow)
	lines = append(lines, content...)

	for len(lines) < height {
		lines = append(lines, padRight("", width))
	}
	return lines[:height]
}

func renderLogContent(allLines []string, scrollOffset, height, width int, follow bool) []string {
	if height <= 0 {
		return nil
	}

	lines := make([]string, 0, height)

	total := len(allLines)
	if total == 0 {
		lines = append(lines, padRight("  "+dimStyle.Render("(waiting for data…)"), width))
		for len(lines) < height {
			lines = append(lines, padRight("", width))
		}
		return lines
	}

	// Determine first visible line
	var start int
	if follow {
		start = max(0, total-height)
	} else {
		maxStart := max(0, total-height)
		start = clamp(scrollOffset, 0, maxStart)
	}

	end := min(start+height, total)

	for i := start; i < end; i++ {
		line := allLines[i]
		// Truncate to fit pane (2 chars left padding)
		maxLen := width - 2
		if maxLen > 0 && len(line) > maxLen {
			line = line[:maxLen]
		}
		lines = append(lines, padRight("  "+line, width))
	}

	// Pad remaining
	for len(lines) < height {
		lines = append(lines, padRight("", width))
	}

	return lines[:height]
}
