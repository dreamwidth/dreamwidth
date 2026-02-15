package ui

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	dwaws "dreamwidth.org/dwtool/internal/aws"
	"dreamwidth.org/dwtool/internal/config"
	"dreamwidth.org/dwtool/internal/github"
	"dreamwidth.org/dwtool/internal/model"
)

// view represents which screen is currently active.
type view int

const (
	viewDashboard view = iota
	viewDetail
	viewDeploy
	viewLogs
	viewTraffic
)

// App is the root Bubble Tea model.
type App struct {
	// Config
	cfg     config.Config
	workers *config.WorkersConfig
	client  *dwaws.Client

	// State
	services     []model.Service
	rows         []dashboardRow
	cursor       int
	scrollOffset int // visual line offset for scrolling
	view         view
	err          error
	loading      bool
	spinner      spinner.Model
	message      string // status bar message
	filter       string
	filterActive bool // true when typing in filter bar
	showHelp     bool // true when help overlay is visible
	width        int
	height       int

	// Detail state
	detail detailState

	// Deploy state
	deploy deployState

	// Logs state
	logs logsState

	// Traffic state
	traffic trafficState
}

// servicesDescribedMsg is sent when service descriptions have been fetched (phase 1).
type servicesDescribedMsg struct {
	services []model.Service
	err      error
}

// servicesImagesMsg is sent when image digests have been fetched (phase 2).
type servicesImagesMsg struct {
	services []model.Service
	err      error
}

// tasksMsg is sent when tasks for a service have been fetched.
type tasksMsg struct {
	tasks []model.Task
	err   error
}

// detailRefreshMsg is sent when both service description and tasks have been refreshed.
type detailRefreshMsg struct {
	service *model.Service // nil if describe failed
	tasks   []model.Task
	err     error
}

// shellResolvedMsg carries the resolved task/container info for shell exec.
type shellResolvedMsg struct {
	cluster       string
	taskID        string
	containerName string
	err           error
}

// shellDoneMsg is sent when an ECS exec shell session ends.
type shellDoneMsg struct{ err error }

// imagesMsg is sent when GHCR images have been fetched.
type imagesMsg struct {
	images []model.Image
	err    error
}

// deployTriggeredMsg is sent after the workflow trigger completes.
type deployTriggeredMsg struct{ err error }

// workflowRunFoundMsg is sent when we find the triggered run's ID.
type workflowRunFoundMsg struct {
	runID int
	err   error
}

// workflowPollMsg is sent with the latest run status.
type workflowPollMsg struct {
	status     string
	conclusion string
	err        error
}

// pollTickMsg triggers the next poll cycle.
type pollTickMsg struct{}

// logsMsg is sent when initial log events have been fetched.
type logsMsg struct {
	events      []model.LogEvent
	lastEventMs int64
	err         error
}

// logsTailMsg is sent when new log events arrive from tailing.
type logsTailMsg struct {
	events      []model.LogEvent
	lastEventMs int64
	err         error
}

// logsTailTickMsg triggers the next tail poll.
type logsTailTickMsg struct{}

// trafficRuleFetchedMsg is sent when the ALB traffic rule has been fetched.
type trafficRuleFetchedMsg struct {
	rule model.TrafficRule
	err  error
}

// trafficRuleUpdatedMsg is sent when traffic weights have been applied.
type trafficRuleUpdatedMsg struct {
	err error
}

// refreshTickMsg triggers a periodic dashboard refresh.
type refreshTickMsg struct{}

// NewApp creates a new App model.
func NewApp(cfg config.Config, workers *config.WorkersConfig, client *dwaws.Client) App {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(colorCyan)

	// Build skeleton services from config so the UI populates immediately
	skeleton := skeletonServices(workers)
	rows := buildRows(skeleton, workers)

	a := App{
		cfg:      cfg,
		workers:  workers,
		client:   client,
		spinner:  s,
		loading:  true,
		view:     viewDashboard,
		services: skeleton,
		rows:     rows,
	}
	// Position cursor on first service row
	a.advanceCursorToService(1)
	return a
}

// skeletonServices builds placeholder services from config so the dashboard
// can render immediately while real data loads from AWS.
func skeletonServices(workers *config.WorkersConfig) []model.Service {
	var services []model.Service

	// Web services
	for _, ws := range config.WebServices() {
		name := ws.Name + "-service"
		services = append(services, model.Service{
			Name:      name,
			Group:     "web",
			Workflow:  ws.Workflow,
			WorkflowSvc: ws.WorkflowSvc,
			ImageBase: ws.ImageBase,
		})
	}

	// Proxy
	services = append(services, model.Service{
		Name:  "proxy-service",
		Group: "proxy",
	})

	// Workers from workers.json
	if workers != nil {
		for name := range workers.Workers {
			svcName := "worker-" + name + "-service"
			services = append(services, model.Service{
				Name:      svcName,
				Group:     "worker",
				Workflow:  config.WorkflowWorker,
				WorkflowSvc: name,
				ImageBase: config.ImageBaseWorker,
			})
		}
	}

	return services
}

func (a App) Init() tea.Cmd {
	return tea.Batch(a.spinner.Tick, a.fetchServiceDescriptions(), refreshTick())
}

func (a App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {

	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
		a.ensureCursorVisible()
		return a, nil

	case tea.KeyMsg:
		// Help overlay intercepts all keys
		if a.showHelp {
			if key.Matches(msg, keys.Help) || key.Matches(msg, keys.Escape) || key.Matches(msg, keys.Quit) {
				a.showHelp = false
			}
			return a, nil
		}

		// ? toggles help from any view
		if key.Matches(msg, keys.Help) {
			a.showHelp = true
			return a, nil
		}

		switch a.view {
		case viewDashboard:
			return a.handleDashboardKey(msg)
		case viewDetail:
			return a.handleDetailKey(msg)
		case viewDeploy:
			return a.handleDeployKey(msg)
		case viewLogs:
			return a.handleLogsKey(msg)
		case viewTraffic:
			return a.handleTrafficKey(msg)
		default:
			return a.handleDashboardKey(msg)
		}

	case servicesDescribedMsg:
		if msg.err != nil {
			a.err = msg.err
			a.message = fmt.Sprintf("Error: %v", msg.err)
			a.loading = false
			return a, nil
		}
		// Carry forward existing image digests so the UI doesn't blank them
		// while phase 2 re-fetches in the background.
		existing := make(map[string]string, len(a.services))
		for _, svc := range a.services {
			if svc.ImageDigest != "" {
				existing[svc.Name] = svc.ImageDigest
			}
		}
		for i := range msg.services {
			if msg.services[i].ImageDigest == "" {
				msg.services[i].ImageDigest = existing[msg.services[i].Name]
			}
		}
		a.updateServices(msg.services)
		// Phase 2: fetch fresh image digests in the background
		return a, a.fetchServiceImages(a.services)

	case servicesImagesMsg:
		a.loading = false
		if msg.err != nil {
			a.message = fmt.Sprintf("Error loading images: %v", msg.err)
		}
		if msg.services != nil {
			a.updateServices(msg.services)
		}
		return a, nil

	case trafficRuleFetchedMsg:
		if a.view != viewTraffic {
			return a, nil
		}
		a.traffic.loading = false
		if msg.err != nil {
			a.traffic.err = msg.err
			return a, nil
		}
		a.traffic.rule = msg.rule
		// Snapshot original weights for diff display
		a.traffic.originalWeights = make([]int, len(msg.rule.Targets))
		for i, t := range msg.rule.Targets {
			a.traffic.originalWeights[i] = t.Weight
		}
		return a, nil

	case trafficRuleUpdatedMsg:
		if a.view != viewTraffic {
			return a, nil
		}
		if msg.err != nil {
			a.traffic.err = msg.err
			a.traffic.step = trafficEditing
			return a, nil
		}
		return a.exitTraffic("Traffic weights updated")

	case refreshTickMsg:
		// Auto-refresh: only fetch if on dashboard, always re-arm the tick
		if a.view == viewDashboard && !a.loading {
			a.loading = true
			return a, tea.Batch(a.spinner.Tick, a.fetchServiceDescriptions(), refreshTick())
		}
		return a, refreshTick()

	case tasksMsg:
		a.detail.loading = false
		if msg.err != nil {
			a.detail.err = msg.err
			return a, nil
		}
		a.detail.tasks = msg.tasks
		a.detail.taskCursor = 0
		return a, nil

	case detailRefreshMsg:
		a.detail.loading = false
		if msg.err != nil {
			a.detail.err = msg.err
			return a, nil
		}
		if msg.service != nil {
			a.detail.service = *msg.service
		}
		a.detail.tasks = msg.tasks
		if a.detail.taskCursor >= len(a.detail.tasks) {
			a.detail.taskCursor = max(0, len(a.detail.tasks)-1)
		}
		return a, nil

	case logsMsg:
		a.logs.loading = false
		if msg.err != nil {
			a.logs.err = msg.err
			return a, nil
		}
		a.logs.events = msg.events
		a.logs.lastEventMs = msg.lastEventMs
		// Start in follow mode: scroll to bottom
		if a.logs.follow {
			maxScroll := len(a.logs.events) - visibleLogLines(a.height)
			if maxScroll < 0 {
				maxScroll = 0
			}
			a.logs.scrollOffset = maxScroll
		}
		// Start tailing
		if a.logs.follow {
			return a, logsTailTick()
		}
		return a, nil

	case logsTailTickMsg:
		if a.view != viewLogs || !a.logs.follow {
			return a, nil
		}
		return a, a.fetchLogsTail(a.logs.logGroup, a.logs.lastEventMs)

	case logsTailMsg:
		if a.view != viewLogs {
			return a, nil
		}
		if msg.err != nil {
			// Don't show transient tail errors, just keep tailing
			if a.logs.follow {
				return a, logsTailTick()
			}
			return a, nil
		}
		if len(msg.events) > 0 {
			a.logs.events = append(a.logs.events, msg.events...)
			a.logs.lastEventMs = msg.lastEventMs
			// If following, scroll to bottom
			if a.logs.follow {
				maxScroll := len(a.logs.events) - visibleLogLines(a.height)
				if maxScroll < 0 {
					maxScroll = 0
				}
				a.logs.scrollOffset = maxScroll
			}
		}
		if a.logs.follow {
			return a, logsTailTick()
		}
		return a, nil

	case shellResolvedMsg:
		if msg.err != nil {
			a.message = fmt.Sprintf("Shell error: %v", msg.err)
			return a, nil
		}
		// Launch the interactive shell, suspending the TUI
		c := exec.Command("aws", "ecs", "execute-command",
			"--cluster", msg.cluster,
			"--task", msg.taskID,
			"--container", msg.containerName,
			"--interactive",
			"--command", "/bin/bash",
		)
		return a, tea.ExecProcess(c, func(err error) tea.Msg {
			return shellDoneMsg{err: err}
		})

	case shellDoneMsg:
		if msg.err != nil {
			a.message = fmt.Sprintf("Shell exited: %v", msg.err)
		} else {
			a.message = "Shell session ended"
		}
		return a, nil

	// Deploy flow messages
	case imagesMsg:
		a.deploy.loading = false
		if msg.err != nil {
			a.deploy.err = msg.err
			return a, nil
		}
		a.deploy.images = msg.images
		a.deploy.imageCursor = 0
		return a, nil

	case deployTriggeredMsg:
		if msg.err != nil {
			a.deploy.err = msg.err
			return a, nil
		}
		// Workflow triggered; wait 2s then look for the run
		return a, tea.Tick(2*time.Second, func(t time.Time) tea.Msg {
			return pollTickMsg{}
		})

	case workflowRunFoundMsg:
		if msg.err != nil {
			a.deploy.err = msg.err
			return a, nil
		}
		if msg.runID == 0 {
			// Not found yet, retry after 3s
			return a, tea.Tick(3*time.Second, func(t time.Time) tea.Msg {
				return pollTickMsg{}
			})
		}
		a.deploy.runID = msg.runID
		// Now poll for status
		return a, a.pollRun(a.cfg.Repo, msg.runID)

	case workflowPollMsg:
		if msg.err != nil {
			a.deploy.err = msg.err
			return a, nil
		}
		a.deploy.runStatus = msg.status
		a.deploy.conclusion = msg.conclusion
		if msg.status == "completed" {
			// Set next hint for web deploy order
			if !a.deploy.allWorkers {
				a.deploy.nextHint = nextWebService(a.deploy.service.WorkflowSvc)
			}
			return a, nil
		}
		// Still running, poll again after 5s
		return a, tea.Tick(5*time.Second, func(t time.Time) tea.Msg {
			return pollTickMsg{}
		})

	case pollTickMsg:
		if a.view != viewDeploy || a.deploy.step != stepProgress {
			return a, nil
		}
		target := a.deploy.selectedTarget()
		if a.deploy.runID == 0 {
			// Still looking for the run
			return a, a.findRun(a.cfg.Repo, target.Workflow, a.deploy.triggered)
		}
		// Poll the known run
		return a, a.pollRun(a.cfg.Repo, a.deploy.runID)

	case spinner.TickMsg:
		if a.loading {
			var cmd tea.Cmd
			a.spinner, cmd = a.spinner.Update(msg)
			return a, cmd
		}
		return a, nil
	}

	return a, nil
}

// viewportHeight returns the number of visual lines available for scrollable content.
// Layout: title (1) + header (1) + separator (1) + [viewport] + footer (1) = 4 fixed lines.
func (a App) viewportHeight() int {
	h := a.height - 4
	if h < 1 {
		return 1
	}
	return h
}

func (a App) View() string {
	if a.height == 0 {
		return ""
	}

	if a.showHelp {
		return a.viewHelp()
	}

	switch a.view {
	case viewDetail:
		return a.viewDetail()
	case viewDeploy:
		return a.viewDeploy()
	case viewLogs:
		return a.viewLogs()
	case viewTraffic:
		return a.viewTrafficScreen()
	default:
		return a.viewDashboard()
	}
}

func (a App) viewDashboard() string {
	var b strings.Builder

	// Title bar (1 line)
	title := titleStyle.Render("dwtool")
	info := titleInfoStyle.Render(fmt.Sprintf(" - %s (%s)", a.cfg.Cluster, a.cfg.Region))
	rightHelp := titleInfoStyle.Render("r:refresh  ?:help  q:quit")

	titleLine := title + info
	padding := a.width - lipgloss.Width(titleLine) - lipgloss.Width(rightHelp)
	if padding < 1 {
		padding = 1
	}
	b.WriteString(titleLine + strings.Repeat(" ", padding) + rightHelp)
	b.WriteString("\n")

	// Column header (1 line)
	b.WriteString(renderColumnHeader(a.width))
	b.WriteString("\n")

	// Separator (1 line)
	b.WriteString(renderSeparator(a.width))
	b.WriteString("\n")

	vpHeight := a.viewportHeight()

	if a.err != nil && len(a.services) == 0 {
		b.WriteString(fmt.Sprintf("\n %s\n", errorStyle.Render(fmt.Sprintf("Error: %v", a.err))))
	} else {
		// Pre-render all rows to visual lines
		lines := preRenderLines(a.rows, a.cursor, a.width)
		// Render visible slice
		content := renderVisibleLines(lines, a.scrollOffset, vpHeight)
		b.WriteString(content)
	}

	// Pad to push footer to last line
	currentLines := strings.Count(b.String(), "\n")
	target := a.height - 1
	for i := currentLines; i < target; i++ {
		b.WriteString("\n")
	}

	// Footer (1 line)
	b.WriteString(a.renderFooter())

	return b.String()
}

func (a App) viewDetail() string {
	var b strings.Builder

	// Title bar
	title := titleStyle.Render("dwtool")
	info := titleInfoStyle.Render(fmt.Sprintf(" - %s (%s)", a.cfg.Cluster, a.cfg.Region))
	rightHelp := titleInfoStyle.Render("esc:back  r:refresh  q:quit")

	titleLine := title + info
	padding := a.width - lipgloss.Width(titleLine) - lipgloss.Width(rightHelp)
	if padding < 1 {
		padding = 1
	}
	b.WriteString(titleLine + strings.Repeat(" ", padding) + rightHelp)
	b.WriteString("\n")

	// Detail content
	b.WriteString(renderDetailView(a.detail, a.width, a.height))

	return b.String()
}

func (a App) viewDeploy() string {
	var b strings.Builder

	// Title bar
	title := titleStyle.Render("dwtool")
	info := titleInfoStyle.Render(fmt.Sprintf(" - %s (%s)", a.cfg.Cluster, a.cfg.Region))
	rightHelp := titleInfoStyle.Render("esc:back")

	titleLine := title + info
	padding := a.width - lipgloss.Width(titleLine) - lipgloss.Width(rightHelp)
	if padding < 1 {
		padding = 1
	}
	b.WriteString(titleLine + strings.Repeat(" ", padding) + rightHelp)
	b.WriteString("\n")

	// Separator
	b.WriteString(renderSeparator(a.width))
	b.WriteString("\n")

	// Deploy content
	b.WriteString(renderDeployView(a.deploy, a.width, a.height))

	return b.String()
}

func (a App) handleDashboardKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Filter input mode
	if a.filterActive {
		return a.handleFilterKey(msg)
	}

	switch {
	case key.Matches(msg, keys.Quit):
		return a, tea.Quit

	case key.Matches(msg, keys.Up):
		a.moveCursor(-1)
		a.ensureCursorVisible()
		return a, nil

	case key.Matches(msg, keys.Down):
		a.moveCursor(1)
		a.ensureCursorVisible()
		return a, nil

	case key.Matches(msg, keys.Enter):
		svc := a.selectedService()
		if svc == nil {
			return a, nil
		}
		a.detail = detailState{
			service: *svc,
			loading: true,
		}
		a.view = viewDetail
		return a, a.fetchTasks(svc.Name)

	case key.Matches(msg, keys.Refresh):
		a.loading = true
		a.message = ""
		return a, tea.Batch(a.spinner.Tick, a.fetchServiceDescriptions())

	case key.Matches(msg, keys.Shell):
		svc := a.selectedService()
		if svc == nil {
			return a, nil
		}
		a.message = fmt.Sprintf("Connecting to %s...", svc.Name)
		return a, a.resolveShell(svc.Name)

	case key.Matches(msg, keys.Deploy):
		svc := a.selectedService()
		if svc == nil {
			return a, nil
		}
		if svc.Workflow == "" {
			a.message = fmt.Sprintf("No deploy workflow for %s", svc.Name)
			return a, nil
		}
		return a.startDeploy(*svc, false)

	case key.Matches(msg, keys.DeployAll):
		// Deploy all workers — offer worker and worker22 targets
		allSvc := model.Service{
			Name:        "ALL WORKERS",
			Workflow:    config.WorkflowWorker,
			WorkflowSvc: "ALL WORKERS (*)",
			ImageBase:   config.ImageBaseWorker,
			DeployTargets: []model.DeployTarget{
				{Label: "worker", Workflow: config.WorkflowWorker, WorkflowSvc: "ALL WORKERS (*)", ImageBase: config.ImageBaseWorker},
				{Label: "worker22", Workflow: config.WorkflowWorker22, WorkflowSvc: "ALL WORKERS (*)", ImageBase: config.ImageBaseWorker22},
			},
		}
		return a.startDeploy(allSvc, true)

	case key.Matches(msg, keys.Logs):
		svc := a.selectedService()
		if svc == nil {
			return a, nil
		}
		return a.openLogs(*svc)

	case key.Matches(msg, keys.Traffic):
		svc := a.selectedService()
		if svc == nil {
			return a, nil
		}
		if svc.Group != "web" {
			a.message = "Traffic weights only available for web services"
			return a, nil
		}
		serviceKey := strings.TrimSuffix(svc.Name, "-service")
		a.traffic = trafficState{
			service:  *svc,
			prevView: viewDashboard,
			loading:  true,
		}
		a.view = viewTraffic
		return a, a.fetchTrafficRule(serviceKey)

	case key.Matches(msg, keys.Filter):
		a.filterActive = true
		return a, nil
	}

	return a, nil
}

func (a App) handleFilterKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyEnter:
		// Accept filter and exit filter mode
		a.filterActive = false
		return a, nil
	case tea.KeyEscape:
		// Clear filter and exit filter mode
		a.filterActive = false
		a.filter = ""
		a.applyFilter()
		return a, nil
	case tea.KeyBackspace:
		if len(a.filter) > 0 {
			a.filter = a.filter[:len(a.filter)-1]
			a.applyFilter()
		}
		return a, nil
	case tea.KeyRunes:
		a.filter += string(msg.Runes)
		a.applyFilter()
		return a, nil
	}
	return a, nil
}

// applyFilter rebuilds the dashboard rows using the current filter.
func (a *App) applyFilter() {
	filtered := filterServices(a.services, a.filter)
	a.rows = buildRows(filtered, a.workers)
	// Reset cursor to first service
	a.cursor = 0
	a.advanceCursorToService(1)
	a.scrollOffset = 0
}

func (a App) handleDetailKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, keys.Escape):
		a.view = viewDashboard
		a.message = ""
		return a, nil

	case key.Matches(msg, keys.Up):
		if a.detail.taskCursor > 0 {
			a.detail.taskCursor--
		}
		return a, nil

	case key.Matches(msg, keys.Down):
		if a.detail.taskCursor < len(a.detail.tasks)-1 {
			a.detail.taskCursor++
		}
		return a, nil

	case key.Matches(msg, keys.Shell):
		task := a.detail.selectedTask()
		if task == nil {
			return a, nil
		}
		containerName := task.ContainerName
		if containerName == "" {
			containerName = "web"
		}
		c := exec.Command("aws", "ecs", "execute-command",
			"--cluster", a.cfg.Cluster,
			"--task", task.ID,
			"--container", containerName,
			"--interactive",
			"--command", "/bin/bash",
		)
		return a, tea.ExecProcess(c, func(err error) tea.Msg {
			return shellDoneMsg{err: err}
		})

	case key.Matches(msg, keys.Deploy):
		svc := a.detail.service
		if svc.Workflow == "" {
			a.message = fmt.Sprintf("No deploy workflow for %s", svc.Name)
			return a, nil
		}
		return a.startDeploy(svc, false)

	case key.Matches(msg, keys.Logs):
		return a.openLogs(a.detail.service)

	case key.Matches(msg, keys.Traffic):
		svc := a.detail.service
		if svc.Group != "web" {
			a.message = "Traffic weights only available for web services"
			return a, nil
		}
		serviceKey := strings.TrimSuffix(svc.Name, "-service")
		a.traffic = trafficState{
			service:  svc,
			prevView: viewDetail,
			loading:  true,
		}
		a.view = viewTraffic
		return a, a.fetchTrafficRule(serviceKey)

	case key.Matches(msg, keys.Refresh):
		a.detail.loading = true
		a.detail.err = nil
		return a, a.fetchDetailRefresh(a.detail.service.Name)

	case key.Matches(msg, keys.Quit):
		return a, tea.Quit
	}

	return a, nil
}

func (a App) openLogs(svc model.Service) (tea.Model, tea.Cmd) {
	logGroup := dwaws.LogGroupForService(svc)
	if logGroup == "" {
		a.message = fmt.Sprintf("No log group for %s", svc.Name)
		return a, nil
	}
	a.logs = logsState{
		service:  svc,
		logGroup: logGroup,
		prevView: a.view,
		follow:   true,
		loading:  true,
	}
	a.view = viewLogs
	return a, a.fetchLogsInitial(logGroup)
}

func (a App) handleLogsKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Search mode: capture keystrokes for the search input
	if a.logs.searchActive {
		return a.handleLogsSearchKey(msg)
	}

	switch {
	case key.Matches(msg, keys.Escape):
		a.view = a.logs.prevView
		a.logs.follow = false
		return a, nil

	case key.Matches(msg, keys.Quit):
		return a, tea.Quit

	case key.Matches(msg, keys.Up):
		a.logs.follow = false
		if a.logs.scrollOffset > 0 {
			a.logs.scrollOffset--
		}
		return a, nil

	case key.Matches(msg, keys.Down):
		a.logs.follow = false
		maxScroll := len(a.logs.events) - visibleLogLines(a.height)
		if maxScroll < 0 {
			maxScroll = 0
		}
		if a.logs.scrollOffset < maxScroll {
			a.logs.scrollOffset++
		}
		return a, nil

	case msg.Type == tea.KeyRunes && string(msg.Runes) == "f":
		a.logs.follow = !a.logs.follow
		if a.logs.follow {
			// Scroll to bottom and start tailing
			maxScroll := len(a.logs.events) - visibleLogLines(a.height)
			if maxScroll < 0 {
				maxScroll = 0
			}
			a.logs.scrollOffset = maxScroll
			return a, logsTailTick()
		}
		return a, nil

	case msg.Type == tea.KeyRunes && string(msg.Runes) == "G":
		// Jump to end
		maxScroll := len(a.logs.events) - visibleLogLines(a.height)
		if maxScroll < 0 {
			maxScroll = 0
		}
		a.logs.scrollOffset = maxScroll
		return a, nil

	case msg.Type == tea.KeyRunes && string(msg.Runes) == "g":
		// Jump to top
		a.logs.follow = false
		a.logs.scrollOffset = 0
		return a, nil

	case key.Matches(msg, keys.Filter):
		// Enter search mode
		a.logs.searchActive = true
		a.logs.search = ""
		a.logs.matchLines = nil
		a.logs.matchCursor = 0
		return a, nil

	case msg.Type == tea.KeyRunes && string(msg.Runes) == "n":
		// Next match
		if len(a.logs.matchLines) > 0 {
			a.logs.matchCursor = (a.logs.matchCursor + 1) % len(a.logs.matchLines)
			a.logs.scrollToMatch(visibleLogLines(a.height))
		}
		return a, nil

	case msg.Type == tea.KeyRunes && string(msg.Runes) == "N":
		// Previous match
		if len(a.logs.matchLines) > 0 {
			a.logs.matchCursor--
			if a.logs.matchCursor < 0 {
				a.logs.matchCursor = len(a.logs.matchLines) - 1
			}
			a.logs.scrollToMatch(visibleLogLines(a.height))
		}
		return a, nil
	}

	return a, nil
}

func (a App) handleLogsSearchKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyEnter:
		a.logs.searchActive = false
		return a, nil
	case tea.KeyEscape:
		a.logs.searchActive = false
		a.logs.search = ""
		a.logs.matchLines = nil
		return a, nil
	case tea.KeyBackspace:
		if len(a.logs.search) > 0 {
			a.logs.search = a.logs.search[:len(a.logs.search)-1]
			a.logs.updateSearchMatches()
			if len(a.logs.matchLines) > 0 {
				a.logs.scrollToMatch(visibleLogLines(a.height))
			}
		}
		return a, nil
	case tea.KeyRunes:
		a.logs.search += string(msg.Runes)
		a.logs.updateSearchMatches()
		if len(a.logs.matchLines) > 0 {
			a.logs.scrollToMatch(visibleLogLines(a.height))
		}
		return a, nil
	}
	return a, nil
}

func (a App) viewLogs() string {
	var b strings.Builder

	// Title bar
	title := titleStyle.Render("dwtool")
	info := titleInfoStyle.Render(fmt.Sprintf(" - %s (%s)", a.cfg.Cluster, a.cfg.Region))
	rightHelp := titleInfoStyle.Render("esc:back  f:follow  q:quit")

	titleLine := title + info
	padding := a.width - lipgloss.Width(titleLine) - lipgloss.Width(rightHelp)
	if padding < 1 {
		padding = 1
	}
	b.WriteString(titleLine + strings.Repeat(" ", padding) + rightHelp)
	b.WriteString("\n")

	// Log content
	b.WriteString(renderLogsView(a.logs, a.width, a.height))

	// Pad to push footer to last line
	currentLines := strings.Count(b.String(), "\n")
	target := a.height - 1
	for i := currentLines; i < target; i++ {
		b.WriteString("\n")
	}

	// Footer
	b.WriteString(renderLogsFooter(a.logs, a.width))

	return b.String()
}

func (a App) viewHelp() string {
	var b strings.Builder

	// Title bar
	title := titleStyle.Render("dwtool")
	info := titleInfoStyle.Render(fmt.Sprintf(" - %s (%s)", a.cfg.Cluster, a.cfg.Region))
	rightHelp := titleInfoStyle.Render("?:close  esc:close")

	titleLine := title + info
	padding := a.width - lipgloss.Width(titleLine) - lipgloss.Width(rightHelp)
	if padding < 1 {
		padding = 1
	}
	b.WriteString(titleLine + strings.Repeat(" ", padding) + rightHelp)
	b.WriteString("\n")

	b.WriteString(renderHelpOverlay(a.width, a.height))

	return b.String()
}

func (a App) handleDeployKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch a.deploy.step {
	case stepSelectTarget:
		return a.handleTargetSelectKey(msg)
	case stepSelectImage:
		return a.handleImageSelectKey(msg)
	case stepConfirm:
		return a.handleConfirmKey(msg)
	case stepProgress:
		// Only Esc to go back
		if key.Matches(msg, keys.Escape) {
			if a.deploy.runStatus != "completed" {
				a.message = "Deploy continues on GitHub"
			}
			a.view = viewDashboard
			// Refresh services to pick up new deployment status
			a.loading = true
			return a, tea.Batch(a.spinner.Tick, a.fetchServiceDescriptions())
		}
		return a, nil
	}
	return a, nil
}

func (a App) handleTargetSelectKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, keys.Escape):
		a.view = viewDashboard
		a.message = ""
		return a, nil

	case key.Matches(msg, keys.Up):
		if a.deploy.targetCursor > 0 {
			a.deploy.targetCursor--
		}
		return a, nil

	case key.Matches(msg, keys.Down):
		if a.deploy.targetCursor < len(a.deploy.targets)-1 {
			a.deploy.targetCursor++
		}
		return a, nil

	case key.Matches(msg, keys.Enter):
		// Move to image selection, fetch images for the selected target
		a.deploy.step = stepSelectImage
		a.deploy.loading = true
		target := a.deploy.selectedTarget()
		return a, a.fetchImages(a.cfg.Repo, target.ImageBase)
	}

	return a, nil
}

func (a App) handleImageSelectKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, keys.Escape):
		// Go back to target selection if there were multiple targets
		if len(a.deploy.targets) > 1 {
			a.deploy.step = stepSelectTarget
			a.deploy.images = nil
			a.deploy.imageCursor = 0
			a.deploy.err = nil
			return a, nil
		}
		a.view = viewDashboard
		a.message = ""
		return a, nil

	case key.Matches(msg, keys.Up):
		if a.deploy.imageCursor > 0 {
			a.deploy.imageCursor--
		}
		return a, nil

	case key.Matches(msg, keys.Down):
		if a.deploy.imageCursor < len(a.deploy.images)-1 {
			a.deploy.imageCursor++
		}
		return a, nil

	case key.Matches(msg, keys.Enter):
		if len(a.deploy.images) == 0 || a.deploy.loading {
			return a, nil
		}
		a.deploy.step = stepConfirm
		return a, nil
	}

	return a, nil
}

func (a App) handleConfirmKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Only Shift+Y confirms
	if msg.String() == "Y" {
		a.deploy.step = stepProgress
		a.deploy.triggered = time.Now()

		// Use the selected target's workflow and service input
		target := a.deploy.selectedTarget()
		img := a.deploy.images[a.deploy.imageCursor]
		inputs := map[string]string{
			"service": target.WorkflowSvc,
			"tag":     img.Digest, // already has "sha256:" prefix
		}

		return a, a.triggerDeploy(a.cfg.Repo, target.Workflow, inputs)
	}

	// Any other key cancels
	a.deploy.step = stepSelectImage
	a.message = "Deploy cancelled"
	return a, nil
}

// startDeploy initiates the deploy flow for a service.
func (a App) startDeploy(svc model.Service, allWorkers bool) (tea.Model, tea.Cmd) {
	a.view = viewDeploy
	a.deploy = deployState{
		service:    svc,
		targets:    svc.DeployTargets,
		allWorkers: allWorkers,
	}
	a.message = ""

	// If multiple targets, show target picker first
	if len(svc.DeployTargets) > 1 {
		a.deploy.step = stepSelectTarget
		return a, nil
	}

	// Single target (or none) — go straight to image selection
	a.deploy.step = stepSelectImage
	a.deploy.loading = true
	imageBase := svc.ImageBase
	if len(svc.DeployTargets) == 1 {
		imageBase = svc.DeployTargets[0].ImageBase
	}
	return a, a.fetchImages(a.cfg.Repo, imageBase)
}

func (a *App) moveCursor(direction int) {
	if len(a.rows) == 0 {
		return
	}

	newPos := a.cursor + direction
	// Skip group headers
	for newPos >= 0 && newPos < len(a.rows) && a.rows[newPos].isGroup {
		newPos += direction
	}
	if newPos >= 0 && newPos < len(a.rows) && !a.rows[newPos].isGroup {
		a.cursor = newPos
	}
}

func (a *App) advanceCursorToService(direction int) {
	for a.cursor >= 0 && a.cursor < len(a.rows) && a.rows[a.cursor].isGroup {
		a.cursor += direction
	}
	if a.cursor < 0 || a.cursor >= len(a.rows) {
		a.cursor = 0
		for a.cursor < len(a.rows) && a.rows[a.cursor].isGroup {
			a.cursor++
		}
	}
}

// ensureCursorVisible adjusts scrollOffset so the cursor row is within the viewport.
func (a *App) ensureCursorVisible() {
	if len(a.rows) == 0 {
		a.scrollOffset = 0
		return
	}

	// Compute the cursor's visual line position by counting line heights
	// of all rows before it. Group headers after the first take 2 lines
	// (blank separator + header text); everything else takes 1 line.
	cursorVLine := 0
	for i := 0; i < a.cursor && i < len(a.rows); i++ {
		cursorVLine += rowVisualHeight(a.rows, i)
	}

	vpHeight := a.viewportHeight()

	// Scroll up if cursor is above viewport
	if cursorVLine < a.scrollOffset {
		a.scrollOffset = cursorVLine
	}
	// Scroll down if cursor is below viewport
	if cursorVLine >= a.scrollOffset+vpHeight {
		a.scrollOffset = cursorVLine - vpHeight + 1
	}
}

func (a App) selectedService() *model.Service {
	if a.cursor < 0 || a.cursor >= len(a.rows) {
		return nil
	}
	row := a.rows[a.cursor]
	if row.isGroup {
		return nil
	}
	return &row.service
}

// updateServices replaces the service list and rebuilds rows, preserving cursor position.
func (a *App) updateServices(services []model.Service) {
	var selectedName string
	if a.cursor >= 0 && a.cursor < len(a.rows) && !a.rows[a.cursor].isGroup {
		selectedName = a.rows[a.cursor].service.Name
	}
	a.services = services
	a.rows = buildRows(filterServices(a.services, a.filter), a.workers)
	restored := false
	if selectedName != "" {
		for i, row := range a.rows {
			if !row.isGroup && row.service.Name == selectedName {
				a.cursor = i
				restored = true
				break
			}
		}
	}
	if !restored {
		a.cursor = 0
		a.advanceCursorToService(1)
	}
	a.ensureCursorVisible()

	// Update the detail view's service if we're looking at one
	if a.view == viewDetail {
		for _, svc := range services {
			if svc.Name == a.detail.service.Name {
				a.detail.service = svc
				break
			}
		}
	}
}

// fetchServiceDescriptions fetches service names and descriptions from ECS (phase 1).
func (a App) fetchServiceDescriptions() tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()

		names, err := a.client.ListServices(ctx)
		if err != nil {
			return servicesDescribedMsg{err: err}
		}

		services, err := a.client.DescribeServices(ctx, names)
		if err != nil {
			return servicesDescribedMsg{err: err}
		}

		return servicesDescribedMsg{services: services}
	}
}

// fetchServiceImages fetches image digests from running tasks (phase 2).
func (a App) fetchServiceImages(services []model.Service) tea.Cmd {
	// Copy the slice so the background goroutine has its own copy
	svcsCopy := make([]model.Service, len(services))
	copy(svcsCopy, services)
	return func() tea.Msg {
		ctx := context.Background()
		updated, err := a.client.FetchServiceImages(ctx, svcsCopy)
		return servicesImagesMsg{services: updated, err: err}
	}
}

// fetchTasks fetches running tasks for a service.
func (a App) fetchTasks(serviceName string) tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()
		tasks, err := a.client.ListTasks(ctx, serviceName)
		return tasksMsg{tasks: tasks, err: err}
	}
}

// fetchDetailRefresh fetches both the service description and its tasks.
func (a App) fetchDetailRefresh(serviceName string) tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()

		// Describe the single service
		services, err := a.client.DescribeServices(ctx, []string{serviceName})
		if err != nil {
			return detailRefreshMsg{err: fmt.Errorf("describing service: %w", err)}
		}

		var svc *model.Service
		if len(services) > 0 {
			svc = &services[0]
		}

		// Fetch tasks
		tasks, err := a.client.ListTasks(ctx, serviceName)
		if err != nil {
			return detailRefreshMsg{service: svc, err: fmt.Errorf("listing tasks: %w", err)}
		}

		return detailRefreshMsg{service: svc, tasks: tasks}
	}
}

// refreshTick returns a command that sends a refreshTickMsg after 30 seconds.
func refreshTick() tea.Cmd {
	return tea.Tick(30*time.Second, func(time.Time) tea.Msg {
		return refreshTickMsg{}
	})
}

// resolveShell finds a running task and container for the service, then
// sends a shellResolvedMsg so Update can launch the interactive exec.
func (a App) resolveShell(serviceName string) tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()
		tasks, err := a.client.ListTasks(ctx, serviceName)
		if err != nil {
			return shellResolvedMsg{err: fmt.Errorf("listing tasks for %s: %w", serviceName, err)}
		}

		// Find a running task
		var task *model.Task
		for i := range tasks {
			if tasks[i].Status == "RUNNING" {
				task = &tasks[i]
				break
			}
		}
		if task == nil {
			if len(tasks) > 0 {
				task = &tasks[0]
			} else {
				return shellResolvedMsg{err: fmt.Errorf("no running tasks for %s", serviceName)}
			}
		}

		containerName := task.ContainerName
		if containerName == "" {
			containerName = "web" // fallback default
		}

		return shellResolvedMsg{
			cluster:       a.cfg.Cluster,
			taskID:        task.ID,
			containerName: containerName,
		}
	}
}

// fetchLogsInitial fetches the initial batch of log events.
func (a App) fetchLogsInitial(logGroup string) tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()
		events, err := a.client.FetchLogs(ctx, logGroup, 30*time.Minute, 500)
		if err != nil {
			return logsMsg{err: err}
		}
		var lastMs int64
		if len(events) > 0 {
			lastMs = events[len(events)-1].Timestamp.UnixMilli()
		}
		return logsMsg{events: events, lastEventMs: lastMs}
	}
}

// fetchLogsTail fetches new log events after the given timestamp.
func (a App) fetchLogsTail(logGroup string, afterMs int64) tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()
		// Add 1ms to avoid re-fetching the last event
		events, latestMs, err := a.client.FetchLogsSince(ctx, logGroup, afterMs+1)
		return logsTailMsg{events: events, lastEventMs: latestMs, err: err}
	}
}

// logsTailTick returns a command that sends a logsTailTickMsg after 5 seconds.
func logsTailTick() tea.Cmd {
	return tea.Tick(5*time.Second, func(time.Time) tea.Msg {
		return logsTailTickMsg{}
	})
}

// fetchImages fetches GHCR images for the deploy image picker,
// then resolves git commit messages from SHA-like tags.
func (a App) fetchImages(repo, imageBase string) tea.Cmd {
	return func() tea.Msg {
		images, err := github.FetchImages(repo, imageBase, 20)
		if err != nil {
			return imagesMsg{err: err}
		}
		github.ResolveCommitMessages(images)
		return imagesMsg{images: images}
	}
}

// triggerDeploy dispatches the GitHub Actions workflow.
func (a App) triggerDeploy(repo, workflow string, inputs map[string]string) tea.Cmd {
	return func() tea.Msg {
		err := github.TriggerWorkflow(repo, workflow, inputs)
		return deployTriggeredMsg{err: err}
	}
}

// findRun looks for the workflow run that was triggered.
func (a App) findRun(repo, workflow string, since time.Time) tea.Cmd {
	return func() tea.Msg {
		runID, err := github.FindWorkflowRun(repo, workflow, since)
		return workflowRunFoundMsg{runID: runID, err: err}
	}
}

// pollRun checks the status of a workflow run.
func (a App) pollRun(repo string, runID int) tea.Cmd {
	return func() tea.Msg {
		status, conclusion, err := github.GetWorkflowRun(repo, runID)
		return workflowPollMsg{status: status, conclusion: conclusion, err: err}
	}
}

func (a App) handleTrafficKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch a.traffic.step {
	case trafficEditing:
		return a.handleTrafficEditKey(msg)
	case trafficConfirm:
		return a.handleTrafficConfirmKey(msg)
	case trafficSaving:
		// No input during save
		return a, nil
	}
	return a, nil
}

func (a App) handleTrafficEditKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, keys.Escape):
		return a.exitTraffic("")

	case key.Matches(msg, keys.Quit):
		return a, tea.Quit

	case key.Matches(msg, keys.Up):
		if a.traffic.tgCursor > 0 {
			a.traffic.tgCursor--
		}
		return a, nil

	case key.Matches(msg, keys.Down):
		if a.traffic.tgCursor < len(a.traffic.rule.Targets)-1 {
			a.traffic.tgCursor++
		}
		return a, nil

	case msg.Type == tea.KeyLeft:
		if len(a.traffic.rule.Targets) > 0 {
			idx := a.traffic.tgCursor
			w := a.traffic.rule.Targets[idx].Weight - 10
			if w < 0 {
				w = 0
			}
			a.traffic.rule.Targets[idx].Weight = w
		}
		return a, nil

	case msg.Type == tea.KeyRight:
		if len(a.traffic.rule.Targets) > 0 {
			idx := a.traffic.tgCursor
			w := a.traffic.rule.Targets[idx].Weight + 10
			if w > 999 {
				w = 999
			}
			a.traffic.rule.Targets[idx].Weight = w
		}
		return a, nil

	case msg.Type == tea.KeyRunes && string(msg.Runes) == "1":
		applyPreset(&a.traffic.rule, 1)
		return a, nil

	case msg.Type == tea.KeyRunes && string(msg.Runes) == "2":
		applyPreset(&a.traffic.rule, 2)
		return a, nil

	case msg.Type == tea.KeyRunes && string(msg.Runes) == "3":
		applyPreset(&a.traffic.rule, 3)
		return a, nil

	case msg.Type == tea.KeyRunes && string(msg.Runes) == "4":
		applyPreset(&a.traffic.rule, 4)
		return a, nil

	case key.Matches(msg, keys.Enter):
		if len(a.traffic.rule.Targets) == 0 || a.traffic.loading {
			return a, nil
		}
		if !weightsChanged(a.traffic.rule, a.traffic.originalWeights) {
			return a.exitTraffic("No changes to apply")
		}
		a.traffic.step = trafficConfirm
		return a, nil
	}

	return a, nil
}

func (a App) handleTrafficConfirmKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Only Shift+Y confirms
	if msg.String() == "Y" {
		a.traffic.step = trafficSaving
		return a, a.updateTrafficWeights(a.traffic.rule)
	}

	// Any other key cancels back to editing
	a.traffic.step = trafficEditing
	return a, nil
}

// exitTraffic returns to wherever the user came from (dashboard or detail).
func (a App) exitTraffic(msg string) (tea.Model, tea.Cmd) {
	a.message = msg
	a.view = a.traffic.prevView
	return a, nil
}

func (a App) viewTrafficScreen() string {
	var b strings.Builder

	// Title bar
	title := titleStyle.Render("dwtool")
	info := titleInfoStyle.Render(fmt.Sprintf(" - %s (%s)", a.cfg.Cluster, a.cfg.Region))
	rightHelp := titleInfoStyle.Render("esc:cancel  q:quit")

	titleLine := title + info
	padding := a.width - lipgloss.Width(titleLine) - lipgloss.Width(rightHelp)
	if padding < 1 {
		padding = 1
	}
	b.WriteString(titleLine + strings.Repeat(" ", padding) + rightHelp)
	b.WriteString("\n")

	// Separator
	b.WriteString(renderSeparator(a.width))
	b.WriteString("\n")

	// Traffic content
	b.WriteString(renderTrafficView(a.traffic, a.width, a.height))

	return b.String()
}

// fetchTrafficRule fetches the ALB traffic rule for a web service.
func (a App) fetchTrafficRule(serviceKey string) tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()
		rule, err := a.client.FetchTrafficRule(ctx, serviceKey)
		return trafficRuleFetchedMsg{rule: rule, err: err}
	}
}

// updateTrafficWeights applies new traffic weights to the ALB.
func (a App) updateTrafficWeights(rule model.TrafficRule) tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()
		err := a.client.UpdateTrafficWeights(ctx, rule)
		return trafficRuleUpdatedMsg{err: err}
	}
}

func (a App) renderFooter() string {
	serviceCount := 0
	for _, row := range a.rows {
		if !row.isGroup {
			serviceCount++
		}
	}

	// Filter mode: show filter input in footer
	if a.filterActive {
		left := fmt.Sprintf(" /%s", a.filter)
		hint := dimStyle.Render("  enter:apply  esc:clear")
		right := fmt.Sprintf("%d services ", serviceCount)

		padding := a.width - lipgloss.Width(left) - lipgloss.Width(hint) - lipgloss.Width(right)
		if padding < 1 {
			padding = 1
		}
		return footerStyle.Render(left + hint + strings.Repeat(" ", padding) + right)
	}

	left := fmt.Sprintf(" %s:%s  %s:%s  %s:%s  %s:%s  %s:%s  %s:%s",
		footerKeyStyle.Render("enter"), "detail",
		footerKeyStyle.Render("d"), "deploy",
		footerKeyStyle.Render("D"), "deploy-all-workers",
		footerKeyStyle.Render("s"), "shell",
		footerKeyStyle.Render("l"), "logs",
		footerKeyStyle.Render("/"), "filter",
	)

	right := fmt.Sprintf("%d services ", serviceCount)
	if a.loading {
		right = a.spinner.View() + " " + right
	}

	// Show active filter indicator
	var msg string
	if a.filter != "" {
		msg = "  " + confirmStyle.Render(fmt.Sprintf("[filter: %s]", a.filter))
	} else if a.message != "" {
		msg = "  " + dimStyle.Render(a.message)
	}

	padding := a.width - lipgloss.Width(left) - lipgloss.Width(right) - lipgloss.Width(msg)
	if padding < 1 {
		padding = 1
	}

	return footerStyle.Render(left + msg + strings.Repeat(" ", padding) + right)
}
