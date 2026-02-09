package ui

import (
	"fmt"
	"strings"

	"dreamwidth.org/dwtool/internal/model"
)

// logsState holds state for the log viewer.
type logsState struct {
	service  model.Service
	logGroup string
	prevView view // view to return to on esc
	events   []model.LogEvent
	scrollOffset int
	follow       bool // auto-scroll to bottom on new events
	loading      bool
	err          error

	// For tailing: timestamp of the last fetched event (millis)
	lastEventMs int64

	// Search
	search       string
	searchActive bool
	matchLines   []int // indices into events that match the search
	matchCursor  int   // current match index within matchLines
}

// visibleLogLines returns the number of log lines visible in the viewport.
// Layout: title(1) + info(1) + blank(1) + [viewport] + footer(1) = 4 fixed.
func visibleLogLines(height int) int {
	h := height - 4
	if h < 1 {
		return 1
	}
	return h
}

// renderLogsView renders the log viewer.
func renderLogsView(ls logsState, width, height int) string {
	var b strings.Builder

	// Service + log group info
	b.WriteString(labelStyle.Render(fmt.Sprintf(" Logs: %s", ls.service.Name)))
	b.WriteString("\n")
	b.WriteString(dimStyle.Render(fmt.Sprintf("   %s", ls.logGroup)))
	if ls.follow {
		b.WriteString("  ")
		b.WriteString(successStyle.Render("[FOLLOW]"))
	}
	b.WriteString("\n")

	if ls.loading && len(ls.events) == 0 {
		b.WriteString("\n   Loading logs...\n")
		return b.String()
	}

	if ls.err != nil && len(ls.events) == 0 {
		b.WriteString(fmt.Sprintf("\n   %s\n", errorStyle.Render(fmt.Sprintf("Error: %v", ls.err))))
		return b.String()
	}

	if len(ls.events) == 0 {
		b.WriteString("\n   No log events found.\n")
		return b.String()
	}

	vpHeight := visibleLogLines(height)

	// Render visible slice of events
	end := ls.scrollOffset + vpHeight
	if end > len(ls.events) {
		end = len(ls.events)
	}
	start := ls.scrollOffset
	if start < 0 {
		start = 0
	}

	for i := start; i < end; i++ {
		ev := ls.events[i]
		ts := ev.Timestamp.Format("15:04:05")

		msg := ev.Message
		// Truncate long lines to terminal width
		maxMsg := width - 12 // timestamp(8) + spaces(4)
		if maxMsg < 20 {
			maxMsg = 20
		}
		if len(msg) > maxMsg {
			msg = msg[:maxMsg-3] + "..."
		}

		// Highlight search matches
		isMatch := false
		if ls.search != "" && ls.searchActive {
			if strings.Contains(strings.ToLower(ev.Message), strings.ToLower(ls.search)) {
				isMatch = true
			}
		}

		line := fmt.Sprintf(" %s  %s", dimStyle.Render(ts), msg)
		if isMatch {
			line = fmt.Sprintf(" %s  %s", dimStyle.Render(ts), confirmStyle.Render(msg))
		}

		b.WriteString(line)
		b.WriteString("\n")
	}

	// Scroll indicator
	if len(ls.events) > vpHeight {
		pos := ""
		if ls.scrollOffset == 0 {
			pos = "TOP"
		} else if ls.scrollOffset >= len(ls.events)-vpHeight {
			pos = "END"
		} else {
			pct := ls.scrollOffset * 100 / (len(ls.events) - vpHeight)
			pos = fmt.Sprintf("%d%%", pct)
		}
		b.WriteString(dimStyle.Render(fmt.Sprintf("   %d events  %s", len(ls.events), pos)))
		b.WriteString("\n")
	}

	return b.String()
}

// renderLogsFooter renders the footer for the logs view.
func renderLogsFooter(ls logsState, width int) string {
	var parts []string

	if ls.searchActive {
		searchInfo := fmt.Sprintf(" /%s", ls.search)
		if len(ls.matchLines) > 0 {
			searchInfo += fmt.Sprintf(" (%d/%d)", ls.matchCursor+1, len(ls.matchLines))
		} else if ls.search != "" {
			searchInfo += " (no matches)"
		}
		parts = append(parts, searchInfo)
		parts = append(parts, "  "+dimStyle.Render("enter:done  esc:cancel"))
	} else {
		parts = append(parts, fmt.Sprintf(" %s:%s", footerKeyStyle.Render("f"), "follow"))
		parts = append(parts, fmt.Sprintf("  %s:%s", footerKeyStyle.Render("/"), "search"))
		parts = append(parts, fmt.Sprintf("  %s:%s", footerKeyStyle.Render("n"), "next-match"))
		parts = append(parts, fmt.Sprintf("  %s:%s", footerKeyStyle.Render("G"), "end"))
		parts = append(parts, fmt.Sprintf("  %s:%s", footerKeyStyle.Render("g"), "top"))
		parts = append(parts, fmt.Sprintf("  %s:%s", footerKeyStyle.Render("esc"), "back"))
	}

	left := strings.Join(parts, "")
	return footerStyle.Render(padRight(left, width))
}

// updateSearchMatches recalculates which event indices match the current search.
func (ls *logsState) updateSearchMatches() {
	ls.matchLines = nil
	ls.matchCursor = 0
	if ls.search == "" {
		return
	}
	needle := strings.ToLower(ls.search)
	for i, ev := range ls.events {
		if strings.Contains(strings.ToLower(ev.Message), needle) {
			ls.matchLines = append(ls.matchLines, i)
		}
	}
}

// scrollToMatch scrolls to the current match.
func (ls *logsState) scrollToMatch(vpHeight int) {
	if len(ls.matchLines) == 0 {
		return
	}
	target := ls.matchLines[ls.matchCursor]
	// Center the match in the viewport
	ls.scrollOffset = target - vpHeight/2
	if ls.scrollOffset < 0 {
		ls.scrollOffset = 0
	}
	maxScroll := len(ls.events) - vpHeight
	if maxScroll < 0 {
		maxScroll = 0
	}
	if ls.scrollOffset > maxScroll {
		ls.scrollOffset = maxScroll
	}
}
