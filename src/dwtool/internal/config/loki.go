package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// LokiConfig holds credentials for querying Grafana Cloud Loki.
type LokiConfig struct {
	Host     string `json:"host"`     // e.g. "logs-prod-042.grafana.net"
	User     string `json:"user"`     // numeric instance ID
	Password string `json:"password"` // API token
}

// ConfigFile is the top-level structure of ~/.config/dwtool/config.json.
type ConfigFile struct {
	Loki LokiConfig `json:"loki"`
}

// configFilePath returns ~/.config/dwtool/config.json.
func configFilePath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "dwtool", "config.json")
}

// LoadLokiConfig loads Loki credentials from the config file,
// with environment variable overrides:
//
//	DWTOOL_LOKI_HOST     (default: from config file)
//	DWTOOL_LOKI_USER     (default: from config file)
//	DWTOOL_LOKI_PASSWORD (default: from config file)
func LoadLokiConfig() (*LokiConfig, error) {
	cfg := &LokiConfig{}

	// Try config file first
	data, err := os.ReadFile(configFilePath())
	if err == nil {
		var file ConfigFile
		if err := json.Unmarshal(data, &file); err == nil {
			cfg = &file.Loki
		}
	}

	// Environment overrides
	if v := os.Getenv("DWTOOL_LOKI_HOST"); v != "" {
		cfg.Host = v
	}
	if v := os.Getenv("DWTOOL_LOKI_USER"); v != "" {
		cfg.User = v
	}
	if v := os.Getenv("DWTOOL_LOKI_PASSWORD"); v != "" {
		cfg.Password = v
	}

	if cfg.Host == "" || cfg.User == "" || cfg.Password == "" {
		return nil, fmt.Errorf(
			"Loki credentials not configured.\n\n"+
				"Either create %s:\n"+
				"  {\n"+
				"    \"loki\": {\n"+
				"      \"host\": \"logs-prod-042.grafana.net\",\n"+
				"      \"user\": \"1549950\",\n"+
				"      \"password\": \"glc_...\"\n"+
				"    }\n"+
				"  }\n\n"+
				"Or set environment variables:\n"+
				"  export DWTOOL_LOKI_HOST=logs-prod-042.grafana.net\n"+
				"  export DWTOOL_LOKI_USER=1549950\n"+
				"  export DWTOOL_LOKI_PASSWORD=glc_...\n",
			configFilePath(),
		)
	}

	return cfg, nil
}
