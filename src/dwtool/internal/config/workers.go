package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

// WorkerDef represents a single worker definition from workers.json.
type WorkerDef struct {
	CPU       int    `json:"cpu"`
	Memory    int    `json:"memory"`
	Category  string `json:"category"`
	Spot      bool   `json:"spot"`
	MinCount  int    `json:"min_count"`
	MaxCount  int    `json:"max_count"`
	TargetCPU int    `json:"target_cpu"`
}

// WorkersConfig is the top-level structure of workers.json.
type WorkersConfig struct {
	Workers map[string]WorkerDef `json:"workers"`
}

// CategoryOrder defines the display order for worker categories.
var CategoryOrder = []string{
	"email",
	"esn",
	"importer",
	"misc",
	"scheduled",
	"search",
	"sqs",
	"syndication",
}

// LoadWorkers loads and parses the workers.json file.
// It uses the explicit path if given, otherwise $LJHOME/config/workers.json.
func LoadWorkers(explicitPath string) (*WorkersConfig, error) {
	path := explicitPath
	if path == "" {
		ljhome := os.Getenv("LJHOME")
		if ljhome == "" {
			return nil, fmt.Errorf("LJHOME not set and no --workers-json provided")
		}
		path = filepath.Join(ljhome, "config", "workers.json")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", path, err)
	}

	var cfg WorkersConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing %s: %w", path, err)
	}
	return &cfg, nil
}

// WorkersByCategory returns worker names grouped by category, sorted.
func (c *WorkersConfig) WorkersByCategory() map[string][]string {
	if c == nil {
		return nil
	}
	result := make(map[string][]string)
	for name, def := range c.Workers {
		result[def.Category] = append(result[def.Category], name)
	}
	for cat := range result {
		sort.Strings(result[cat])
	}
	return result
}
