package aws

import (
	"context"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	cwtypes "github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"

	"dreamwidth.org/dwtool/internal/model"
)

// ListSQSQueues discovers SQS queues by prefix and fetches their attributes.
func (c *Client) ListSQSQueues(ctx context.Context, prefix string) ([]model.SQSQueue, error) {
	// List queues with the given prefix
	listOut, err := c.sqs.ListQueues(ctx, &sqs.ListQueuesInput{
		QueueNamePrefix: &prefix,
	})
	if err != nil {
		return nil, fmt.Errorf("listing SQS queues: %w", err)
	}

	var queues []model.SQSQueue
	for _, url := range listOut.QueueUrls {
		q, err := c.getQueueAttributes(ctx, url, prefix)
		if err != nil {
			// Skip queues we can't describe rather than failing entirely
			continue
		}
		queues = append(queues, q)
	}

	// Fetch throughput from CloudWatch and merge into results
	throughput := c.fetchSQSThroughput(ctx, queues)
	for i := range queues {
		if rate, ok := throughput[queues[i].URL]; ok {
			queues[i].Throughput = rate
		}
	}

	return queues, nil
}

// getQueueAttributes fetches metrics for a single SQS queue.
func (c *Client) getQueueAttributes(ctx context.Context, queueURL, prefix string) (model.SQSQueue, error) {
	out, err := c.sqs.GetQueueAttributes(ctx, &sqs.GetQueueAttributesInput{
		QueueUrl: &queueURL,
		AttributeNames: []sqstypes.QueueAttributeName{
			sqstypes.QueueAttributeNameApproximateNumberOfMessages,
			sqstypes.QueueAttributeNameApproximateNumberOfMessagesNotVisible,
			sqstypes.QueueAttributeNameApproximateNumberOfMessagesDelayed,
		},
	})
	if err != nil {
		return model.SQSQueue{}, fmt.Errorf("getting attributes for %s: %w", queueURL, err)
	}

	// Extract queue name from URL (last path segment)
	name := queueURL
	if idx := strings.LastIndex(queueURL, "/"); idx >= 0 {
		name = queueURL[idx+1:]
	}

	// Strip the configured prefix for display
	displayName := strings.TrimPrefix(name, prefix)

	pending := attrInt(out.Attributes, "ApproximateNumberOfMessages")
	inFlight := attrInt(out.Attributes, "ApproximateNumberOfMessagesNotVisible")
	delayed := attrInt(out.Attributes, "ApproximateNumberOfMessagesDelayed")
	isDLQ := strings.HasSuffix(name, "-dlq")

	return model.SQSQueue{
		Name:     displayName,
		URL:      queueURL,
		Pending:  pending,
		InFlight: inFlight,
		Delayed:  delayed,
		IsDLQ:    isDLQ,
	}, nil
}

// fetchSQSThroughput uses CloudWatch GetMetricData to fetch NumberOfMessagesReceived
// for all queues in a single API call. Returns a map of queue URL -> "~N/min" string.
func (c *Client) fetchSQSThroughput(ctx context.Context, queues []model.SQSQueue) map[string]string {
	if len(queues) == 0 {
		return nil
	}

	// Build metric queries — one per queue
	now := time.Now()
	startTime := now.Add(-5 * time.Minute)

	var queries []cwtypes.MetricDataQuery
	// Map query ID back to queue URL
	idToURL := make(map[string]string, len(queues))

	for i, q := range queues {
		// Extract full queue name from URL for CloudWatch dimension
		queueName := q.URL
		if idx := strings.LastIndex(q.URL, "/"); idx >= 0 {
			queueName = q.URL[idx+1:]
		}

		id := fmt.Sprintf("q%d", i)
		idToURL[id] = q.URL

		queries = append(queries, cwtypes.MetricDataQuery{
			Id: aws.String(id),
			MetricStat: &cwtypes.MetricStat{
				Metric: &cwtypes.Metric{
					Namespace:  aws.String("AWS/SQS"),
					MetricName: aws.String("NumberOfMessagesReceived"),
					Dimensions: []cwtypes.Dimension{
						{Name: aws.String("QueueName"), Value: aws.String(queueName)},
					},
				},
				Period: aws.Int32(300), // 5-minute period
				Stat:   aws.String("Sum"),
			},
		})
	}

	out, err := c.cw.GetMetricData(ctx, &cloudwatch.GetMetricDataInput{
		StartTime:         &startTime,
		EndTime:           &now,
		MetricDataQueries: queries,
	})
	if err != nil {
		// Non-fatal: just return empty throughput
		return nil
	}

	result := make(map[string]string, len(queues))
	for _, r := range out.MetricDataResults {
		if r.Id == nil || len(r.Values) == 0 {
			continue
		}
		url := idToURL[*r.Id]
		// Sum of messages received in the 5-minute window, scale to per-minute
		total := r.Values[0]
		perMin := total / 5.0
		if perMin < 0.5 {
			continue // too low to display
		}
		result[url] = fmt.Sprintf("~%d/min", int(math.Round(perMin)))
	}

	return result
}

// attrInt parses an integer from the SQS attributes map.
func attrInt(attrs map[string]string, key string) int {
	if v, ok := attrs[key]; ok {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return 0
}
