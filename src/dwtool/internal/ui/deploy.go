package ui

import (
	"fmt"
	"strings"
	"time"

	dwaws "dreamwidth.org/dwtool/internal/aws"
	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/model"
)

// deployStep tracks which step of the deploy flow we're on.
type deployStep int

const (
	stepSelectTarget deployStep = iota
	stepSelectImage
	stepConfirm
	stepProgress
)

// deployState holds all state for the deploy flow.
type deployState struct {
	service     model.Service
	images      []model.Image
	imageCursor int
	step        deployStep
	loading     bool
	err         error
	message     string

	// Target selection (when service has multiple deploy sources)
	targets      []model.DeployTarget
	targetCursor int

	// for "all workers" deploy
	allWorkers bool

	// Progress tracking
	triggered  time.Time
	runID      int
	runStatus  string // "queued", "in_progress", "completed"
	conclusion string // "success", "failure", "cancelled"
	nextHint   string // "Next: deploy web-shop" after web-canary
}

// selectedTarget returns the currently selected deploy target.
func (ds deployState) selectedTarget() model.DeployTarget {
	if ds.targetCursor >= 0 && ds.targetCursor < len(ds.targets) {
		return ds.targets[ds.targetCursor]
	}
	// Fallback to service's primary values
	return model.DeployTarget{
		Label:       "",
		Workflow:    ds.service.Workflow,
		WorkflowSvc: ds.service.WorkflowSvc,
		ImageBase:   ds.service.ImageBase,
	}
}

// imageScrollOffset returns the scroll offset for the image list viewport.
// We keep the cursor centered when possible.
func imageScrollOffset(cursor, total, viewportHeight int) int {
	if total <= viewportHeight {
		return 0
	}
	half := viewportHeight / 2
	offset := cursor - half
	if offset < 0 {
		offset = 0
	}
	if offset > total-viewportHeight {
		offset = total - viewportHeight
	}
	return offset
}

// renderDeployView renders the appropriate deploy step.
func renderDeployView(ds deployState, width, height int) string {
	switch ds.step {
	case stepSelectTarget:
		return renderTargetSelectView(ds, width)
	case stepSelectImage:
		return renderImageSelectView(ds, width, height)
	case stepConfirm:
		return renderConfirmView(ds, width)
	case stepProgress:
		return renderProgressView(ds, width)
	default:
		return ""
	}
}

// renderTargetSelectView shows a list of deploy sources to choose from.
func renderTargetSelectView(ds deployState, width int) string {
	var b strings.Builder

	serviceName := ds.service.Name
	if ds.allWorkers {
		serviceName = "ALL WORKERS"
	}
	b.WriteString(labelStyle.Render(fmt.Sprintf(" Deploy %s — Select Image Source", serviceName)))
	b.WriteString("\n\n")

	for i, target := range ds.targets {
		label := padRight(target.Label, 16)
		source := dimStyle.Render(target.ImageBase)

		if i == ds.targetCursor {
			line := fmt.Sprintf("   %s %s", label, target.ImageBase)
			if width > 0 && len(line) < width {
				line += strings.Repeat(" ", width-len(line))
			}
			b.WriteString(selectedStyle.Render(line))
		} else {
			b.WriteString(fmt.Sprintf("   %s %s", label, source))
		}
		b.WriteString("\n")
	}

	b.WriteString("\n")
	b.WriteString(dimStyle.Render("   j/k:navigate  enter:select  esc:cancel"))
	b.WriteString("\n")

	return b.String()
}

// renderImageSelectView shows a list of GHCR images to choose from.
func renderImageSelectView(ds deployState, width, height int) string {
	var b strings.Builder

	serviceName := ds.service.Name
	if ds.allWorkers {
		serviceName = "ALL WORKERS"
	}
	target := ds.selectedTarget()
	sourceLabel := ""
	if target.Label != "" {
		sourceLabel = fmt.Sprintf(" (%s)", target.Label)
	}
	b.WriteString(labelStyle.Render(fmt.Sprintf(" Deploy %s%s — Select Image", serviceName, sourceLabel)))
	b.WriteString("\n\n")

	if ds.loading {
		b.WriteString("   Loading images...\n")
		return b.String()
	}

	if ds.err != nil {
		b.WriteString(fmt.Sprintf("   %s\n", errorStyle.Render(fmt.Sprintf("Error: %v", ds.err))))
		b.WriteString("\n   Press Esc to go back.\n")
		return b.String()
	}

	if len(ds.images) == 0 {
		b.WriteString("   No images found.\n")
		b.WriteString("\n   Press Esc to go back.\n")
		return b.String()
	}

	// Compute commit message column width from available terminal width
	// Layout: marker(3) + digest(14) + tags(22) + age(12) = 51 fixed, rest for commit
	commitCol := width - 51
	if commitCol < 10 {
		commitCol = 10
	}
	if commitCol > 60 {
		commitCol = 60
	}

	// Header for image list
	header := fmt.Sprintf("     %s %s %s %s",
		padRight("DIGEST", 14),
		padRight("TAGS", 22),
		padRight("AGE", 12),
		padRight("COMMIT", commitCol),
	)
	b.WriteString(headerStyle.Render(header))
	b.WriteString("\n")

	// Calculate available height for images (subtract: title(2) + header(1) + footer hint(2) = 5)
	listHeight := height - 9
	if listHeight < 3 {
		listHeight = 3
	}

	offset := imageScrollOffset(ds.imageCursor, len(ds.images), listHeight)
	end := offset + listHeight
	if end > len(ds.images) {
		end = len(ds.images)
	}

	for i := offset; i < end; i++ {
		img := ds.images[i]

		// Format digest (first 12 chars after "sha256:" prefix)
		digest := img.Digest
		if strings.HasPrefix(digest, "sha256:") {
			digest = digest[7:]
		}
		if len(digest) > 12 {
			digest = digest[:12]
		}

		// Check if this is the currently deployed image
		isDeployed := ds.service.ImageDigest != "" && strings.HasPrefix(
			strings.TrimPrefix(img.Digest, "sha256:"),
			ds.service.ImageDigest,
		)
		marker := "   "
		if isDeployed {
			marker = " * "
		}

		// Format tags
		tags := strings.Join(img.Tags, ", ")
		if len(tags) > 20 {
			tags = tags[:17] + "..."
		}
		if tags == "" {
			tags = "(untagged)"
		}

		age := dwaws.RelativeTime(img.CreatedAt)

		// Format commit message
		commit := img.CommitMsg
		if len(commit) > commitCol-2 {
			commit = commit[:commitCol-5] + "..."
		}

		digestCell := padRight(digest, 14)
		tagsCell := padRight(tags, 22)
		ageCell := padRight(age, 12)
		commitCell := commit

		if i == ds.imageCursor {
			line := fmt.Sprintf("%s%s %s %s %s", marker, digestCell, tagsCell, ageCell, commitCell)
			if width > 0 && len(line) < width {
				line += strings.Repeat(" ", width-len(line))
			}
			b.WriteString(selectedStyle.Render(line))
		} else {
			deployedMarker := marker
			if isDeployed {
				deployedMarker = successStyle.Render(marker)
			}
			b.WriteString(fmt.Sprintf("%s%s %s %s %s",
				deployedMarker,
				digestStyle.Render(digestCell),
				tagsCell,
				dimStyle.Render(ageCell),
				dimStyle.Render(commitCell),
			))
		}
		b.WriteString("\n")
	}

	// Scroll indicator
	if len(ds.images) > listHeight {
		b.WriteString(dimStyle.Render(fmt.Sprintf("\n   Showing %d-%d of %d images", offset+1, end, len(ds.images))))
		b.WriteString("\n")
	}

	b.WriteString("\n")
	b.WriteString(dimStyle.Render("   j/k:navigate  enter:select  esc:cancel  *=deployed"))
	b.WriteString("\n")

	return b.String()
}

// renderConfirmView shows the confirmation prompt.
func renderConfirmView(ds deployState, width int) string {
	var b strings.Builder

	serviceName := ds.service.Name
	if ds.allWorkers {
		serviceName = "ALL WORKERS (*)"
	}

	b.WriteString(confirmStyle.Render(" Confirm Deploy"))
	b.WriteString("\n\n")

	// Service info
	b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Service: "), serviceName))

	// Image info
	img := ds.images[ds.imageCursor]
	digest := img.Digest
	shortDigest := digest
	if strings.HasPrefix(shortDigest, "sha256:") {
		shortDigest = shortDigest[7:]
	}
	if len(shortDigest) > 12 {
		shortDigest = shortDigest[:12]
	}

	tags := strings.Join(img.Tags, ", ")
	if tags == "" {
		tags = "(untagged)"
	}

	target := ds.selectedTarget()

	b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Image:   "), shortDigest))
	b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Tags:    "), tags))
	b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Age:     "), dwaws.RelativeTime(img.CreatedAt)))
	if img.CommitMsg != "" {
		b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Commit:  "), img.CommitMsg))
	}

	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Workflow:"), target.Workflow))
	b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Source:  "), target.ImageBase))

	b.WriteString("\n")
	b.WriteString(confirmStyle.Render("   Press Y (Shift+Y) to deploy, any other key to cancel."))
	b.WriteString("\n")

	return b.String()
}

// renderProgressView shows the deploy progress.
func renderProgressView(ds deployState, width int) string {
	var b strings.Builder

	serviceName := ds.service.Name
	if ds.allWorkers {
		serviceName = "ALL WORKERS (*)"
	}

	b.WriteString(labelStyle.Render(fmt.Sprintf(" Deploying %s", serviceName)))
	b.WriteString("\n\n")

	// Show what was triggered
	img := ds.images[ds.imageCursor]
	shortDigest := img.Digest
	if strings.HasPrefix(shortDigest, "sha256:") {
		shortDigest = shortDigest[7:]
	}
	if len(shortDigest) > 12 {
		shortDigest = shortDigest[:12]
	}
	b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Image:"), shortDigest))

	b.WriteString("\n")

	if ds.err != nil {
		b.WriteString(fmt.Sprintf("   %s\n", failureStyle.Render(fmt.Sprintf("Error: %v", ds.err))))
		b.WriteString("\n")
		b.WriteString(dimStyle.Render("   Press Esc to go back."))
		b.WriteString("\n")
		return b.String()
	}

	// Status display
	if ds.runID == 0 {
		b.WriteString(fmt.Sprintf("   %s Triggering workflow...\n", spinnerFrames[spinnerFrame(ds.triggered)]))
	} else {
		b.WriteString(fmt.Sprintf("   %s  %d\n", labelStyle.Render("Run ID:"), ds.runID))

		switch ds.runStatus {
		case "completed":
			switch ds.conclusion {
			case "success":
				b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Status:"), successStyle.Render("SUCCESS")))
			case "failure":
				b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Status:"), failureStyle.Render("FAILED")))
			case "cancelled":
				b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Status:"), confirmStyle.Render("CANCELLED")))
			default:
				b.WriteString(fmt.Sprintf("   %s  %s (%s)\n", labelStyle.Render("Status:"), ds.runStatus, ds.conclusion))
			}
		case "in_progress":
			b.WriteString(fmt.Sprintf("   %s  %s In progress...\n", labelStyle.Render("Status:"), spinnerFrames[spinnerFrame(ds.triggered)]))
		case "queued":
			b.WriteString(fmt.Sprintf("   %s  %s Queued...\n", labelStyle.Render("Status:"), spinnerFrames[spinnerFrame(ds.triggered)]))
		default:
			if ds.runStatus != "" {
				b.WriteString(fmt.Sprintf("   %s  %s\n", labelStyle.Render("Status:"), ds.runStatus))
			} else {
				b.WriteString(fmt.Sprintf("   %s Looking for workflow run...\n", spinnerFrames[spinnerFrame(ds.triggered)]))
			}
		}
	}

	// Next hint for web deploy order
	if ds.nextHint != "" && ds.runStatus == "completed" && ds.conclusion == "success" {
		b.WriteString("\n")
		b.WriteString(fmt.Sprintf("   %s\n", successStyle.Render(ds.nextHint)))
	}

	b.WriteString("\n")
	if ds.runStatus == "completed" {
		b.WriteString(dimStyle.Render("   Press Esc to go back."))
	} else {
		b.WriteString(dimStyle.Render("   Press Esc to go back (deploy continues on GitHub)."))
	}
	b.WriteString("\n")

	return b.String()
}

// nextWebService returns a hint for the next web service to deploy, or empty if none.
func nextWebService(currentService string) string {
	order := config.WebDeployOrder
	for i, name := range order {
		if name == currentService && i+1 < len(order) {
			return fmt.Sprintf("Next: deploy %s (select it and press d)", order[i+1])
		}
	}
	return ""
}

// Simple text spinner for progress display (no dependency on bubbletea spinner).
var spinnerFrames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

func spinnerFrame(since time.Time) int {
	elapsed := time.Since(since)
	idx := int(elapsed.Milliseconds()/100) % len(spinnerFrames)
	return idx
}
