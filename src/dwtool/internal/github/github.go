package github

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"dreamwidth.org/dwtool/internal/model"
)

// ghPackageVersion represents a single GHCR package version from the GitHub API.
type ghPackageVersion struct {
	ID        int    `json:"id"`
	Name      string `json:"name"` // the sha256 digest
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
	Metadata  struct {
		Container struct {
			Tags []string `json:"tags"`
		} `json:"container"`
	} `json:"metadata"`
}

// ghWorkflowRun represents a workflow run from gh run list.
type ghWorkflowRun struct {
	DatabaseID int    `json:"databaseId"`
	CreatedAt  string `json:"createdAt"`
}

// ghRunView represents a workflow run from gh run view.
type ghRunView struct {
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
}

// FetchImages lists recent GHCR package versions for the given image base.
// imageBase is like "ghcr.io/dreamwidth/web" — we extract "web" as the package name.
func FetchImages(repo, imageBase string, limit int) ([]model.Image, error) {
	// Extract package name from imageBase (e.g. "ghcr.io/dreamwidth/web" -> "web")
	parts := strings.Split(imageBase, "/")
	if len(parts) < 2 {
		return nil, fmt.Errorf("invalid image base: %s", imageBase)
	}
	packageName := parts[len(parts)-1]

	// Extract org from repo (e.g. "dreamwidth/dreamwidth" -> "dreamwidth")
	repoParts := strings.SplitN(repo, "/", 2)
	if len(repoParts) != 2 {
		return nil, fmt.Errorf("invalid repo: %s", repo)
	}
	org := repoParts[0]

	// gh api to list package versions
	apiPath := fmt.Sprintf("/orgs/%s/packages/container/%s/versions?per_page=%d", org, packageName, limit)
	out, err := exec.Command("gh", "api", apiPath).Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("gh api failed: %s", string(exitErr.Stderr))
		}
		return nil, fmt.Errorf("gh api failed: %w", err)
	}

	var versions []ghPackageVersion
	if err := json.Unmarshal(out, &versions); err != nil {
		return nil, fmt.Errorf("parsing GHCR response: %w", err)
	}

	var images []model.Image
	for _, v := range versions {
		created, _ := time.Parse(time.RFC3339, v.CreatedAt)
		images = append(images, model.Image{
			Digest:    v.Name,
			Tags:      v.Metadata.Container.Tags,
			CreatedAt: created,
		})
	}

	return images, nil
}

// TriggerWorkflow dispatches a GitHub Actions workflow.
// inputs is a map of workflow input keys to values (e.g. {"service": "web-canary", "tag": "sha256:abc..."}).
func TriggerWorkflow(repo, workflow string, inputs map[string]string) error {
	args := []string{"workflow", "run", workflow, "-R", repo}
	for k, v := range inputs {
		args = append(args, "-f", k+"="+v)
	}

	cmd := exec.Command("gh", args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("gh workflow run failed: %s", strings.TrimSpace(string(out)))
	}
	return nil
}

// FindWorkflowRun finds the most recent workflow run created after `since`.
// Returns the run ID or 0 if not found.
func FindWorkflowRun(repo, workflow string, since time.Time) (int, error) {
	out, err := exec.Command("gh", "run", "list",
		"--workflow="+workflow,
		"-R", repo,
		"--json", "databaseId,createdAt",
		"--limit", "5",
	).Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return 0, fmt.Errorf("gh run list failed: %s", string(exitErr.Stderr))
		}
		return 0, fmt.Errorf("gh run list failed: %w", err)
	}

	var runs []ghWorkflowRun
	if err := json.Unmarshal(out, &runs); err != nil {
		return 0, fmt.Errorf("parsing run list: %w", err)
	}

	for _, r := range runs {
		created, err := time.Parse(time.RFC3339, r.CreatedAt)
		if err != nil {
			continue
		}
		if created.After(since) {
			return r.DatabaseID, nil
		}
	}

	return 0, nil
}

// GetWorkflowRun returns the status and conclusion of a workflow run.
func GetWorkflowRun(repo string, runID int) (status, conclusion string, err error) {
	out, err := exec.Command("gh", "run", "view",
		fmt.Sprintf("%d", runID),
		"-R", repo,
		"--json", "status,conclusion",
	).Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return "", "", fmt.Errorf("gh run view failed: %s", string(exitErr.Stderr))
		}
		return "", "", fmt.Errorf("gh run view failed: %w", err)
	}

	var run ghRunView
	if err := json.Unmarshal(out, &run); err != nil {
		return "", "", fmt.Errorf("parsing run view: %w", err)
	}

	return run.Status, run.Conclusion, nil
}

// ResolveCommitMessages tries to find git commit messages for images
// by looking at their tags for SHA-like strings and running git log.
func ResolveCommitMessages(images []model.Image) {
	for i, img := range images {
		sha := extractGitSHA(img.Tags)
		if sha == "" {
			continue
		}
		msg, err := gitCommitMessage(sha)
		if err == nil && msg != "" {
			images[i].CommitMsg = msg
		}
	}
}

// extractGitSHA finds a git commit SHA from image tags.
// Looks for "sha-{hex}" (GitHub Actions convention) or raw hex strings.
func extractGitSHA(tags []string) string {
	// Prefer "sha-{hex}" format (GitHub Actions docker/metadata-action convention)
	for _, tag := range tags {
		if strings.HasPrefix(tag, "sha-") {
			hex := tag[4:]
			if isHex(hex) && len(hex) >= 7 {
				return hex
			}
		}
	}
	// Fall back to raw hex that looks like a git SHA
	for _, tag := range tags {
		if isHex(tag) && len(tag) >= 7 && len(tag) <= 40 {
			return tag
		}
	}
	return ""
}

func isHex(s string) bool {
	if len(s) == 0 {
		return false
	}
	for _, c := range s {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return true
}

func gitCommitMessage(sha string) (string, error) {
	out, err := exec.Command("git", "log", "--format=%s", "-1", sha).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
