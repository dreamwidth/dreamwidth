package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	dwaws "dreamwidth.org/dwtool/internal/aws"
	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/model"
	"dreamwidth.org/dwtool/internal/ui"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "logscan" {
		runLogScan(os.Args[2:])
		return
	}

	if len(os.Args) > 1 && os.Args[1] == "esn-trace" {
		runESNTrace(os.Args[2:])
		return
	}

	var cfg config.Config
	flag.StringVar(&cfg.Region, "region", config.DefaultRegion, "AWS region")
	flag.StringVar(&cfg.Cluster, "cluster", config.DefaultCluster, "ECS cluster name")
	flag.StringVar(&cfg.Repo, "repo", config.DefaultRepo, "GitHub repository (owner/name)")
	flag.StringVar(&cfg.WorkersDir, "workers-json", "", "path to config/workers.json (auto-detected if empty)")
	flag.StringVar(&cfg.SQSPrefix, "sqs-prefix", config.DefaultSQSPrefix, "SQS queue name prefix for discovery")
	flag.Parse()

	// Load workers config
	workers, err := config.LoadWorkers(cfg.WorkersDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: %v\nWorkers will appear ungrouped. Use --workers-json to specify the path.\n", err)
	}

	// Create AWS client
	client, err := dwaws.NewClient(cfg.Region, cfg.Cluster)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing AWS client: %v\n", err)
		os.Exit(1)
	}

	app := ui.NewApp(cfg, workers, client)
	p := tea.NewProgram(app, tea.WithAltScreen())

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func runLogScan(args []string) {
	fs := flag.NewFlagSet("logscan", flag.ExitOnError)
	keyword := fs.String("keyword", "", "search keyword (required)")
	since := fs.String("since", "24h", "how far back to search (e.g. 1h, 24h, 7d)")
	region := fs.String("region", config.DefaultRegion, "AWS region")
	cluster := fs.String("cluster", config.DefaultCluster, "ECS cluster name")
	groups := fs.String("groups", "", "glob pattern to filter log groups (e.g. '*esn*', '*web*')")
	limit := fs.Int("limit", 500, "max results per log group (0 = unlimited)")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: dwtool logscan -keyword <term> [options]\n\n")
		fmt.Fprintf(os.Stderr, "Search CloudWatch logs across all Dreamwidth services.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  dwtool logscan -keyword exampleuser\n")
		fmt.Fprintf(os.Stderr, "  dwtool logscan -keyword exampleuser -since 7d\n")
		fmt.Fprintf(os.Stderr, "  dwtool logscan -keyword exampleuser -since 7d -groups '*esn*'\n")
		fmt.Fprintf(os.Stderr, "  dwtool logscan -keyword 'error.*timeout' -groups '*web*' -since 1h\n")
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	if *keyword == "" {
		fmt.Fprintf(os.Stderr, "Error: -keyword is required\n\n")
		fs.Usage()
		os.Exit(1)
	}

	// Parse duration
	duration, err := parseDuration(*since)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: invalid -since value %q: %v\n", *since, err)
		os.Exit(1)
	}

	ctx := context.Background()

	// Create AWS client
	client, err := dwaws.NewClient(*region, *cluster)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing AWS client: %v\n", err)
		os.Exit(1)
	}

	// Discover log groups
	fmt.Fprintf(os.Stderr, "Discovering log groups...\n")
	logGroups, err := client.ListLogGroups(ctx, "/dreamwidth/")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error listing log groups: %v\n", err)
		os.Exit(1)
	}

	// Filter by glob if specified
	if *groups != "" {
		var filtered []string
		for _, lg := range logGroups {
			// Match against the full path and just the last segment
			name := lg[strings.LastIndex(lg, "/")+1:]
			matched, _ := filepath.Match(*groups, name)
			if !matched {
				matched, _ = filepath.Match(*groups, lg)
			}
			if matched {
				filtered = append(filtered, lg)
			}
		}
		logGroups = filtered
	}

	if len(logGroups) == 0 {
		fmt.Fprintf(os.Stderr, "No log groups found")
		if *groups != "" {
			fmt.Fprintf(os.Stderr, " matching %q", *groups)
		}
		fmt.Fprintf(os.Stderr, "\n")
		os.Exit(1)
	}

	fmt.Fprintf(os.Stderr, "Searching %d log groups for %q (last %s)...\n", len(logGroups), *keyword, *since)

	now := time.Now()

	// Wrap keyword in quotes for CloudWatch literal substring matching
	pattern := fmt.Sprintf("%q", *keyword)

	// Build 1-hour chunks from newest to oldest
	type timeChunk struct {
		start time.Time
		end   time.Time
	}
	var chunks []timeChunk
	chunkEnd := now
	oldest := now.Add(-duration)
	for chunkEnd.After(oldest) {
		chunkStart := chunkEnd.Add(-time.Hour)
		if chunkStart.Before(oldest) {
			chunkStart = oldest
		}
		chunks = append(chunks, timeChunk{start: chunkStart, end: chunkEnd})
		chunkEnd = chunkStart
	}

	// Search chunk by chunk, newest first
	type result struct {
		logGroup string
		events   []model.LogEvent
		err      error
	}

	totalMatches := 0
	totalErrors := 0

	for ci, chunk := range chunks {
		label := chunk.start.Format("2006-01-02 15:04") + " to " + chunk.end.Format("15:04")
		fmt.Fprintf(os.Stderr, "[%d/%d] %s\n", ci+1, len(chunks), label)

		// Search all log groups concurrently within this chunk
		results := make(chan result, len(logGroups))
		var wg sync.WaitGroup

		for _, lg := range logGroups {
			wg.Add(1)
			go func(logGroup string) {
				defer wg.Done()
				events, err := client.SearchLogs(ctx, logGroup, pattern, chunk.start, chunk.end, *limit)
				results <- result{logGroup: logGroup, events: events, err: err}
			}(lg)
		}

		go func() {
			wg.Wait()
			close(results)
		}()

		// Collect this chunk's results
		type taggedEvent struct {
			logGroup string
			event    model.LogEvent
		}
		var chunkEvents []taggedEvent

		for r := range results {
			if r.err != nil {
				fmt.Fprintf(os.Stderr, "  error: %s: %v\n", r.logGroup, r.err)
				totalErrors++
				continue
			}
			for _, ev := range r.events {
				chunkEvents = append(chunkEvents, taggedEvent{logGroup: r.logGroup, event: ev})
			}
		}

		if len(chunkEvents) == 0 {
			continue
		}

		// Sort within chunk by timestamp
		sort.Slice(chunkEvents, func(i, j int) bool {
			return chunkEvents[i].event.Timestamp.Before(chunkEvents[j].event.Timestamp)
		})

		totalMatches += len(chunkEvents)
		fmt.Fprintf(os.Stderr, "  %d match(es)\n", len(chunkEvents))

		for _, te := range chunkEvents {
			ts := te.event.Timestamp.Format("2006-01-02 15:04:05")
			group := strings.TrimPrefix(te.logGroup, "/dreamwidth/")
			fmt.Printf("[%s] %-30s %s\n", ts, group, te.event.Message)
		}
	}

	if totalMatches == 0 {
		fmt.Fprintf(os.Stderr, "No matches found.\n")
	} else {
		fmt.Fprintf(os.Stderr, "Done. %d total match(es).\n", totalMatches)
	}
}

func runESNTrace(args []string) {
	fs := flag.NewFlagSet("esn-trace", flag.ExitOnError)
	since := fs.String("since", "1h", "how far back to search (e.g. 1h, 24h, 7d)")
	region := fs.String("region", config.DefaultRegion, "AWS region")
	limit := fs.Int("limit", 1000, "max results per log group")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: dwtool esn-trace <trace-id> [options]\n\n")
		fmt.Fprintf(os.Stderr, "Trace an ESN event through the full notification pipeline.\n\n")
		fmt.Fprintf(os.Stderr, "The trace-id is the event's raw params joined with colons:\n")
		fmt.Fprintf(os.Stderr, "  ETYPEID:JOURNALID:ARG1:ARG2  (e.g. 3:48205:2847193:0)\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  dwtool esn-trace 3:48205:2847193:0\n")
		fmt.Fprintf(os.Stderr, "  dwtool esn-trace 3:48205:2847193:0 -since 24h\n")
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	traceID := fs.Arg(0)
	if traceID == "" {
		fmt.Fprintf(os.Stderr, "Error: trace-id is required\n\n")
		fs.Usage()
		os.Exit(1)
	}

	duration, err := parseDuration(*since)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: invalid -since value %q: %v\n", *since, err)
		os.Exit(1)
	}

	ctx := context.Background()

	client, err := dwaws.NewClient(*region, config.DefaultCluster)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing AWS client: %v\n", err)
		os.Exit(1)
	}

	// Search all 4 ESN log groups
	esnLogGroups := []string{
		"/dreamwidth/worker/dw-esn-fired-event",
		"/dreamwidth/worker/dw-esn-cluster-subs",
		"/dreamwidth/worker/dw-esn-filter-subs",
		"/dreamwidth/worker/dw-esn-process-sub",
	}

	now := time.Now()
	startTime := now.Add(-duration)
	pattern := fmt.Sprintf("\"[esn %s]\"", traceID)

	fmt.Fprintf(os.Stderr, "Searching for trace %s (last %s)...\n", traceID, *since)

	type taggedEvent struct {
		logGroup string
		event    model.LogEvent
	}

	var allEvents []taggedEvent
	var mu sync.Mutex
	var wg sync.WaitGroup

	for _, lg := range esnLogGroups {
		wg.Add(1)
		go func(logGroup string) {
			defer wg.Done()
			events, err := client.SearchLogs(ctx, logGroup, pattern, startTime, now, *limit)
			if err != nil {
				fmt.Fprintf(os.Stderr, "  error: %s: %v\n", logGroup, err)
				return
			}
			mu.Lock()
			for _, ev := range events {
				allEvents = append(allEvents, taggedEvent{logGroup: logGroup, event: ev})
			}
			mu.Unlock()
		}(lg)
	}

	wg.Wait()

	if len(allEvents) == 0 {
		fmt.Fprintf(os.Stderr, "No events found for trace %s\n", traceID)
		os.Exit(0)
	}

	// Sort by timestamp
	sort.Slice(allEvents, func(i, j int) bool {
		return allEvents[i].event.Timestamp.Before(allEvents[j].event.Timestamp)
	})

	// Pretty-print with stage labels
	stageNames := map[string]string{
		"/dreamwidth/worker/dw-esn-fired-event":  "fired-event",
		"/dreamwidth/worker/dw-esn-cluster-subs": "cluster-subs",
		"/dreamwidth/worker/dw-esn-filter-subs":  "filter-subs",
		"/dreamwidth/worker/dw-esn-process-sub":  "process-sub",
	}

	fmt.Fprintf(os.Stderr, "Found %d events:\n\n", len(allEvents))

	for _, te := range allEvents {
		ts := te.event.Timestamp.Format("15:04:05.000")
		stage := stageNames[te.logGroup]
		if stage == "" {
			stage = te.logGroup
		}
		// Strip the [esn ...] prefix from the message since we're already showing the trace
		msg := te.event.Message
		prefix := fmt.Sprintf("[esn %s] ", traceID)
		if idx := strings.Index(msg, prefix); idx >= 0 {
			msg = msg[:idx] + msg[idx+len(prefix):]
		}
		fmt.Printf("%s  [%-13s]  %s\n", ts, stage, strings.TrimSpace(msg))
	}

	fmt.Fprintf(os.Stderr, "\nDone. %d events across %s.\n", len(allEvents), *since)
}

// parseDuration parses a duration string that supports "d" for days
// in addition to Go's standard time.ParseDuration units.
func parseDuration(s string) (time.Duration, error) {
	if strings.HasSuffix(s, "d") {
		s = strings.TrimSuffix(s, "d")
		var days int
		if _, err := fmt.Sscanf(s, "%d", &days); err != nil {
			return 0, fmt.Errorf("invalid day value: %s", s)
		}
		return time.Duration(days) * 24 * time.Hour, nil
	}
	return time.ParseDuration(s)
}
