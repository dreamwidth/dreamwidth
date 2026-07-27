package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/github"
	"dreamwidth.org/dwtool/internal/model"
)

// These are the headless deploy commands. They are deliberately conservative:
// a deploy only fires when --yes is given. Without --yes the command performs
// every read-only step (resolve the service, validate that the image digest
// actually exists in GHCR, resolve the workflow target) and prints the exact
// plan it WOULD trigger, then exits 0 without calling GitHub. This makes the
// default safe to run in production and easy to preview before committing.
//
// They reuse the same internal packages as the TUI and the read commands, so
// the service -> workflow -> image-base mappings stay a single source of truth.

// resolveDeployTarget picks the deploy target (workflow + workflow service
// input + image base) for a service, honoring an optional --target label when
// the service has more than one deploy source.
func resolveDeployTarget(svc model.Service, target string) (model.DeployTarget, error) {
	targets := svc.DeployTargets
	if len(targets) == 0 {
		if svc.Workflow == "" {
			return model.DeployTarget{}, fmt.Errorf("service %q has no deploy workflow (group=%s)", svc.Name, dash(svc.Group))
		}
		targets = []model.DeployTarget{{
			Label:       "",
			Workflow:    svc.Workflow,
			WorkflowSvc: svc.WorkflowSvc,
			ImageBase:   svc.ImageBase,
		}}
	}
	if target == "" {
		return targets[0], nil
	}
	for _, t := range targets {
		if t.Label == target {
			return t, nil
		}
	}
	var labels []string
	for _, t := range targets {
		labels = append(labels, dash(t.Label))
	}
	return model.DeployTarget{}, fmt.Errorf("unknown target %q for %s; available: %s", target, svc.Name, strings.Join(labels, ", "))
}

// resolveDigest validates the user-supplied digest against the images actually
// present in GHCR for imageBase and returns the matching image (whose .Digest is
// the full "sha256:..." form used as the workflow tag). The user may pass the
// full digest (with or without the sha256: prefix) or the abbreviated form shown
// by `dwtool images`; exactly one image must match, so a typo or stale digest
// fails loudly instead of triggering a deploy of the wrong (or nonexistent) image.
func resolveDigest(repo, imageBase, userDigest string, limit int) (model.Image, error) {
	want := strings.TrimPrefix(strings.TrimSpace(userDigest), "sha256:")
	if want == "" {
		return model.Image{}, fmt.Errorf("an explicit image digest is required")
	}
	images, err := github.FetchImages(repo, imageBase, limit)
	if err != nil {
		return model.Image{}, fmt.Errorf("listing images for %s: %w", imageBase, err)
	}
	var matches []model.Image
	for _, img := range images {
		bare := strings.TrimPrefix(img.Digest, "sha256:")
		if bare == want || strings.HasPrefix(bare, want) {
			matches = append(matches, img)
		}
	}
	switch len(matches) {
	case 1:
		return matches[0], nil
	case 0:
		return model.Image{}, fmt.Errorf("digest %q not found among the last %d images of %s (try a larger --limit, or recheck the digest)", userDigest, limit, imageBase)
	default:
		return model.Image{}, fmt.Errorf("digest %q is ambiguous (%d matches in %s); pass the full digest", userDigest, len(matches), imageBase)
	}
}

// waitForRun finds the workflow run created after `since` and polls it to
// completion, printing status transitions. Returns the final conclusion
// ("success", "failure", "cancelled", ...).
func waitForRun(repo, workflow string, since time.Time) (string, error) {
	var runID int
	findDeadline := time.Now().Add(2 * time.Minute)
	for {
		id, err := github.FindWorkflowRun(repo, workflow, since)
		if err != nil {
			return "", fmt.Errorf("finding workflow run: %w", err)
		}
		if id != 0 {
			runID = id
			break
		}
		if time.Now().After(findDeadline) {
			return "", fmt.Errorf("timed out waiting for the run to appear (it may still be starting; check GitHub Actions)")
		}
		time.Sleep(3 * time.Second)
	}
	fmt.Printf("  run id:   %d\n", runID)
	fmt.Printf("  run url:  https://github.com/%s/actions/runs/%d\n", repo, runID)

	lastStatus := ""
	pollDeadline := time.Now().Add(30 * time.Minute)
	for {
		status, conclusion, err := github.GetWorkflowRun(repo, runID)
		if err != nil {
			return "", fmt.Errorf("polling run %d: %w", runID, err)
		}
		if status != lastStatus {
			fmt.Printf("  status:   %s\n", status)
			lastStatus = status
		}
		if status == "completed" {
			return conclusion, nil
		}
		if time.Now().After(pollDeadline) {
			return "", fmt.Errorf("timed out after 30m polling run %d (still %s); check GitHub Actions", runID, status)
		}
		time.Sleep(5 * time.Second)
	}
}

// runDeploy implements `dwtool deploy <service> <digest>`.
func runDeploy(args []string) {
	service, rest := peelPositional(args)
	digest, rest := peelPositional(rest)

	fs := flag.NewFlagSet("deploy", flag.ExitOnError)
	region := fs.String("region", config.DefaultRegion, "AWS region")
	cluster := fs.String("cluster", config.DefaultCluster, "ECS cluster name")
	repo := fs.String("repo", config.DefaultRepo, "GitHub repository (owner/name)")
	target := fs.String("target", "", "deploy target label when a service has more than one (e.g. worker22)")
	limit := fs.Int("limit", 50, "how many recent GHCR images to search when resolving the digest")
	wait := fs.Bool("wait", false, "block until the GitHub Actions run completes; exit non-zero on failure")
	yes := fs.Bool("yes", false, "actually trigger the deploy (without this flag the command is a dry run)")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: dwtool deploy <service> <digest> [options]\n\n")
		fmt.Fprintf(os.Stderr, "Deploy a specific image digest to one ECS service by triggering its\n")
		fmt.Fprintf(os.Stderr, "GitHub Actions deploy workflow. The digest must be an explicit image\n")
		fmt.Fprintf(os.Stderr, "digest (full or abbreviated) that exists in GHCR -- there is no 'latest'\n")
		fmt.Fprintf(os.Stderr, "shortcut. Without --yes this is a DRY RUN that only prints the plan.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  dwtool deploy web-stable-service 110ddd7f52bd             # dry run\n")
		fmt.Fprintf(os.Stderr, "  dwtool deploy web-stable-service 110ddd7f52bd --yes       # execute\n")
		fmt.Fprintf(os.Stderr, "  dwtool deploy web-stable-service 110ddd7f52bd --yes --wait\n")
	}
	if err := fs.Parse(rest); err != nil {
		os.Exit(1)
	}
	leftover := fs.Args()
	if service == "" && len(leftover) > 0 {
		service, leftover = leftover[0], leftover[1:]
	}
	if digest == "" && len(leftover) > 0 {
		digest, leftover = leftover[0], leftover[1:]
	}
	if service == "" || digest == "" {
		fmt.Fprintf(os.Stderr, "Error: both <service> and <digest> are required\n\n")
		fs.Usage()
		os.Exit(1)
	}

	client := newAWSClient(*region, *cluster)
	ctx := context.Background()

	services, err := client.DescribeServices(ctx, []string{service})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	if len(services) == 0 {
		fmt.Fprintf(os.Stderr, "Error: service %q not found in cluster %q\n", service, *cluster)
		os.Exit(1)
	}
	svc := services[0]
	if updated, _ := client.FetchServiceImages(ctx, []model.Service{svc}); len(updated) > 0 {
		svc = updated[0]
	}

	tgt, err := resolveDeployTarget(svc, *target)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	img, err := resolveDigest(*repo, tgt.ImageBase, digest, *limit)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Deploy plan for %s\n", svc.Name)
	fmt.Printf("  workflow: %s (service=%s)\n", tgt.Workflow, tgt.WorkflowSvc)
	fmt.Printf("  source:   %s\n", tgt.ImageBase)
	fmt.Printf("  current:  %s\n", dash(svc.ImageDigest))
	fmt.Printf("  deploy:   %s\n", shortDigest(img.Digest))
	if len(img.Tags) > 0 {
		fmt.Printf("  tags:     %s\n", strings.Join(img.Tags, ", "))
	}
	if img.CommitMsg != "" {
		fmt.Printf("  commit:   %s\n", img.CommitMsg)
	}
	if isDeployed(img, svc.ImageDigest) {
		fmt.Printf("  note:     this digest is already the running image\n")
	}

	if !*yes {
		fmt.Printf("\n[dry run] no deploy triggered. Re-run with --yes to execute.\n")
		return
	}

	inputs := map[string]string{
		"service": tgt.WorkflowSvc,
		"tag":     img.Digest, // full sha256:... digest, as the workflow expects
	}
	since := time.Now()
	fmt.Printf("\nTriggering %s ...\n", tgt.Workflow)
	if err := github.TriggerWorkflow(*repo, tgt.Workflow, inputs); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("  triggered.\n")

	if !*wait {
		fmt.Printf("Deploy started on GitHub Actions (%s). Use --wait to block on completion.\n", tgt.Workflow)
		return
	}

	conclusion, err := waitForRun(*repo, tgt.Workflow, since)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("  result:   %s\n", conclusion)
	if conclusion != "success" {
		os.Exit(1)
	}
}

// runDeployCategory implements `dwtool deploy-category <category> <digest>`,
// deploying one image digest to every worker in a workers.json category.
func runDeployCategory(args []string) {
	category, rest := peelPositional(args)
	digest, rest := peelPositional(rest)

	fs := flag.NewFlagSet("deploy-category", flag.ExitOnError)
	repo := fs.String("repo", config.DefaultRepo, "GitHub repository (owner/name)")
	workersJSON := fs.String("workers-json", "", "path to config/workers.json (auto-detected from $LJHOME if empty)")
	target := fs.String("target", "worker22", "worker deploy target: worker22 (default) or worker")
	limit := fs.Int("limit", 50, "how many recent GHCR images to search when resolving the digest")
	wait := fs.Bool("wait", false, "block until all triggered runs complete; exit non-zero on any failure")
	yes := fs.Bool("yes", false, "actually trigger the deploys (without this flag the command is a dry run)")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: dwtool deploy-category <category> <digest> [options]\n\n")
		fmt.Fprintf(os.Stderr, "Deploy one image digest to every worker in a workers.json category.\n")
		fmt.Fprintf(os.Stderr, "Without --yes this is a DRY RUN that only prints the plan.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  dwtool deploy-category search 8bffde07b265           # dry run\n")
		fmt.Fprintf(os.Stderr, "  dwtool deploy-category search 8bffde07b265 --yes --wait\n")
	}
	if err := fs.Parse(rest); err != nil {
		os.Exit(1)
	}
	leftover := fs.Args()
	if category == "" && len(leftover) > 0 {
		category, leftover = leftover[0], leftover[1:]
	}
	if digest == "" && len(leftover) > 0 {
		digest, leftover = leftover[0], leftover[1:]
	}
	if category == "" || digest == "" {
		fmt.Fprintf(os.Stderr, "Error: both <category> and <digest> are required\n\n")
		fs.Usage()
		os.Exit(1)
	}

	var workflow, imageBase string
	switch *target {
	case "worker22":
		workflow, imageBase = config.WorkflowWorker22, config.ImageBaseWorker22
	case "worker":
		workflow, imageBase = config.WorkflowWorker, config.ImageBaseWorker
	default:
		fmt.Fprintf(os.Stderr, "Error: unknown --target %q; use worker22 or worker\n", *target)
		os.Exit(1)
	}

	workers, err := config.LoadWorkers(*workersJSON)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	byCat := workers.WorkersByCategory()
	names := byCat[category]
	if len(names) == 0 {
		var cats []string
		for c := range byCat {
			cats = append(cats, c)
		}
		sort.Strings(cats)
		fmt.Fprintf(os.Stderr, "Error: no workers in category %q; available: %s\n", category, strings.Join(cats, ", "))
		os.Exit(1)
	}
	sort.Strings(names)

	img, err := resolveDigest(*repo, imageBase, digest, *limit)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Deploy plan for category %q (%d workers)\n", category, len(names))
	fmt.Printf("  workflow: %s\n", workflow)
	fmt.Printf("  source:   %s\n", imageBase)
	fmt.Printf("  deploy:   %s\n", shortDigest(img.Digest))
	if img.CommitMsg != "" {
		fmt.Printf("  commit:   %s\n", img.CommitMsg)
	}
	fmt.Printf("  workers:  %s\n", strings.Join(names, ", "))

	if !*yes {
		fmt.Printf("\n[dry run] no deploys triggered. Re-run with --yes to execute.\n")
		return
	}

	// Trigger each worker sequentially. When --wait is set we find each
	// worker's run immediately after triggering it (before the next trigger),
	// so "most recent run of this workflow after `since`" reliably maps to the
	// worker we just triggered -- the worker deploy workflow is shared, so the
	// run can only be disambiguated by trigger order.
	type runRef struct {
		name  string
		runID int
	}
	var runs []runRef
	failed := false

	for _, name := range names {
		inputs := map[string]string{"service": name, "tag": img.Digest}
		since := time.Now()
		fmt.Printf("\nTriggering %s for %s ...\n", workflow, name)
		if err := github.TriggerWorkflow(*repo, workflow, inputs); err != nil {
			fmt.Fprintf(os.Stderr, "  error triggering %s: %v\n", name, err)
			failed = true
			continue
		}
		fmt.Printf("  triggered.\n")

		if *wait {
			id := 0
			deadline := time.Now().Add(90 * time.Second)
			for id == 0 && time.Now().Before(deadline) {
				time.Sleep(3 * time.Second)
				found, ferr := github.FindWorkflowRun(*repo, workflow, since)
				if ferr != nil {
					fmt.Fprintf(os.Stderr, "  warn: finding run for %s: %v\n", name, ferr)
					break
				}
				id = found
			}
			if id == 0 {
				fmt.Fprintf(os.Stderr, "  warn: could not find run for %s (it may still appear on GitHub)\n", name)
			} else {
				fmt.Printf("  run id:   %d\n", id)
			}
			runs = append(runs, runRef{name, id})
		}
	}

	if !*wait {
		if failed {
			os.Exit(1)
		}
		fmt.Printf("\nAll triggers sent. Use --wait to block on completion.\n")
		return
	}

	fmt.Printf("\nWaiting for %d runs to complete ...\n", len(runs))
	done := make([]bool, len(runs))
	pollDeadline := time.Now().Add(40 * time.Minute)
	for {
		allDone := true
		for i := range runs {
			if done[i] {
				continue
			}
			if runs[i].runID == 0 {
				done[i] = true
				failed = true
				continue
			}
			status, conclusion, gerr := github.GetWorkflowRun(*repo, runs[i].runID)
			if gerr != nil {
				fmt.Fprintf(os.Stderr, "  warn: polling %s: %v\n", runs[i].name, gerr)
				allDone = false
				continue
			}
			if status == "completed" {
				done[i] = true
				fmt.Printf("  %s: %s\n", runs[i].name, conclusion)
				if conclusion != "success" {
					failed = true
				}
			} else {
				allDone = false
			}
		}
		if allDone {
			break
		}
		if time.Now().After(pollDeadline) {
			fmt.Fprintf(os.Stderr, "  timed out waiting for some runs; check GitHub Actions\n")
			failed = true
			break
		}
		time.Sleep(5 * time.Second)
	}

	if failed {
		os.Exit(1)
	}
	fmt.Printf("\nAll deploys succeeded.\n")
}
