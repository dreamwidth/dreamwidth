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
