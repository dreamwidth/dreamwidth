package aws

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	cwltypes "github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs/types"

	"dreamwidth.org/dwtool/internal/model"
)

// LogGroupForService returns the CloudWatch log group name for a service.
// Each service has its own log group: /dreamwidth/web/{key} for web services,
// /dreamwidth/worker/{name} for workers.
// Web WorkflowSvc values have a "web-" prefix (e.g. "web-canary") but the
// log group key is just "canary".
func LogGroupForService(svc model.Service) string {
	switch svc.Group {
	case "web":
		key := strings.TrimPrefix(svc.WorkflowSvc, "web-")
		return "/dreamwidth/web/" + key
	case "worker":
		return "/dreamwidth/worker/" + svc.WorkflowSvc
	default:
		return ""
	}
}

// FetchLogs retrieves recent log events from a CloudWatch log group.
// It returns events sorted by timestamp, limited to the most recent logs within the given duration.
func (c *Client) FetchLogs(ctx context.Context, logGroup string, since time.Duration, limit int) ([]model.LogEvent, error) {
	startTime := time.Now().Add(-since).UnixMilli()

	input := &cloudwatchlogs.FilterLogEventsInput{
		LogGroupName: aws.String(logGroup),
		StartTime:    aws.Int64(startTime),
		Interleaved:  aws.Bool(true),
		Limit:        aws.Int32(int32(limit)),
	}

	var events []model.LogEvent
	paginator := cloudwatchlogs.NewFilterLogEventsPaginator(c.cwl, input)
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, fmt.Errorf("filtering log events: %w", err)
		}
		for _, event := range page.Events {
			events = append(events, cwlEventToModel(event))
		}
		// Stop after we have enough
		if len(events) >= limit {
			events = events[:limit]
			break
		}
	}

	// Sort by timestamp
	sort.Slice(events, func(i, j int) bool {
		return events[i].Timestamp.Before(events[j].Timestamp)
	})

	return events, nil
}

// FetchLogsSince retrieves log events after a given timestamp (for tailing).
// Returns the events and the timestamp of the latest event (for the next call).
func (c *Client) FetchLogsSince(ctx context.Context, logGroup string, afterMs int64) ([]model.LogEvent, int64, error) {
	input := &cloudwatchlogs.FilterLogEventsInput{
		LogGroupName: aws.String(logGroup),
		StartTime:    aws.Int64(afterMs),
		Interleaved:  aws.Bool(true),
	}

	var events []model.LogEvent
	var latestMs int64 = afterMs

	paginator := cloudwatchlogs.NewFilterLogEventsPaginator(c.cwl, input)
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, afterMs, fmt.Errorf("filtering log events: %w", err)
		}
		for _, event := range page.Events {
			ev := cwlEventToModel(event)
			events = append(events, ev)
			if event.Timestamp != nil && *event.Timestamp > latestMs {
				latestMs = *event.Timestamp
			}
		}
	}

	sort.Slice(events, func(i, j int) bool {
		return events[i].Timestamp.Before(events[j].Timestamp)
	})

	return events, latestMs, nil
}

func cwlEventToModel(event cwltypes.FilteredLogEvent) model.LogEvent {
	ev := model.LogEvent{
		Message: strings.TrimRight(aws.ToString(event.Message), "\n"),
	}
	if event.Timestamp != nil {
		ev.Timestamp = time.UnixMilli(*event.Timestamp)
	}
	if event.LogStreamName != nil {
		stream := aws.ToString(event.LogStreamName)
		// Stream names are often long; extract a short suffix
		if parts := strings.Split(stream, "/"); len(parts) > 0 {
			ev.Stream = parts[len(parts)-1]
			if len(ev.Stream) > 12 {
				ev.Stream = ev.Stream[:12]
			}
		}
	}
	return ev
}
