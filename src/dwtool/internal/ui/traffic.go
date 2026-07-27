package ui

import (
	"fmt"
	"strings"

	"dreamwidth.org/dwtool/internal/model"
)

// trafficStep tracks which step of the traffic flow we're on.
type trafficStep int

const (
	trafficEditing trafficStep = iota
	trafficConfirm
	trafficSaving
)

// trafficState holds all state for the traffic weight view.
type trafficState struct {
	service         model.Service
	rule            model.TrafficRule
	originalWeights []int // snapshot for diff display
	tgCursor        int   // selected target group
	step            trafficStep
	prevView        view  // where to return on cancel
	loading         bool
	err             error
}

// renderTrafficView renders the traffic weight editing screen.
func renderTrafficView(ts trafficState, width, height int) string {
	switch ts.step {
	case trafficConfirm:
		return renderTrafficConfirm(ts, width)
	case trafficSaving:
		return renderTrafficSaving(ts)
	default:
		return renderTrafficEditing(ts, width)
	}
}

// renderTrafficEditing renders the weight editing view.
func renderTrafficEditing(ts trafficState, width int) string {
	var b strings.Builder

	// Title
	serviceKey := ts.rule.ServiceKey
	b.WriteString(labelStyle.Render(fmt.Sprintf(" Traffic \u2014 %s (%s)", serviceKey, ts.rule.Label)))
	b.WriteString("\n\n")

	if ts.loading {
		b.WriteString("   Loading traffic rule...\n")
		return b.String()
	}

	if ts.err != nil {
		b.WriteString(fmt.Sprintf("   %s\n", errorStyle.Render(fmt.Sprintf("Error: %v", ts.err))))
		b.WriteString("\n   Press Esc to go back.\n")
		return b.String()
	}

	if len(ts.rule.Targets) == 0 {
		b.WriteString("   No target groups found.\n")
		b.WriteString("\n   Press Esc to go back.\n")
		return b.String()
	}

	// Column header
	header := fmt.Sprintf("     %s %s %s",
		padRight("TARGET GROUP", 28),
		padRight("WEIGHT", 10),
		"TRAFFIC",
	)
	b.WriteString(headerStyle.Render(header))
	b.WriteString("\n")

	// Calculate total weight for percentage/bar
	totalWeight := 0
	for _, t := range ts.rule.Targets {
		totalWeight += t.Weight
	}

	// Target group rows
	for i, t := range ts.rule.Targets {
		nameCell := padRight(t.Name, 28)
		weightCell := padRight(fmt.Sprintf("%d", t.Weight), 10)
		bar := renderBar(t.Weight, totalWeight)
		pct := 0
		if totalWeight > 0 {
			pct = t.Weight * 100 / totalWeight
		}
		trafficCell := fmt.Sprintf("%s  %3d%%", bar, pct)

		if i == ts.tgCursor {
			line := fmt.Sprintf("   > %s %s %s", nameCell, weightCell, trafficCell)
			if width > 0 && len(line) < width {
				line += strings.Repeat(" ", width-len(line))
			}
			b.WriteString(selectedStyle.Render(line))
		} else {
			b.WriteString(fmt.Sprintf("     %s %s %s",
				dimStyle.Render(nameCell),
				weightCell,
				dimStyle.Render(trafficCell),
			))
		}
		b.WriteString("\n")
	}

	b.WriteString("\n")

	// Presets
	b.WriteString(labelStyle.Render("   Presets"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("     %s  %-26s %s  %s\n",
		footerKeyStyle.Render("1"),
		"All primary (100/0)",
		footerKeyStyle.Render("2"),
		"All secondary (0/100)",
	))
	b.WriteString(fmt.Sprintf("     %s  %-26s %s  %s\n",
		footerKeyStyle.Render("3"),
		"Even split (50/50)",
		footerKeyStyle.Render("4"),
		"Maintenance",
	))

	b.WriteString("\n")
	b.WriteString(dimStyle.Render("   j/k:select  \u2190/\u2192:adjust \u00b110  1-4:preset  enter:apply  esc:cancel"))
	b.WriteString("\n")

	return b.String()
}

// renderTrafficConfirm renders the confirmation diff view.
func renderTrafficConfirm(ts trafficState, width int) string {
	var b strings.Builder

	serviceKey := ts.rule.ServiceKey
	b.WriteString(confirmStyle.Render(fmt.Sprintf(" Apply Traffic Changes \u2014 %s (%s)", serviceKey, ts.rule.Label)))
	b.WriteString("\n\n")

	// Diff table
	header := fmt.Sprintf("     %s %s %s",
		padRight("TARGET GROUP", 28),
		padRight("BEFORE", 10),
		"AFTER",
	)
	b.WriteString(headerStyle.Render(header))
	b.WriteString("\n")

	for i, t := range ts.rule.Targets {
		nameCell := padRight(t.Name, 28)
		before := ts.originalWeights[i]
		after := t.Weight

		beforeStr := padRight(fmt.Sprintf("%d", before), 10)
		afterStr := fmt.Sprintf("%d", after)

		if before != after {
			b.WriteString(fmt.Sprintf("     %s %s \u2192  %s\n",
				nameCell,
				beforeStr,
				confirmStyle.Render(afterStr),
			))
		} else {
			b.WriteString(fmt.Sprintf("     %s %s \u2192  %s\n",
				dimStyle.Render(nameCell),
				dimStyle.Render(beforeStr),
				dimStyle.Render(afterStr),
			))
		}
	}

	b.WriteString("\n")
	b.WriteString(confirmStyle.Render("   Press Y (Shift+Y) to apply, any other key to cancel."))
	b.WriteString("\n")

	return b.String()
}

// renderTrafficSaving renders the saving state.
func renderTrafficSaving(ts trafficState) string {
	var b strings.Builder

	b.WriteString(labelStyle.Render(fmt.Sprintf(" Traffic \u2014 %s", ts.rule.ServiceKey)))
	b.WriteString("\n\n")
	b.WriteString("   Applying traffic weights...\n")

	return b.String()
}

// renderBar renders a visual bar of filled blocks proportional to weight/total.
func renderBar(weight, total int) string {
	const barWidth = 20
	if total == 0 {
		return strings.Repeat(" ", barWidth)
	}
	filled := weight * barWidth / total
	if weight > 0 && filled == 0 {
		filled = 1 // show at least one block for non-zero weight
	}
	return strings.Repeat("\u2588", filled) + strings.Repeat(" ", barWidth-filled)
}

// applyPreset sets target group weights to a predefined configuration.
// Targets are identified by naming convention:
//   - primary: serviceKey + "-tg"
//   - secondary: serviceKey + "-2-tg"
//   - maintenance: "dw-maint"
func applyPreset(rule *model.TrafficRule, preset int) {
	for i, t := range rule.Targets {
		switch preset {
		case 1: // All primary
			if strings.HasSuffix(t.Name, "-2-tg") || t.Name == "dw-maint" {
				rule.Targets[i].Weight = 0
			} else {
				rule.Targets[i].Weight = 100
			}
		case 2: // All secondary
			if strings.HasSuffix(t.Name, "-2-tg") {
				rule.Targets[i].Weight = 100
			} else {
				rule.Targets[i].Weight = 0
			}
		case 3: // Even split
			if t.Name == "dw-maint" {
				rule.Targets[i].Weight = 0
			} else {
				rule.Targets[i].Weight = 50
			}
		case 4: // Maintenance
			if t.Name == "dw-maint" {
				rule.Targets[i].Weight = 100
			} else {
				rule.Targets[i].Weight = 0
			}
		}
	}
}

// weightsChanged returns true if any weight differs from the original.
func weightsChanged(rule model.TrafficRule, original []int) bool {
	for i, t := range rule.Targets {
		if i < len(original) && t.Weight != original[i] {
			return true
		}
	}
	return false
}
