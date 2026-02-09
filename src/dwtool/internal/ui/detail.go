package ui

import (
	"fmt"
	"strings"

	dwaws "dreamwidth.org/dwtool/internal/aws"
	"dreamwidth.org/dwtool/internal/model"
)

// detailState holds state for the service detail view.
type detailState struct {
	service    model.Service
	tasks      []model.Task
	taskCursor int
	loading    bool
	err        error
}

// selectedTask returns the currently selected task, or nil.
func (ds detailState) selectedTask() *model.Task {
	if ds.taskCursor >= 0 && ds.taskCursor < len(ds.tasks) {
		return &ds.tasks[ds.taskCursor]
	}
	return nil
}

// renderDetailView renders the service detail screen.
func renderDetailView(ds detailState, width, height int) string {
	var b strings.Builder

	// Title
	b.WriteString(labelStyle.Render(fmt.Sprintf(" %s", ds.service.Name)))
	b.WriteString("\n\n")

	// Service summary
	status := ds.service.Status
	if status == "" {
		status = "-"
	}
	tasksStr := fmt.Sprintf("%d/%d", ds.service.RunningCount, ds.service.DesiredCount)
	if ds.service.PendingCount > 0 {
		tasksStr += fmt.Sprintf(" +%dp", ds.service.PendingCount)
	}
	digest := ds.service.ImageDigest
	if digest == "" {
		digest = "-"
	}
	deployed := dwaws.RelativeTime(ds.service.DeployedAt)

	b.WriteString(fmt.Sprintf("   %s  %s", labelStyle.Render("Status: "), status))
	b.WriteString(fmt.Sprintf("    %s  %s", labelStyle.Render("Tasks:"), tasksStr))
	b.WriteString(fmt.Sprintf("    %s  %s", labelStyle.Render("Image:"), digestStyle.Render(digest)))
	b.WriteString(fmt.Sprintf("    %s  %s", labelStyle.Render("Deployed:"), deployed))
	b.WriteString("\n")

	if ds.service.Workflow != "" {
		b.WriteString(fmt.Sprintf("   %s  %s", labelStyle.Render("Workflow:"), dimStyle.Render(ds.service.Workflow)))
		b.WriteString("\n")
	}

	b.WriteString("\n")

	// Tasks section
	b.WriteString(labelStyle.Render(" Tasks"))
	b.WriteString("\n")

	if ds.loading {
		b.WriteString("   Loading tasks...\n")
	} else if ds.err != nil {
		b.WriteString(fmt.Sprintf("   %s\n", errorStyle.Render(fmt.Sprintf("Error: %v", ds.err))))
	} else if len(ds.tasks) == 0 {
		b.WriteString("   No running tasks.\n")
	} else {
		// Task table header
		header := fmt.Sprintf("     %s %s %s %s %s",
			padRight("TASK ID", 38),
			padRight("STATUS", 12),
			padRight("STARTED", 12),
			padRight("IP", 16),
			padRight("CONTAINER", 16),
		)
		b.WriteString(headerStyle.Render(header))
		b.WriteString("\n")

		for i, task := range ds.tasks {
			taskID := task.ID
			if len(taskID) > 36 {
				taskID = taskID[:36]
			}

			started := dwaws.RelativeTime(task.StartedAt)
			ip := task.PrivateIP
			if ip == "" {
				ip = "-"
			}
			container := task.ContainerName
			if container == "" {
				container = "-"
			}

			idCell := padRight(taskID, 38)
			statusCell := padRight(task.Status, 12)
			startedCell := padRight(started, 12)
			ipCell := padRight(ip, 16)
			containerCell := padRight(container, 16)

			if i == ds.taskCursor {
				line := fmt.Sprintf("   > %s %s %s %s %s",
					idCell, statusCell, startedCell, ipCell, containerCell)
				if width > 0 && len(line) < width {
					line += strings.Repeat(" ", width-len(line))
				}
				b.WriteString(selectedStyle.Render(line))
			} else {
				b.WriteString(fmt.Sprintf("     %s %s %s %s %s",
					dimStyle.Render(idCell),
					colorizeTaskStatus(statusCell, task.Status),
					dimStyle.Render(startedCell),
					ipCell,
					dimStyle.Render(containerCell),
				))
			}
			b.WriteString("\n")
		}
	}

	b.WriteString("\n")

	// Deployments section
	if len(ds.service.Deployments) > 0 {
		b.WriteString(labelStyle.Render(" Deployments"))
		b.WriteString("\n")

		depHeader := fmt.Sprintf("     %s %s %s %s %s",
			padRight("STATUS", 12),
			padRight("TASKS", 14),
			padRight("ROLLOUT", 14),
			padRight("AGE", 12),
			padRight("TASK DEF", 30),
		)
		b.WriteString(headerStyle.Render(depHeader))
		b.WriteString("\n")

		for _, dep := range ds.service.Deployments {
			tasks := fmt.Sprintf("%d/%d", dep.RunningCount, dep.DesiredCount)
			if dep.PendingCount > 0 {
				tasks += fmt.Sprintf(" +%dp", dep.PendingCount)
			}
			age := dwaws.RelativeTime(dep.CreatedAt)

			rollout := dep.RolloutState
			if rollout == "" {
				rollout = "-"
			}

			taskDef := dep.TaskDef
			if taskDef == "" {
				taskDef = "-"
			}

			b.WriteString(fmt.Sprintf("     %s %s %s %s %s",
				colorizeDeployStatus(padRight(dep.Status, 12), dep.Status),
				padRight(tasks, 14),
				colorizeRollout(padRight(rollout, 14), dep.RolloutState),
				dimStyle.Render(padRight(age, 12)),
				dimStyle.Render(padRight(taskDef, 30)),
			))
			b.WriteString("\n")
		}
	}

	b.WriteString("\n")
	b.WriteString(dimStyle.Render("   j/k:navigate  s:shell  d:deploy  r:refresh  esc:back"))
	b.WriteString("\n")

	return b.String()
}

// colorizeTaskStatus applies color to a task status cell.
func colorizeTaskStatus(padded, status string) string {
	switch status {
	case "RUNNING":
		return taskCountOKStyle.Render(padded)
	case "PENDING", "PROVISIONING", "ACTIVATING":
		return taskCountWarnStyle.Render(padded)
	case "STOPPED", "DEACTIVATING", "STOPPING":
		return failureStyle.Render(padded)
	default:
		return padded
	}
}

// colorizeDeployStatus applies color to a deployment status cell.
func colorizeDeployStatus(padded, status string) string {
	switch status {
	case "PRIMARY":
		return successStyle.Render(padded)
	case "ACTIVE":
		return taskCountWarnStyle.Render(padded)
	default:
		return padded
	}
}

// colorizeRollout applies color to a rollout state cell.
func colorizeRollout(padded, state string) string {
	switch state {
	case "COMPLETED":
		return successStyle.Render(padded)
	case "IN_PROGRESS":
		return taskCountWarnStyle.Render(padded)
	case "FAILED":
		return failureStyle.Render(padded)
	default:
		return padded
	}
}
