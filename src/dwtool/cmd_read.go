package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
	"text/tabwriter"

	dwaws "dreamwidth.org/dwtool/internal/aws"
	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/github"
	"dreamwidth.org/dwtool/internal/model"
)

// These are the headless, non-TUI read commands. They share the same internal
// packages (aws, github, config) as the TUI so the service→workflow→image
// mappings have a single source of truth. Each command prints human-readable
// text by default and machine-readable JSON with --json, and uses exit codes
// so the result can be checked from a script.

// peelPositional pulls a leading non-flag argument off the front of args so a
// command can be invoked as either "<cmd> <name> [flags]" or "<cmd> [flags]
// <name>". The leading form is peeled here; the trailing form falls out of
// flag.Parse stopping at the first non-flag (read back via fs.Arg(0)).
func peelPositional(args []string) (positional string, rest []string) {
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		return args[0], args[1:]
	}
	return "", args
}

// newAWSClient builds the AWS client used by the ECS-backed read commands,
// exiting with a clear message if credentials or region resolution fail.
func newAWSClient(region, cluster string) *dwaws.Client {
	client, err := dwaws.NewClient(region, cluster)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing AWS client: %v\n", err)
		os.Exit(1)
	}
	return client
}

// emitJSON marshals v as indented JSON to stdout, exiting on error.
func emitJSON(v interface{}) {
	out, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error encoding JSON: %v\n", err)
		os.Exit(1)
	}
	fmt.Println(string(out))
}

// runServices lists ECS services with their current rollout state.
func runServices(args []string) {
	fs := flag.NewFlagSet("services", flag.ExitOnError)
	jsonOut := fs.Bool("json", false, "output JSON")
	region := fs.String("region", config.DefaultRegion, "AWS region")
	cluster := fs.String("cluster", config.DefaultCluster, "ECS cluster name")
	group := fs.String("group", "", "filter by group: web, worker, proxy, other")
	filter := fs.String("filter", "", "only services whose name contains this substring")
	noImages := fs.Bool("no-images", false, "skip resolving running image digests (faster)")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: dwtool services [options]\n\n")
		fmt.Fprintf(os.Stderr, "List ECS services and their rollout state.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  dwtool services\n")
		fmt.Fprintf(os.Stderr, "  dwtool services --group web --json\n")
		fmt.Fprintf(os.Stderr, "  dwtool services --filter esn\n")
	}
	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	client := newAWSClient(*region, *cluster)
	ctx := context.Background()

	names, err := client.ListServices(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	services, err := client.DescribeServices(ctx, names)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	if !*noImages {
		services, err = client.FetchServiceImages(ctx, services)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: could not resolve all image digests: %v\n", err)
		}
	}

	services = filterServices(services, *group, *filter)
	sort.Slice(services, func(i, j int) bool {
		if services[i].Group != services[j].Group {
			return services[i].Group < services[j].Group
		}
		return services[i].Name < services[j].Name
	})

	if *jsonOut {
		emitJSON(services)
		return
	}

	if len(services) == 0 {
		fmt.Fprintln(os.Stderr, "No services matched.")
		return
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "GROUP\tSERVICE\tSTATUS\tTASKS\tDIGEST\tROLLOUT\tDEPLOYED")
	for _, s := range services {
		rollout := "-"
		if len(s.Deployments) > 0 {
			rollout = s.Deployments[0].RolloutState
		}
		if s.Deploying {
			rollout += " (deploying)"
		}
		digest := s.ImageDigest
		if digest == "" {
			digest = "-"
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
			dash(s.Group),
			s.Name,
			s.Status,
			dwaws.TaskCount(s.RunningCount, s.DesiredCount),
			digest,
			rollout,
			dwaws.RelativeTime(s.DeployedAt),
		)
	}
	w.Flush()
}

// runStatus shows a single service's deployments and running tasks.
func runStatus(args []string) {
	name, rest := peelPositional(args)
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	jsonOut := fs.Bool("json", false, "output JSON")
	region := fs.String("region", config.DefaultRegion, "AWS region")
	cluster := fs.String("cluster", config.DefaultCluster, "ECS cluster name")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: dwtool status <service> [options]\n\n")
		fmt.Fprintf(os.Stderr, "Show a service's deployments and running tasks.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  dwtool status web-stable-service\n")
		fmt.Fprintf(os.Stderr, "  dwtool status worker-esn-process-sub-service --json\n")
	}
	if err := fs.Parse(rest); err != nil {
		os.Exit(1)
	}
	if name == "" {
		name = fs.Arg(0)
	}
	if name == "" {
		fmt.Fprintf(os.Stderr, "Error: service name is required\n\n")
		fs.Usage()
		os.Exit(1)
	}

	client := newAWSClient(*region, *cluster)
	ctx := context.Background()

	services, err := client.DescribeServices(ctx, []string{name})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	if len(services) == 0 {
		fmt.Fprintf(os.Stderr, "Error: service %q not found in cluster %q\n", name, *cluster)
		os.Exit(1)
	}
	svc := services[0]
	updated, _ := client.FetchServiceImages(ctx, []model.Service{svc})
	if len(updated) > 0 {
		svc = updated[0]
	}

	tasks, err := client.ListTasks(ctx, name)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: could not list tasks: %v\n", err)
	}

	if *jsonOut {
		emitJSON(struct {
			Service model.Service `json:"service"`
			Tasks   []model.Task  `json:"tasks"`
		}{svc, tasks})
		return
	}

	fmt.Printf("%s\n", svc.Name)
	fmt.Printf("  group:    %s\n", dash(svc.Group))
	fmt.Printf("  status:   %s\n", svc.Status)
	fmt.Printf("  tasks:    %s running\n", dwaws.TaskCount(svc.RunningCount, svc.DesiredCount))
	fmt.Printf("  digest:   %s\n", dash(svc.ImageDigest))
	if svc.Workflow != "" {
		fmt.Printf("  workflow: %s (service=%s)\n", svc.Workflow, svc.WorkflowSvc)
	}
	if len(svc.DeployTargets) > 0 {
		var labels []string
		for _, t := range svc.DeployTargets {
			labels = append(labels, t.Label)
		}
		fmt.Printf("  targets:  %s\n", strings.Join(labels, ", "))
	}

	if len(svc.Deployments) > 0 {
		fmt.Println("\n  deployments:")
		w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
		fmt.Fprintln(w, "    STATUS\tROLLOUT\tTASKS\tTASKDEF\tCREATED")
		for _, d := range svc.Deployments {
			fmt.Fprintf(w, "    %s\t%s\t%s\t%s\t%s\n",
				d.Status,
				dash(d.RolloutState),
				dwaws.TaskCount(d.RunningCount, d.DesiredCount),
				dash(d.TaskDef),
				dwaws.RelativeTime(d.CreatedAt),
			)
		}
		w.Flush()
	}

	if len(tasks) > 0 {
		fmt.Println("\n  running tasks:")
		w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
		fmt.Fprintln(w, "    TASK\tSTATUS\tCONTAINER\tIP\tSTARTED")
		for _, t := range tasks {
			fmt.Fprintf(w, "    %s\t%s\t%s\t%s\t%s\n",
				t.ID, t.Status, dash(t.ContainerName), dash(t.PrivateIP), dwaws.RelativeTime(t.StartedAt))
		}
		w.Flush()
	}
}

// runImages lists deployable GHCR images for a service's image base.
func runImages(args []string) {
	name, rest := peelPositional(args)
	fs := flag.NewFlagSet("images", flag.ExitOnError)
	jsonOut := fs.Bool("json", false, "output JSON")
	region := fs.String("region", config.DefaultRegion, "AWS region")
	cluster := fs.String("cluster", config.DefaultCluster, "ECS cluster name")
	repo := fs.String("repo", config.DefaultRepo, "GitHub repository (owner/name)")
	target := fs.String("target", "", "deploy target label when a service has more than one (e.g. worker22)")
	limit := fs.Int("limit", 20, "max images to list")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: dwtool images <service> [options]\n\n")
		fmt.Fprintf(os.Stderr, "List recent GHCR images deployable to a service, newest first.\n")
		fmt.Fprintf(os.Stderr, "The currently-deployed image is marked with '*'.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  dwtool images web-stable-service\n")
		fmt.Fprintf(os.Stderr, "  dwtool images worker-esn-process-sub-service --target worker22\n")
	}
	if err := fs.Parse(rest); err != nil {
		os.Exit(1)
	}
	if name == "" {
		name = fs.Arg(0)
	}
	if name == "" {
		fmt.Fprintf(os.Stderr, "Error: service name is required\n\n")
		fs.Usage()
		os.Exit(1)
	}

	client := newAWSClient(*region, *cluster)
	ctx := context.Background()

	services, err := client.DescribeServices(ctx, []string{name})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	if len(services) == 0 {
		fmt.Fprintf(os.Stderr, "Error: service %q not found in cluster %q\n", name, *cluster)
		os.Exit(1)
	}
	svc := services[0]
	updated, _ := client.FetchServiceImages(ctx, []model.Service{svc})
	if len(updated) > 0 {
		svc = updated[0]
	}

	imageBase, err := resolveImageBase(svc, *target)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	images, err := github.FetchImages(*repo, imageBase, *limit)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	github.ResolveCommitMessages(images)

	type imageOut struct {
		model.Image
		Deployed bool `json:"deployed"`
	}
	var out []imageOut
	for _, img := range images {
		out = append(out, imageOut{Image: img, Deployed: isDeployed(img, svc.ImageDigest)})
	}

	if *jsonOut {
		emitJSON(struct {
			Service   string     `json:"service"`
			ImageBase string     `json:"image_base"`
			Images    []imageOut `json:"images"`
		}{svc.Name, imageBase, out})
		return
	}

	fmt.Printf("%s  (source: %s)\n\n", svc.Name, imageBase)
	if len(out) == 0 {
		fmt.Fprintln(os.Stderr, "No images found.")
		return
	}
	w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "\tDIGEST\tTAGS\tAGE\tCOMMIT")
	for _, o := range out {
		marker := " "
		if o.Deployed {
			marker = "*"
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n",
			marker,
			shortDigest(o.Digest),
			dash(strings.Join(o.Tags, ", ")),
			dwaws.RelativeTime(o.CreatedAt),
			o.CommitMsg,
		)
	}
	w.Flush()
	fmt.Fprintln(os.Stderr, "\n* = currently deployed")
}

// resolveImageBase picks the GHCR image base for a service, honoring an
// optional target label when the service has more than one deploy source.
func resolveImageBase(svc model.Service, target string) (string, error) {
	if svc.ImageBase == "" && len(svc.DeployTargets) == 0 {
		return "", fmt.Errorf("service %q has no deployable image source (group=%s)", svc.Name, dash(svc.Group))
	}
	if target == "" {
		if svc.ImageBase != "" {
			return svc.ImageBase, nil
		}
		return svc.DeployTargets[0].ImageBase, nil
	}
	for _, t := range svc.DeployTargets {
		if t.Label == target {
			return t.ImageBase, nil
		}
	}
	var labels []string
	for _, t := range svc.DeployTargets {
		labels = append(labels, t.Label)
	}
	return "", fmt.Errorf("unknown target %q for %s; available: %s", target, svc.Name, strings.Join(labels, ", "))
}

// isDeployed reports whether a GHCR image matches the service's running digest.
// svc.ImageDigest is an abbreviated (12-char) digest; image digests carry a
// "sha256:" prefix, so we compare on the abbreviated tail.
func isDeployed(img model.Image, deployedDigest string) bool {
	if deployedDigest == "" {
		return false
	}
	return strings.HasPrefix(strings.TrimPrefix(img.Digest, "sha256:"), deployedDigest)
}

// filterServices applies the optional --group and --filter narrowing.
func filterServices(services []model.Service, group, filter string) []model.Service {
	if group == "" && filter == "" {
		return services
	}
	var out []model.Service
	for _, s := range services {
		if group != "" && s.Group != group {
			continue
		}
		if filter != "" && !strings.Contains(s.Name, filter) {
			continue
		}
		out = append(out, s)
	}
	return out
}

// shortDigest trims the "sha256:" prefix and clips to 12 hex chars for display.
func shortDigest(d string) string {
	d = strings.TrimPrefix(d, "sha256:")
	if len(d) > 12 {
		d = d[:12]
	}
	return d
}

// dash returns "-" for an empty string, otherwise the string unchanged.
func dash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}
