package aws

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/ecs"
	ecstypes "github.com/aws/aws-sdk-go-v2/service/ecs/types"
	elbv2 "github.com/aws/aws-sdk-go-v2/service/elasticloadbalancingv2"
	"github.com/aws/aws-sdk-go-v2/service/sqs"

	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/model"
)

// Client wraps the AWS ECS, CloudWatch, ELBv2, and SQS clients.
type Client struct {
	ecs     *ecs.Client
	cw      *cloudwatch.Client
	cwl     *cloudwatchlogs.Client
	elbv2   *elbv2.Client
	sqs     *sqs.Client
	cluster string
}

// NewClient creates a new AWS ECS client.
func NewClient(region, cluster string) (*Client, error) {
	cfg, err := awsconfig.LoadDefaultConfig(context.Background(),
		awsconfig.WithRegion(region),
	)
	if err != nil {
		return nil, fmt.Errorf("loading AWS config: %w", err)
	}
	return &Client{
		ecs:     ecs.NewFromConfig(cfg),
		cw:      cloudwatch.NewFromConfig(cfg),
		cwl:     cloudwatchlogs.NewFromConfig(cfg),
		elbv2:   elbv2.NewFromConfig(cfg),
		sqs:     sqs.NewFromConfig(cfg),
		cluster: cluster,
	}, nil
}

// ListServices returns all ECS service names in the cluster.
func (c *Client) ListServices(ctx context.Context) ([]string, error) {
	var names []string
	paginator := ecs.NewListServicesPaginator(c.ecs, &ecs.ListServicesInput{
		Cluster: aws.String(c.cluster),
	})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, fmt.Errorf("listing services: %w", err)
		}
		for _, arn := range page.ServiceArns {
			// Extract service name from ARN
			parts := strings.Split(arn, "/")
			if len(parts) > 0 {
				names = append(names, parts[len(parts)-1])
			}
		}
	}
	sort.Strings(names)
	return names, nil
}

// DescribeServices returns detailed info for the given service names.
// AWS limits DescribeServices to 10 at a time, so we batch.
func (c *Client) DescribeServices(ctx context.Context, names []string) ([]model.Service, error) {
	var result []model.Service

	for i := 0; i < len(names); i += 10 {
		end := i + 10
		if end > len(names) {
			end = len(names)
		}
		batch := names[i:end]

		out, err := c.ecs.DescribeServices(ctx, &ecs.DescribeServicesInput{
			Cluster:  aws.String(c.cluster),
			Services: batch,
		})
		if err != nil {
			return nil, fmt.Errorf("describing services: %w", err)
		}

		for _, svc := range out.Services {
			s := ecsServiceToModel(svc)
			result = append(result, s)
		}
	}

	return result, nil
}

// ListTasks returns running tasks for a service.
func (c *Client) ListTasks(ctx context.Context, serviceName string) ([]model.Task, error) {
	listOut, err := c.ecs.ListTasks(ctx, &ecs.ListTasksInput{
		Cluster:     aws.String(c.cluster),
		ServiceName: aws.String(serviceName),
	})
	if err != nil {
		return nil, fmt.Errorf("listing tasks: %w", err)
	}
	if len(listOut.TaskArns) == 0 {
		return nil, nil
	}

	descOut, err := c.ecs.DescribeTasks(ctx, &ecs.DescribeTasksInput{
		Cluster: aws.String(c.cluster),
		Tasks:   listOut.TaskArns,
	})
	if err != nil {
		return nil, fmt.Errorf("describing tasks: %w", err)
	}

	var tasks []model.Task
	for _, t := range descOut.Tasks {
		task := ecsTaskToModel(t, serviceName)
		tasks = append(tasks, task)
	}
	return tasks, nil
}

// pickAppContainerIndex returns the index in names of the best container to
// target. It prefers the real app container by name ("web" for web tasks,
// "worker" for worker tasks). Sidecars (cloudwatch-agent, log_router)
// don't run an ECS-Exec agent capable of accepting a shell, so they're
// excluded from the fallback. Returns -1 if names is empty.
//
// This is the single source of truth for container selection within
// dwtool — both the task-name surfaced in the dashboard and the
// container picked for image-digest extraction route through here.
// bin/ecs-shell carries an equivalent JMESPath version since bash and
// Go can't share code; keep the two in sync if the policy changes.
func pickAppContainerIndex(names []string) int {
	for i, name := range names {
		if name == "web" || name == "worker" {
			return i
		}
	}
	for i, name := range names {
		if name != "cloudwatch-agent" && name != "log_router" {
			return i
		}
	}
	if len(names) > 0 {
		return 0
	}
	return -1
}

func ecsServiceToModel(svc ecstypes.Service) model.Service {
	name := aws.ToString(svc.ServiceName)
	s := model.Service{
		Name:         name,
		Status:       aws.ToString(svc.Status),
		RunningCount: int(svc.RunningCount),
		DesiredCount: int(svc.DesiredCount),
		PendingCount: int(svc.PendingCount),
		Deploying:    len(svc.Deployments) > 1,
	}

	// Extract deployments
	for _, dep := range svc.Deployments {
		d := model.Deployment{
			Status:       aws.ToString(dep.Status),
			RunningCount: int(dep.RunningCount),
			DesiredCount: int(dep.DesiredCount),
			PendingCount: int(dep.PendingCount),
			RolloutState: string(dep.RolloutState),
		}
		if dep.CreatedAt != nil {
			d.CreatedAt = *dep.CreatedAt
		}
		if dep.TaskDefinition != nil {
			td := aws.ToString(dep.TaskDefinition)
			// Extract family:revision from ARN
			if parts := strings.Split(td, "/"); len(parts) > 0 {
				d.TaskDef = parts[len(parts)-1]
			}
		}
		s.Deployments = append(s.Deployments, d)
	}
	if len(svc.Deployments) > 0 && svc.Deployments[0].CreatedAt != nil {
		s.DeployedAt = *svc.Deployments[0].CreatedAt
	}

	// Try to get the image from task definition
	if svc.TaskDefinition != nil {
		s.ImageDigest = extractDigestFromTaskDef(aws.ToString(svc.TaskDefinition))
	}

	// Classify the service
	s.Group, s.Workflow, s.WorkflowSvc, s.ImageBase, s.DeployTargets = classifyService(name)

	return s
}

func ecsTaskToModel(t ecstypes.Task, serviceName string) model.Task {
	task := model.Task{
		ServiceName: serviceName,
		Status:      aws.ToString(t.LastStatus),
	}

	// Extract task ID from ARN
	if t.TaskArn != nil {
		parts := strings.Split(aws.ToString(t.TaskArn), "/")
		if len(parts) > 0 {
			task.ID = parts[len(parts)-1]
		}
	}

	if t.StartedAt != nil {
		task.StartedAt = *t.StartedAt
	}

	// Surface the right container name on the model — see pickAppContainerIndex.
	if len(t.Containers) > 0 {
		names := containerNames(t.Containers)
		if i := pickAppContainerIndex(names); i >= 0 {
			task.ContainerName = names[i]
		}
	}

	// Get private IP from attachments
	for _, att := range t.Attachments {
		for _, detail := range att.Details {
			if aws.ToString(detail.Name) == "privateIPv4Address" {
				task.PrivateIP = aws.ToString(detail.Value)
			}
		}
	}

	return task
}

// classifyService determines the group, workflow, workflow input, image base,
// and all available deploy targets for a service.
// ECS service names have a "-service" suffix (e.g. "web-canary-service",
// "worker-birthday-notify-service") that we strip before matching.
func classifyService(name string) (group, workflow, workflowSvc, imageBase string, targets []model.DeployTarget) {
	// Strip the "-service" suffix that ECS service names carry
	svc := strings.TrimSuffix(name, "-service")

	switch svc {
	case "web-canary":
		return "web", config.WorkflowWeb22, "web-canary", config.ImageBaseWeb22, []model.DeployTarget{
			{Label: "web22", Workflow: config.WorkflowWeb22, WorkflowSvc: "web-canary", ImageBase: config.ImageBaseWeb22},
		}
	case "web-stable":
		return "web", config.WorkflowWeb, "web-stable", config.ImageBaseWeb, []model.DeployTarget{
			{Label: "web", Workflow: config.WorkflowWeb, WorkflowSvc: "web-stable", ImageBase: config.ImageBaseWeb},
		}
	case "web-unauthenticated":
		return "web", config.WorkflowWeb22, "web-unauthenticated", config.ImageBaseWeb22, []model.DeployTarget{
			{Label: "web22", Workflow: config.WorkflowWeb22, WorkflowSvc: "web-unauthenticated", ImageBase: config.ImageBaseWeb22},
		}
	case "web-shop":
		return "web", config.WorkflowWeb22, "web-shop", config.ImageBaseWeb22, []model.DeployTarget{
			{Label: "web22", Workflow: config.WorkflowWeb22, WorkflowSvc: "web-shop", ImageBase: config.ImageBaseWeb22},
		}
	case "proxy":
		return "proxy", "", "", "", nil
	}

	// Workers: strip "worker-" prefix for the workflow service input
	if strings.HasPrefix(svc, "worker-") {
		workerName := strings.TrimPrefix(svc, "worker-")
		return "worker", config.WorkflowWorker, workerName, config.ImageBaseWorker, []model.DeployTarget{
			{Label: "worker", Workflow: config.WorkflowWorker, WorkflowSvc: workerName, ImageBase: config.ImageBaseWorker},
			{Label: "worker22", Workflow: config.WorkflowWorker22, WorkflowSvc: workerName, ImageBase: config.ImageBaseWorker22},
		}
	}

	return "other", "", "", "", nil
}

// extractDigestFromTaskDef extracts the image digest from a task definition ARN.
// This is a placeholder — the actual digest comes from describing the task definition,
// which we'll populate during the describe phase.
func extractDigestFromTaskDef(taskDefArn string) string {
	// We'll resolve this when we have the full task def details
	return ""
}

// FetchServiceImages populates image digests from running task containers.
// It finds the right container via findAppContainer / pickAppContainerIndex
// and extracts the GHCR manifest digest from that container's Image field
// (the @sha256: reference from the task definition), which matches what
// GHCR reports.
func (c *Client) FetchServiceImages(ctx context.Context, services []model.Service) ([]model.Service, error) {
	for i, svc := range services {
		tasks, err := c.listTasksRaw(ctx, svc.Name, 1)
		if err != nil || len(tasks) == 0 {
			continue
		}

		container := findAppContainer(tasks[0].Containers)
		if container == nil {
			continue
		}

		// Prefer Container.Image which has the task definition's image reference
		// (e.g. "ghcr.io/dreamwidth/web@sha256:DIGEST") — this is the GHCR
		// manifest digest and will match GHCR package versions.
		// Container.ImageDigest is the platform-specific runtime digest and
		// won't match GHCR for multi-arch images.
		if container.Image != nil {
			img := aws.ToString(container.Image)
			if idx := strings.Index(img, "sha256:"); idx >= 0 {
				digest := img[idx+7:]
				if len(digest) > 12 {
					digest = digest[:12]
				}
				services[i].ImageDigest = digest
				continue
			}
		}
		// Fallback to ImageDigest if Image doesn't have a sha256 reference
		if container.ImageDigest != nil {
			digest := aws.ToString(container.ImageDigest)
			if strings.HasPrefix(digest, "sha256:") {
				digest = digest[7:]
			}
			if len(digest) > 12 {
				digest = digest[:12]
			}
			services[i].ImageDigest = digest
		}
	}
	return services, nil
}

// findAppContainer returns the application container from a task's
// container list, using pickAppContainerIndex's selection policy.
func findAppContainer(containers []ecstypes.Container) *ecstypes.Container {
	if i := pickAppContainerIndex(containerNames(containers)); i >= 0 {
		return &containers[i]
	}
	return nil
}

// containerNames extracts the Name field from an SDK container slice,
// with nil-safety for the AWS String pointers.
func containerNames(containers []ecstypes.Container) []string {
	names := make([]string, len(containers))
	for i, c := range containers {
		names[i] = aws.ToString(c.Name)
	}
	return names
}

// listTasksRaw returns raw ECS task descriptions (limited to maxTasks).
func (c *Client) listTasksRaw(ctx context.Context, serviceName string, maxTasks int) ([]ecstypes.Task, error) {
	listOut, err := c.ecs.ListTasks(ctx, &ecs.ListTasksInput{
		Cluster:       aws.String(c.cluster),
		ServiceName:   aws.String(serviceName),
		DesiredStatus: ecstypes.DesiredStatusRunning,
		MaxResults:    aws.Int32(int32(maxTasks)),
	})
	if err != nil {
		return nil, err
	}
	if len(listOut.TaskArns) == 0 {
		return nil, nil
	}

	descOut, err := c.ecs.DescribeTasks(ctx, &ecs.DescribeTasksInput{
		Cluster: aws.String(c.cluster),
		Tasks:   listOut.TaskArns,
	})
	if err != nil {
		return nil, err
	}
	return descOut.Tasks, nil
}

// Cluster returns the cluster name.
func (c *Client) Cluster() string {
	return c.cluster
}

// TaskCount is a helper to format "running/desired" task counts.
func TaskCount(running, desired int) string {
	return fmt.Sprintf("%d/%d", running, desired)
}

// RelativeTime formats a time as a human-readable relative string.
func RelativeTime(t time.Time) string {
	if t.IsZero() {
		return "-"
	}
	d := time.Since(t)
	switch {
	case d < time.Minute:
		return "just now"
	case d < time.Hour:
		m := int(d.Minutes())
		if m == 1 {
			return "1m ago"
		}
		return fmt.Sprintf("%dm ago", m)
	case d < 24*time.Hour:
		h := int(d.Hours())
		if h == 1 {
			return "1h ago"
		}
		return fmt.Sprintf("%dh ago", h)
	default:
		days := int(d.Hours() / 24)
		if days == 1 {
			return "1d ago"
		}
		return fmt.Sprintf("%dd ago", days)
	}
}
