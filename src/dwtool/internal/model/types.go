package model

import "time"

// ServiceGroup represents a logical grouping of services in the dashboard.
type ServiceGroup struct {
	Name     string
	Services []Service
}

// DeployTarget represents one way to deploy a service (e.g., web vs web22).
type DeployTarget struct {
	Label       string // display name: "web", "web22", "worker", "worker22"
	Workflow    string // GitHub Actions workflow filename
	WorkflowSvc string // the "service" input value for the workflow
	ImageBase   string // GHCR image base (e.g., ghcr.io/dreamwidth/web)
}

// Service represents an ECS service with its current state.
type Service struct {
	Name         string
	Status       string
	RunningCount int
	DesiredCount int
	PendingCount int
	Deploying    bool // true when a rollout is in progress (multiple deployments)
	ImageDigest  string // abbreviated sha256 digest
	DeployedAt   time.Time
	Group        string // "web", worker category, or "proxy"
	Workflow     string // GitHub Actions workflow filename (primary)
	WorkflowSvc  string // the "service" input value for the workflow
	ImageBase    string // GHCR image base (e.g., ghcr.io/dreamwidth/web)
	DeployTargets []DeployTarget // all available deploy sources (len > 1 means choice)
	Deployments   []Deployment  // active deployments (PRIMARY + any in-progress)
}

// Deployment represents an ECS deployment (part of a service's rollout history).
type Deployment struct {
	Status       string // PRIMARY, ACTIVE
	RunningCount int
	DesiredCount int
	PendingCount int
	RolloutState string // COMPLETED, IN_PROGRESS, FAILED
	CreatedAt    time.Time
	TaskDef      string // short task definition identifier (family:revision)
}

// Task represents a running ECS task.
type Task struct {
	ID            string
	Status        string
	StartedAt     time.Time
	ContainerName string
	PrivateIP     string
	ServiceName   string
}

// Image represents a container image version from GHCR.
type Image struct {
	Digest    string
	Tags      []string
	CreatedAt time.Time
	CommitMsg string // first line of git commit message, if resolvable from tags
}

// LogEvent represents a single CloudWatch log event.
type LogEvent struct {
	Timestamp time.Time
	Stream    string // abbreviated log stream name
	Message   string
}

// DeployRequest represents a request to deploy an image to a service.
type DeployRequest struct {
	Service  Service
	Image    Image
	Workflow string
	DryRun   bool
}
