package main

import (
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	dwaws "dreamwidth.org/dwtool/internal/aws"
	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/loki"
	"dreamwidth.org/dwtool/internal/ui"
)

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "log-scan":
			runLogScan(os.Args[2:])
			return
		case "esn-trace":
			runESNTrace(os.Args[2:])
			return
		case "help", "--help", "-h":
			printUsage()
			return
		}
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

func printUsage() {
	fmt.Fprintf(os.Stderr, `Usage: dwtool <command> [options]

Commands:
  (default)     Interactive ECS service dashboard (TUI)
  log-scan      Search logs across all Dreamwidth services (via Loki)
  esn-trace     Trace an ESN event through the full notification pipeline

Loki credentials: ~/.config/dwtool/config.json or DWTOOL_LOKI_* env vars.
Run 'dwtool <command> --help' for details on a specific command.
`)
}

// lokiClient creates a Loki client from config, exiting on error.
func lokiClient() *loki.Client {
	cfg, err := config.LoadLokiConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	return loki.NewClient(cfg)
}

func runLogScan(args []string) {
	fs := flag.NewFlagSet("log-scan", flag.ExitOnError)
	keyword := fs.String("keyword", "", "search keyword (required)")
	since := fs.String("since", "24h", "how far back to search (e.g. 1h, 24h, 7d)")
	service := fs.String("service", "", "filter to a specific service label (e.g. 'dw-esn-process-sub')")
	limit := fs.Int("limit", 500, "max results")

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: dwtool log-scan -keyword <term> [options]\n\n")
		fmt.Fprintf(os.Stderr, "Search logs across all Dreamwidth services via Loki.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  dwtool log-scan -keyword exampleuser\n")
		fmt.Fprintf(os.Stderr, "  dwtool log-scan -keyword exampleuser -since 7d\n")
		fmt.Fprintf(os.Stderr, "  dwtool log-scan -keyword exampleuser -service dw-esn-process-sub\n")
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	if *keyword == "" {
		fmt.Fprintf(os.Stderr, "Error: -keyword is required\n\n")
		fs.Usage()
		os.Exit(1)
	}

	duration, err := parseDuration(*since)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: invalid -since value %q: %v\n", *since, err)
		os.Exit(1)
	}

	client := lokiClient()

	// Build LogQL query
	selector := `{source="dreamwidth"}`
	if *service != "" {
		selector = fmt.Sprintf(`{source="dreamwidth",service="%s"}`, *service)
	}
	logQL := fmt.Sprintf(`%s |= %q`, selector, *keyword)

	now := time.Now()
	startTime := now.Add(-duration)

	fmt.Fprintf(os.Stderr, "Searching for %q (last %s)...\n", *keyword, *since)

	events, err := client.Search(logQL, startTime, now, *limit)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if len(events) == 0 {
		fmt.Fprintf(os.Stderr, "No matches found.\n")
		os.Exit(0)
	}

	for _, ev := range events {
		ts := ev.Timestamp.Format("2006-01-02 15:04:05")
		if *service != "" {
			fmt.Printf("[%s] %s\n", ts, ev.Message)
		} else {
			svc := ev.Stream
			if svc == "" {
				svc = "-"
			}
			fmt.Printf("[%s] %-25s %s\n", ts, svc, ev.Message)
		}
	}

	fmt.Fprintf(os.Stderr, "Done. %d match(es).\n", len(events))
}

func runESNTrace(args []string) {
	fs := flag.NewFlagSet("esn-trace", flag.ExitOnError)
	since := fs.String("since", "1h", "how far back to search (e.g. 1h, 24h, 7d)")
	limit := fs.Int("limit", 1000, "max results")

	// Go's flag package stops parsing at the first non-flag argument.
	// Reorder args so flags come first, positional args last.
	var reordered []string
	var positional []string
	for i := 0; i < len(args); i++ {
		if strings.HasPrefix(args[i], "-") {
			reordered = append(reordered, args[i])
			if i+1 < len(args) && !strings.HasPrefix(args[i+1], "-") {
				reordered = append(reordered, args[i+1])
				i++
			}
		} else {
			positional = append(positional, args[i])
		}
	}
	args = append(reordered, positional...)

	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: dwtool esn-trace <trace-id-or-url> [options]\n\n")
		fmt.Fprintf(os.Stderr, "Trace an ESN event through the full notification pipeline.\n\n")
		fmt.Fprintf(os.Stderr, "Accepts either a trace ID or a comment URL:\n")
		fmt.Fprintf(os.Stderr, "  ETYPEID:JOURNALID:ARG1:ARG2  (e.g. 3:48205:2847193:0)\n")
		fmt.Fprintf(os.Stderr, "  https://community.dreamwidth.org/12345.html?thread=67890\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		fs.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  dwtool esn-trace 3:48205:2847193:0\n")
		fmt.Fprintf(os.Stderr, "  dwtool esn-trace 3:48205:2847193:0 -since 24h\n")
		fmt.Fprintf(os.Stderr, "  dwtool esn-trace 'https://rp-community.dreamwidth.org/5678.html?thread=1234567#cmt1234567'\n")
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	input := fs.Arg(0)
	if input == "" {
		fmt.Fprintf(os.Stderr, "Error: trace-id or comment URL is required\n\n")
		fs.Usage()
		os.Exit(1)
	}

	duration, err := parseDuration(*since)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: invalid -since value %q: %v\n", *since, err)
		os.Exit(1)
	}

	client := lokiClient()
	now := time.Now()
	startTime := now.Add(-duration)

	// Resolve input: either a trace ID or a comment URL
	traceID := input
	if strings.HasPrefix(input, "http") {
		traceID = resolveCommentURL(client, input, startTime, now)
	}

	// Search all ESN services for this trace
	esnServices := []string{
		"dw-esn-fired-event",
		"dw-esn-cluster-subs",
		"dw-esn-filter-subs",
		"dw-esn-process-sub",
	}
	selector := `{source="dreamwidth",service=~"` + strings.Join(esnServices, "|") + `"}`
	logQL := fmt.Sprintf(`%s |= "[esn %s]"`, selector, traceID)

	fmt.Fprintf(os.Stderr, "Searching for trace %s (last %s)...\n", traceID, *since)

	events, err := client.Search(logQL, startTime, now, *limit)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	if len(events) == 0 {
		fmt.Fprintf(os.Stderr, "No events found for trace %s\n", traceID)
		os.Exit(0)
	}

	fmt.Fprintf(os.Stderr, "Found %d events:\n\n", len(events))

	for _, ev := range events {
		ts := ev.Timestamp.Format("15:04:05.000")
		stage := ev.Stream
		if stage == "" {
			stage = "-"
		}
		// Strip the [esn ...] prefix from the message since we're already showing the trace
		msg := ev.Message
		prefix := fmt.Sprintf("[esn %s] ", traceID)
		if idx := strings.Index(msg, prefix); idx >= 0 {
			msg = msg[:idx] + msg[idx+len(prefix):]
		}
		fmt.Printf("%s  [%-20s]  %s\n", ts, stage, strings.TrimSpace(msg))
	}

	fmt.Fprintf(os.Stderr, "\nDone. %d events across %s.\n", len(events), *since)
}

// resolveUserID fetches the Dreamwidth profile page for a journal and extracts
// the userid from the "Created on ... (#USERID)" text.
func resolveUserID(username string) (int64, error) {
	profileURL := fmt.Sprintf("https://%s.dreamwidth.org/profile", username)
	req, err := http.NewRequest("GET", profileURL, nil)
	if err != nil {
		return 0, fmt.Errorf("building request: %w", err)
	}
	req.Header.Set("User-Agent", "dwtool/1.0")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, fmt.Errorf("fetching profile: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return 0, fmt.Errorf("profile returned %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, fmt.Errorf("reading profile: %w", err)
	}

	// Look for "(#USERID)" which appears near the "Created on" line
	re := regexp.MustCompile(`\(#(\d+)\),\s+last updated`)
	m := re.FindSubmatch(body)
	if m == nil {
		return 0, fmt.Errorf("could not find userid on profile page")
	}

	return strconv.ParseInt(string(m[1]), 10, 64)
}

// resolveCommentURL parses a Dreamwidth comment URL, extracts the jtalkid,
// resolves the journal's userid from the profile page, and searches the
// fired-event logs in Loki to find the full trace ID.
//
// URL format: https://JOURNAL.dreamwidth.org/DITEMID.html?thread=DTALKID#cmt...
// jtalkid = dtalkid >> 8 (Dreamwidth's display-to-internal ID conversion)
func resolveCommentURL(client *loki.Client, rawURL string, startTime, endTime time.Time) string {
	u, err := url.Parse(rawURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing URL: %v\n", err)
		os.Exit(1)
	}

	// Extract journal username from hostname (e.g. "mark" from "mark.dreamwidth.org")
	hostParts := strings.Split(u.Hostname(), ".")
	if len(hostParts) < 3 || hostParts[len(hostParts)-2]+"."+hostParts[len(hostParts)-1] != "dreamwidth.org" {
		fmt.Fprintf(os.Stderr, "Error: expected a *.dreamwidth.org URL\n")
		os.Exit(1)
	}
	username := strings.Join(hostParts[:len(hostParts)-2], ".")

	// Extract dtalkid from ?thread= parameter
	dtalkidStr := u.Query().Get("thread")
	if dtalkidStr == "" {
		fmt.Fprintf(os.Stderr, "Error: URL has no ?thread= parameter. Need a comment URL, not an entry URL.\n")
		fmt.Fprintf(os.Stderr, "  Example: https://community.dreamwidth.org/12345.html?thread=67890\n")
		os.Exit(1)
	}

	dtalkid, err := strconv.ParseInt(dtalkidStr, 10, 64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: invalid thread ID %q: %v\n", dtalkidStr, err)
		os.Exit(1)
	}

	jtalkid := dtalkid >> 8

	fmt.Fprintf(os.Stderr, "Parsed URL: dtalkid=%d → jtalkid=%d\n", dtalkid, jtalkid)

	// Resolve journal username to userid via profile page
	fmt.Fprintf(os.Stderr, "Resolving userid for %s...\n", username)
	journalid, err := resolveUserID(username)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: could not resolve userid for %s: %v\n", username, err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "Resolved %s → userid %d\n", username, journalid)

	fmt.Fprintf(os.Stderr, "Searching fired-event logs for matching trace...\n")

	logQL := fmt.Sprintf(`{source="dreamwidth",service="dw-esn-fired-event"} |~ "\\[esn \\d+:%d:%d:\\d+\\]"`, journalid, jtalkid)

	events, err := client.Search(logQL, startTime, endTime, 10)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error searching logs: %v\n", err)
		os.Exit(1)
	}

	if len(events) == 0 {
		fmt.Fprintf(os.Stderr, "No fired-event found for jtalkid=%d in the given time range.\n", jtalkid)
		fmt.Fprintf(os.Stderr, "Try expanding the time range with -since (e.g. -since 24h)\n")
		os.Exit(1)
	}

	// Extract the full trace ID from the first matching log line
	re := regexp.MustCompile(`\[esn (\d+:\d+:` + strconv.FormatInt(jtalkid, 10) + `:\d+)\]`)
	for _, ev := range events {
		m := re.FindStringSubmatch(ev.Message)
		if m != nil {
			traceID := m[1]
			fmt.Fprintf(os.Stderr, "Found trace: %s\n\n", traceID)
			return traceID
		}
	}

	fmt.Fprintf(os.Stderr, "Found log lines but couldn't extract trace ID. Raw matches:\n")
	for _, ev := range events {
		fmt.Fprintf(os.Stderr, "  %s\n", ev.Message)
	}
	os.Exit(1)
	return "" // unreachable
}

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
