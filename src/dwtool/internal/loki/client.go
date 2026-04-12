package loki

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/model"
)

// Client queries Grafana Cloud Loki.
type Client struct {
	baseURL  string
	user     string
	password string
	http     *http.Client
}

// NewClient creates a Loki client from config.
func NewClient(cfg *config.LokiConfig) *Client {
	return &Client{
		baseURL:  fmt.Sprintf("https://%s/loki/api/v1", cfg.Host),
		user:     cfg.User,
		password: cfg.Password,
		http:     &http.Client{Timeout: 30 * time.Second},
	}
}

// queryRangeResponse is the Loki API response format.
type queryRangeResponse struct {
	Status string `json:"status"`
	Data   struct {
		ResultType string `json:"resultType"`
		Result     []struct {
			Stream map[string]string `json:"stream"`
			Values [][]string        `json:"values"` // [timestamp_ns, line]
		} `json:"result"`
	} `json:"data"`
}

// Search queries Loki for log lines matching a LogQL expression
// within the given time range.
func (c *Client) Search(logQL string, start, end time.Time, limit int) ([]model.LogEvent, error) {
	params := url.Values{
		"query":     {logQL},
		"start":     {strconv.FormatInt(start.UnixNano(), 10)},
		"end":       {strconv.FormatInt(end.UnixNano(), 10)},
		"limit":     {strconv.Itoa(limit)},
		"direction": {"forward"},
	}

	reqURL := fmt.Sprintf("%s/query_range?%s", c.baseURL, params.Encode())
	req, err := http.NewRequest("GET", reqURL, nil)
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(c.user, c.password)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("loki request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("reading response: %w", err)
	}

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("loki returned %d: %s", resp.StatusCode, string(body[:min(len(body), 200)]))
	}

	var result queryRangeResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("parsing response: %w", err)
	}

	if result.Status != "success" {
		return nil, fmt.Errorf("loki query failed: status=%s", result.Status)
	}

	// Flatten all streams into a single sorted event list
	var events []model.LogEvent
	for _, stream := range result.Data.Result {
		service := stream.Stream["service"]
		for _, val := range stream.Values {
			ts, _ := strconv.ParseInt(val[0], 10, 64)
			msg := val[1]

			// Fluent Bit in key_value format wraps lines as:
			//   source="stderr" log="actual message" container_name="..."
			// Extract just the log= value.
			if idx := strings.Index(msg, `log="`); idx >= 0 {
				inner := msg[idx+5:]
				// Find the closing quote — look for '" ' (quote+space) or
				// a quote at the very end of the string
				end := strings.Index(inner, `" `)
				if end < 0 {
					end = len(inner) - 1
				}
				if end > 0 {
					msg = inner[:end]
				}
			}

			// Strip the log4perl timestamp/level prefix:
			//   2026/04/12 15:45:52 DEBUG> FiredEvent.pm:54 DW::Task::... |
			// Keep everything after the " | " separator.
			if idx := strings.Index(msg, " | "); idx >= 0 {
				msg = msg[idx+3:]
			}

			events = append(events, model.LogEvent{
				Timestamp: time.Unix(0, ts),
				Message:   msg,
				Stream:    service,
			})
		}
	}

	sort.Slice(events, func(i, j int) bool {
		return events[i].Timestamp.Before(events[j].Timestamp)
	})

	return events, nil
}
