package config

const (
	DefaultCluster   = "dreamwidth"
	DefaultRegion    = "us-east-1"
	DefaultRepo      = "dreamwidth/dreamwidth"
	DefaultSQSPrefix = "dw-prod-"

	ImageBaseWeb22    = "ghcr.io/dreamwidth/web22"
	ImageBaseWorker   = "ghcr.io/dreamwidth/worker"
	ImageBaseWorker22 = "ghcr.io/dreamwidth/worker22"

	WorkflowWeb22    = "web22-deploy.yml"
	WorkflowWorker   = "worker-deploy.yml"
	WorkflowWorker22 = "worker22-deploy.yml"

	ALBName = "dw-prod"
)

// Config holds runtime configuration for dwtool.
type Config struct {
	Cluster    string
	Region     string
	Repo       string
	WorkersDir string // path to config/workers.json (auto-detected or flag)
	SQSPrefix  string // prefix for SQS queue names (e.g. "dw-prod-")
}

// WebServices returns the web services in deployment order.
func WebServices() []struct {
	Name        string
	Workflow    string
	WorkflowSvc string
	ImageBase   string
} {
	return []struct {
		Name        string
		Workflow    string
		WorkflowSvc string
		ImageBase   string
	}{
		{"web-canary", WorkflowWeb22, "web-canary", ImageBaseWeb22},
		{"web-shop", WorkflowWeb22, "web-shop", ImageBaseWeb22},
		{"web-unauthenticated", WorkflowWeb22, "web-unauthenticated", ImageBaseWeb22},
		{"web-stable", WorkflowWeb22, "web-stable", ImageBaseWeb22},
	}
}

// WebDeployOrder maps a web service to its position in the deployment chain.
// After deploying the service at index N, suggest index N+1.
var WebDeployOrder = []string{
	"web-canary",
	"web-shop",
	"web-unauthenticated",
	"web-stable",
}
