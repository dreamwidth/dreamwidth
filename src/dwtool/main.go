package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"

	dwaws "dreamwidth.org/dwtool/internal/aws"
	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/ui"
)

func main() {
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
