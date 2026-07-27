package ui

import (
	"fmt"
	"strings"

	dwaws "dreamwidth.org/dwtool/internal/aws"
	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/model"
)

// Column widths (plain text characters).
const (
	colService  = 44
	colStatus   = 10
	colTasks    = 12
	colImage    = 14
	colDeployed = 10
)

// dashboardRow represents a single row in the dashboard (either a group header or a service).
type dashboardRow struct {
	isGroup bool
	group   string
	service model.Service
}

// visualLine is a pre-rendered line for display.
type visualLine struct {
	content  string // rendered text for this line
	rowIndex int    // original dashboardRow index, or -1 for separators/blanks
}

// buildRows creates the flat list of dashboard rows from grouped services.
func buildRows(services []model.Service, workers *config.WorkersConfig) []dashboardRow {
	var rows []dashboardRow

	// Group services
	webServices := make([]model.Service, 0)
	workerServices := make(map[string][]model.Service)
	proxyServices := make([]model.Service, 0)
	otherServices := make([]model.Service, 0)

	// Build a worker name -> category lookup
	workerCategories := make(map[string]string)
	if workers != nil {
		for name, def := range workers.Workers {
			workerCategories[name] = def.Category
		}
	}

	for _, svc := range services {
		switch svc.Group {
		case "web":
			webServices = append(webServices, svc)
		case "worker":
			cat := "uncategorized"
			if c, ok := workerCategories[svc.WorkflowSvc]; ok {
				cat = c
			}
			workerServices[cat] = append(workerServices[cat], svc)
		case "proxy":
			proxyServices = append(proxyServices, svc)
		default:
			otherServices = append(otherServices, svc)
		}
	}

	// Web services in deployment order
	if len(webServices) > 0 {
		rows = append(rows, dashboardRow{isGroup: true, group: "Web"})
		webOrder := map[string]int{
			"web-canary":          0,
			"web-shop":            1,
			"web-unauthenticated": 2,
			"web-stable":          3,
		}
		sortByOrder(webServices, webOrder)
		for _, svc := range webServices {
			rows = append(rows, dashboardRow{service: svc})
		}
	}

	// Workers by category
	for _, cat := range config.CategoryOrder {
		svcs, ok := workerServices[cat]
		if !ok || len(svcs) == 0 {
			continue
		}
		rows = append(rows, dashboardRow{isGroup: true, group: fmt.Sprintf("Workers - %s", cat)})
		sortByName(svcs)
		for _, svc := range svcs {
			rows = append(rows, dashboardRow{service: svc})
		}
		delete(workerServices, cat)
	}

	// Any remaining uncategorized workers
	for cat, svcs := range workerServices {
		if len(svcs) == 0 {
			continue
		}
		rows = append(rows, dashboardRow{isGroup: true, group: fmt.Sprintf("Workers - %s", cat)})
		sortByName(svcs)
		for _, svc := range svcs {
			rows = append(rows, dashboardRow{service: svc})
		}
	}

	// Proxy
	if len(proxyServices) > 0 {
		rows = append(rows, dashboardRow{isGroup: true, group: "Proxy"})
		for _, svc := range proxyServices {
			rows = append(rows, dashboardRow{service: svc})
		}
	}

	// Other
	if len(otherServices) > 0 {
		rows = append(rows, dashboardRow{isGroup: true, group: "Other"})
		sortByName(otherServices)
		for _, svc := range otherServices {
			rows = append(rows, dashboardRow{service: svc})
		}
	}

	return rows
}

// preRenderLines converts dashboard rows into a flat list of visual lines.
// Group headers get a blank separator line before them (except the first group).
// Each service row becomes one visual line. The cursor row gets selection styling.
func preRenderLines(rows []dashboardRow, cursor int, width int) []visualLine {
	var lines []visualLine

	for i, row := range rows {
		if row.isGroup {
			// Blank separator before non-first groups
			if i > 0 {
				lines = append(lines, visualLine{content: "", rowIndex: -1})
			}
			lines = append(lines, visualLine{
				content:  groupStyle.Render(" " + row.group),
				rowIndex: -1,
			})
		} else {
			lines = append(lines, visualLine{
				content:  renderServiceLine(row.service, i == cursor, width),
				rowIndex: i,
			})
		}
	}

	return lines
}

// rowVisualHeight returns the number of visual lines a row occupies.
// First group = 1, subsequent groups = 2 (blank + header), services = 1.
func rowVisualHeight(rows []dashboardRow, index int) int {
	if rows[index].isGroup && index > 0 {
		return 2
	}
	return 1
}

// renderColumnHeader returns the fixed column header line.
func renderColumnHeader(width int) string {
	header := fmt.Sprintf("  %s %s %s %s %s",
		padRight("SERVICE", colService),
		padRight("STATUS", colStatus),
		padRight("TASKS", colTasks),
		padRight("IMAGE", colImage),
		padRight("DEPLOYED", colDeployed),
	)
	return headerStyle.Render(header)
}

// renderSeparator returns a horizontal separator line.
func renderSeparator(width int) string {
	w := width
	if w <= 0 {
		w = 80
	}
	return separatorStyle.Render(strings.Repeat("─", w))
}

// renderServiceLine renders a single service row with aligned columns.
// Padding is applied to plain text first, then color is applied, so ANSI
// escape codes don't affect column alignment.
func renderServiceLine(svc model.Service, isCursor bool, width int) string {
	digest := svc.ImageDigest
	if digest == "" {
		digest = "-"
	}
	deployed := dwaws.RelativeTime(svc.DeployedAt)
	tasksStr := fmt.Sprintf("%d/%d", svc.RunningCount, svc.DesiredCount)
	if svc.PendingCount > 0 {
		tasksStr += fmt.Sprintf(" +%dp", svc.PendingCount)
	} else if svc.Deploying {
		tasksStr += " ..."
	}

	// Pad each column as plain text to fixed widths
	nameCell := padRight(svc.Name, colService)
	statusCell := padRight(svc.Status, colStatus)
	tasksCell := padRight(tasksStr, colTasks)
	digestCell := padRight(digest, colImage)
	deployedCell := padRight(deployed, colDeployed)

	if isCursor {
		// Selected row: uniform background, no per-cell colors
		line := fmt.Sprintf("  %s %s %s %s %s",
			nameCell, statusCell, tasksCell, digestCell, deployedCell)
		// Pad to full width so the selection background extends
		if width > 0 && len(line) < width {
			line += strings.Repeat(" ", width-len(line))
		}
		return selectedStyle.Render(line)
	}

	// Normal row: colorize each pre-padded cell
	line := fmt.Sprintf("  %s %s %s %s %s",
		nameCell,
		colorizeStatus(statusCell, svc.Status),
		colorizeTasks(tasksCell, svc),
		digestStyle.Render(digestCell),
		deployedCell,
	)
	return line
}

// renderVisibleLines renders the visible slice of pre-rendered lines.
func renderVisibleLines(lines []visualLine, scrollOffset, viewportHeight int) string {
	var b strings.Builder

	end := scrollOffset + viewportHeight
	if end > len(lines) {
		end = len(lines)
	}
	start := scrollOffset
	if start < 0 {
		start = 0
	}

	for i := start; i < end; i++ {
		b.WriteString(lines[i].content)
		b.WriteString("\n")
	}

	return b.String()
}

// padRight pads a string with spaces to the given width.
// Only counts rune length (safe for ASCII service names).
func padRight(s string, width int) string {
	n := len(s)
	if n >= width {
		return s[:width]
	}
	return s + strings.Repeat(" ", width-n)
}

// sortByOrder sorts services by a predefined order map.
func sortByOrder(services []model.Service, order map[string]int) {
	for i := 0; i < len(services); i++ {
		for j := i + 1; j < len(services); j++ {
			oi, oki := order[services[i].Name]
			oj, okj := order[services[j].Name]
			if !oki {
				oi = 999
			}
			if !okj {
				oj = 999
			}
			if oi > oj {
				services[i], services[j] = services[j], services[i]
			}
		}
	}
}

// categoryForCursor walks the rows to find the group header that contains the
// cursor row, then collects all services in that group. Returns the category
// name (e.g. "email") and the list of services, or empty if the cursor isn't
// on a worker row.
func categoryForCursor(rows []dashboardRow, cursor int) (string, []model.Service) {
	if cursor < 0 || cursor >= len(rows) || rows[cursor].isGroup {
		return "", nil
	}

	// Walk backward to find the group header
	groupIdx := -1
	for i := cursor - 1; i >= 0; i-- {
		if rows[i].isGroup {
			groupIdx = i
			break
		}
	}
	if groupIdx < 0 {
		return "", nil
	}

	groupName := rows[groupIdx].group
	// Must be a "Workers - <category>" group
	if !strings.HasPrefix(groupName, "Workers - ") {
		return "", nil
	}
	category := strings.TrimPrefix(groupName, "Workers - ")

	// Walk forward from the group header to collect all services until next header
	var services []model.Service
	for i := groupIdx + 1; i < len(rows); i++ {
		if rows[i].isGroup {
			break
		}
		services = append(services, rows[i].service)
	}

	return category, services
}

// sortByName sorts services alphabetically.
func sortByName(services []model.Service) {
	for i := 0; i < len(services); i++ {
		for j := i + 1; j < len(services); j++ {
			if services[i].Name > services[j].Name {
				services[i], services[j] = services[j], services[i]
			}
		}
	}
}
