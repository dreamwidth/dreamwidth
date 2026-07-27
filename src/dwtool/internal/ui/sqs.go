package ui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"

	"dreamwidth.org/dwtool/internal/model"
)

// SQS column widths.
const (
	colSQSQueue      = 36
	colSQSPending    = 10
	colSQSFlight     = 10
	colSQSDelayed    = 10
	colSQSThroughput = 12
)

// sqsState holds all state for the SQS queues view.
type sqsState struct {
	queues       []model.SQSQueue
	cursor       int
	scrollOffset int
	loading      bool
	err          error
}

// sqsRow represents a single row in the SQS view (group header or queue).
type sqsRow struct {
	isGroup bool
	group   string
	queue   model.SQSQueue
}

// buildSQSRows creates the flat list of SQS rows grouped into task queues and DLQs.
func buildSQSRows(queues []model.SQSQueue) []sqsRow {
	var taskQueues, dlqQueues []model.SQSQueue
	for _, q := range queues {
		if q.IsDLQ {
			dlqQueues = append(dlqQueues, q)
		} else {
			taskQueues = append(taskQueues, q)
		}
	}

	// Sort each group alphabetically
	sortQueuesByName(taskQueues)
	sortQueuesByName(dlqQueues)

	var rows []sqsRow

	if len(taskQueues) > 0 {
		rows = append(rows, sqsRow{isGroup: true, group: "Task Queues"})
		for _, q := range taskQueues {
			rows = append(rows, sqsRow{queue: q})
		}
	}

	if len(dlqQueues) > 0 {
		rows = append(rows, sqsRow{isGroup: true, group: "Dead Letter Queues"})
		for _, q := range dlqQueues {
			rows = append(rows, sqsRow{queue: q})
		}
	}

	return rows
}

// renderSQSColumnHeader returns the column header line for the SQS view.
func renderSQSColumnHeader() string {
	header := fmt.Sprintf("  %s %s %s %s %s",
		padRight("QUEUE", colSQSQueue),
		padRight("PENDING", colSQSPending),
		padRight("FLIGHT", colSQSFlight),
		padRight("DELAYED", colSQSDelayed),
		padRight("THROUGHPUT", colSQSThroughput),
	)
	return headerStyle.Render(header)
}

// renderSQSView renders the SQS queue table.
func renderSQSView(ss sqsState, width, height int) string {
	rows := buildSQSRows(ss.queues)
	vpHeight := height - 4 // title + header + separator + footer
	if vpHeight < 1 {
		vpHeight = 1
	}

	// Pre-render all rows into visual lines
	var lines []string
	for i, row := range rows {
		if row.isGroup {
			if i > 0 {
				lines = append(lines, "")
			}
			lines = append(lines, groupStyle.Render(" "+row.group))
		} else {
			lines = append(lines, renderSQSLine(row.queue, i == ss.cursor, width))
		}
	}

	// Render visible slice
	var b strings.Builder
	end := ss.scrollOffset + vpHeight
	if end > len(lines) {
		end = len(lines)
	}
	start := ss.scrollOffset
	if start < 0 {
		start = 0
	}
	for i := start; i < end; i++ {
		b.WriteString(lines[i])
		b.WriteString("\n")
	}

	return b.String()
}

// renderSQSLine renders a single SQS queue row with aligned columns.
func renderSQSLine(q model.SQSQueue, isCursor bool, width int) string {
	pendingStr := fmt.Sprintf("%d", q.Pending)
	flightStr := fmt.Sprintf("%d", q.InFlight)
	delayedStr := fmt.Sprintf("%d", q.Delayed)
	throughput := q.Throughput
	if throughput == "" {
		throughput = "-"
	}

	// For DLQs, flight and delayed are not meaningful
	if q.IsDLQ {
		flightStr = "-"
		delayedStr = "-"
	}

	nameCell := padRight(q.Name, colSQSQueue)
	pendingCell := padRight(pendingStr, colSQSPending)
	flightCell := padRight(flightStr, colSQSFlight)
	delayedCell := padRight(delayedStr, colSQSDelayed)
	throughputCell := padRight(throughput, colSQSThroughput)

	if isCursor {
		line := fmt.Sprintf("  %s %s %s %s %s",
			nameCell, pendingCell, flightCell, delayedCell, throughputCell)
		if width > 0 && len(line) < width {
			line += strings.Repeat(" ", width-len(line))
		}
		return selectedStyle.Render(line)
	}

	// Normal row: colorize non-zero pending counts
	styledPending := pendingCell
	if q.Pending > 0 {
		styledPending = taskCountWarnStyle.Render(pendingCell)
	}

	styledFlight := dimStyle.Render(flightCell)
	if q.InFlight > 0 {
		styledFlight = taskCountOKStyle.Render(flightCell)
	}

	return fmt.Sprintf("  %s %s %s %s %s",
		nameCell,
		styledPending,
		styledFlight,
		dimStyle.Render(delayedCell),
		dimStyle.Render(throughputCell),
	)
}

// renderSQSFooter returns the footer line for the SQS view.
func renderSQSFooter(ss sqsState, width int, loading bool, spinnerView string) string {
	left := fmt.Sprintf(" %s:%s  %s:%s  %s:%s",
		footerKeyStyle.Render("j/k"), "move",
		footerKeyStyle.Render("r"), "refresh",
		footerKeyStyle.Render("\u2190"), "ECS",
	)

	taskCount := 0
	dlqCount := 0
	for _, q := range ss.queues {
		if q.IsDLQ {
			dlqCount++
		} else {
			taskCount++
		}
	}

	right := fmt.Sprintf("%d queues  %d DLQs ", taskCount, dlqCount)
	if loading {
		right = spinnerView + " " + right
	}

	padding := width - lipgloss.Width(left) - lipgloss.Width(right)
	if padding < 1 {
		padding = 1
	}

	return footerStyle.Render(left + strings.Repeat(" ", padding) + right)
}

// sortQueuesByName sorts SQS queues alphabetically by name.
func sortQueuesByName(queues []model.SQSQueue) {
	for i := 0; i < len(queues); i++ {
		for j := i + 1; j < len(queues); j++ {
			if queues[i].Name > queues[j].Name {
				queues[i], queues[j] = queues[j], queues[i]
			}
		}
	}
}
