package ui

import (
	"bufio"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/key"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"dreamwidth.org/devtool/internal/proc"
	"dreamwidth.org/devtool/internal/tailer"
)

type focus int

const (
	focusAccessLog focus = iota
	focusErrorLog
)

type lastRunResult struct {
	name   string
	passed bool
}

// cmdState tracks a running or completed command whose output replaces the log panes.
type cmdState struct {
	name    string
	lines   []string
	running bool
	err     error
	scroll  int
	follow  bool
	output  chan string // goroutine sends lines here; nil after command finishes
}

// drain reads all available lines from the output channel into lines.
func (cs *cmdState) drain() {
	for {
		select {
		case line := <-cs.output:
			cs.lines = append(cs.lines, line)
		default:
			return
		}
	}
}

// App is the root Bubble Tea model for devtool.
type App struct {
	ljHome string
	width  int
	height int

	// Starman
	status     proc.Status
	restarting bool

	// Log tailers (pointers — shared across value copies)
	accessTailer *tailer.Tailer
	errorTailer  *tailer.Tailer

	// Log pane state
	focus        focus
	accessScroll int
	errorScroll  int
	accessFollow bool
	errorFollow  bool

	// Command output (replaces log panes when non-nil)
	cmd *cmdState

	// Last command result
	lastRun *lastRunResult

	// Status message (shown in left pane)
	message string

	// Help overlay
	showHelp bool
}

// --- Message types ---

type statusTickMsg struct{}
type logTickMsg struct{}
type restartDoneMsg struct{ err error }
type commandDoneMsg struct {
	name string
	err  error
}

// --- Tick commands ---

func statusTick() tea.Cmd {
	return tea.Tick(5*time.Second, func(time.Time) tea.Msg {
		return statusTickMsg{}
	})
}

func logTick() tea.Cmd {
	return tea.Tick(time.Second, func(time.Time) tea.Msg {
		return logTickMsg{}
	})
}

// runCommand starts a command and streams its combined stdout/stderr to outputCh.
// Returns commandDoneMsg when the command exits.
func runCommand(name string, c *exec.Cmd, outputCh chan<- string) tea.Cmd {
	return func() tea.Msg {
		pr, pw := io.Pipe()
		c.Stdout = pw
		c.Stderr = pw

		if err := c.Start(); err != nil {
			return commandDoneMsg{name: name, err: err}
		}

		// Read output lines in a goroutine
		readerDone := make(chan struct{})
		go func() {
			scanner := bufio.NewScanner(pr)
			for scanner.Scan() {
				outputCh <- scanner.Text()
			}
			close(readerDone)
		}()

		// Wait for command to exit, then close pipe to stop reader
		cmdErr := c.Wait()
		pw.Close()
		<-readerDone

		return commandDoneMsg{name: name, err: cmdErr}
	}
}

// NewApp creates the initial application state.
func NewApp(ljHome string) App {
	logDir := filepath.Join(ljHome, "logs")
	return App{
		ljHome:       ljHome,
		accessTailer: tailer.New(filepath.Join(logDir, "access.log"), 1000),
		errorTailer:  tailer.New(filepath.Join(logDir, "error.log"), 1000),
		accessFollow: true,
		errorFollow:  true,
	}
}

func (a App) Init() tea.Cmd {
	return tea.Batch(
		// Immediate first checks
		func() tea.Msg { return statusTickMsg{} },
		func() tea.Msg { return logTickMsg{} },
	)
}

func (a App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
		return a, nil

	case tea.KeyMsg:
		if a.showHelp {
			a.showHelp = false
			return a, nil
		}
		return a.handleKey(msg)

	case statusTickMsg:
		a.status = proc.ReadStatus(a.ljHome)
		return a, statusTick()

	case logTickMsg:
		a.accessTailer.CheckForUpdates()
		a.errorTailer.CheckForUpdates()
		if a.accessFollow {
			a.accessScroll = len(a.accessTailer.Lines())
		}
		if a.errorFollow {
			a.errorScroll = len(a.errorTailer.Lines())
		}
		// Drain command output
		if a.cmd != nil && a.cmd.output != nil {
			a.cmd.drain()
			if a.cmd.follow {
				a.cmd.scroll = len(a.cmd.lines)
			}
		}
		return a, logTick()

	case restartDoneMsg:
		a.restarting = false
		a.status = proc.ReadStatus(a.ljHome)
		if msg.err != nil {
			a.message = fmt.Sprintf("Restart failed: %v", msg.err)
		} else {
			a.message = ""
		}
		return a, nil

	case commandDoneMsg:
		if a.cmd != nil {
			if a.cmd.output != nil {
				a.cmd.drain()
				a.cmd.output = nil
			}
			a.cmd.running = false
			a.cmd.err = msg.err
			if msg.err != nil && len(a.cmd.lines) == 0 {
				a.cmd.lines = append(a.cmd.lines, fmt.Sprintf("error: %v", msg.err))
			}
			a.lastRun = &lastRunResult{
				name:   msg.name,
				passed: msg.err == nil,
			}
		}
		return a, nil
	}

	return a, nil
}

func (a App) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Global keys
	switch {
	case key.Matches(msg, keys.Quit):
		return a, tea.Quit
	case key.Matches(msg, keys.Help):
		a.showHelp = true
		return a, nil
	}

	// Command output mode
	if a.cmd != nil {
		return a.handleCommandKey(msg)
	}

	// Normal mode
	return a.handleNormalKey(msg)
}

func (a App) handleCommandKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, keys.Escape) || msg.Type == tea.KeyEnter:
		if !a.cmd.running {
			a.cmd = nil
		}
		return a, nil

	case key.Matches(msg, keys.Follow):
		a.cmd.follow = !a.cmd.follow
		if a.cmd.follow {
			a.cmd.scroll = len(a.cmd.lines)
		}
		return a, nil

	case key.Matches(msg, keys.Up):
		a.scrollCommand(-1)
		return a, nil
	case key.Matches(msg, keys.Down):
		a.scrollCommand(1)
		return a, nil
	case key.Matches(msg, keys.PageUp):
		a.scrollCommand(-10)
		return a, nil
	case key.Matches(msg, keys.PageDown):
		a.scrollCommand(10)
		return a, nil

	case key.Matches(msg, keys.Restart):
		if a.restarting {
			return a, nil
		}
		a.restarting = true
		a.message = ""
		ljHome := a.ljHome
		return a, func() tea.Msg {
			return restartDoneMsg{err: proc.Restart(ljHome)}
		}
	}

	return a, nil
}

func (a App) handleNormalKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, keys.Tab):
		if a.focus == focusAccessLog {
			a.focus = focusErrorLog
		} else {
			a.focus = focusAccessLog
		}
		return a, nil

	case key.Matches(msg, keys.Follow):
		if a.focus == focusAccessLog {
			a.accessFollow = !a.accessFollow
			if a.accessFollow {
				a.accessScroll = len(a.accessTailer.Lines())
			}
		} else {
			a.errorFollow = !a.errorFollow
			if a.errorFollow {
				a.errorScroll = len(a.errorTailer.Lines())
			}
		}
		return a, nil

	case key.Matches(msg, keys.Up):
		a.scrollFocused(-1)
		return a, nil
	case key.Matches(msg, keys.Down):
		a.scrollFocused(1)
		return a, nil
	case key.Matches(msg, keys.PageUp):
		a.scrollFocused(-10)
		return a, nil
	case key.Matches(msg, keys.PageDown):
		a.scrollFocused(10)
		return a, nil

	case key.Matches(msg, keys.Restart):
		if a.restarting {
			return a, nil
		}
		a.restarting = true
		a.message = ""
		ljHome := a.ljHome
		return a, func() tea.Msg {
			return restartDoneMsg{err: proc.Restart(ljHome)}
		}

	case key.Matches(msg, keys.Tidy):
		return a.startCommand("tidy", "perl", "/opt/dreamwidth-extlib/bin/tidyall", "-a")

	case key.Matches(msg, keys.Compile):
		return a.startCommand("compile test", "perl", "t/00-compile.t")

	case key.Matches(msg, keys.Build):
		return a.startCommand("build static", filepath.Join(a.ljHome, "bin", "build-static.sh"))
	}

	return a, nil
}

func (a App) startCommand(name string, argv ...string) (tea.Model, tea.Cmd) {
	if a.cmd != nil {
		return a, nil
	}
	outputCh := make(chan string, 10000)
	a.cmd = &cmdState{
		name:    name,
		running: true,
		follow:  true,
		output:  outputCh,
	}
	c := exec.Command(argv[0], argv[1:]...)
	c.Dir = a.ljHome
	return a, runCommand(name, c, outputCh)
}

func (a *App) scrollCommand(delta int) {
	a.cmd.follow = false
	a.cmd.scroll += delta
	total := len(a.cmd.lines)
	a.cmd.scroll = clamp(a.cmd.scroll, 0, max(0, total-1))
}

func (a *App) scrollFocused(delta int) {
	if a.focus == focusAccessLog {
		a.accessFollow = false
		a.accessScroll += delta
		total := len(a.accessTailer.Lines())
		a.accessScroll = clamp(a.accessScroll, 0, max(0, total-1))
	} else {
		a.errorFollow = false
		a.errorScroll += delta
		total := len(a.errorTailer.Lines())
		a.errorScroll = clamp(a.errorScroll, 0, max(0, total-1))
	}
}

// --- View ---

func (a App) View() string {
	if a.width == 0 || a.height == 0 {
		return ""
	}
	if a.showHelp {
		return a.viewHelp()
	}

	var b strings.Builder

	// Title bar
	titleText := " devtool "
	titleBar := separatorStyle.Render("─") +
		titleStyle.Render(titleText) +
		separatorStyle.Render(strings.Repeat("─", max(0, a.width-lipgloss.Width(titleText)-1)))
	b.WriteString(titleBar + "\n")

	// Main content area
	contentHeight := max(1, a.height-2) // title + footer
	rightWidth := max(10, a.width-leftPaneWidth-1)

	leftLines := a.renderStatusPane(contentHeight)

	var rightLines []string
	if a.cmd != nil {
		rightLines = a.renderCommandPane(contentHeight, rightWidth)
	} else {
		rightLines = a.renderLogPanes(contentHeight, rightWidth)
	}

	sep := separatorStyle.Render("│")
	for i := 0; i < contentHeight; i++ {
		left := ""
		if i < len(leftLines) {
			left = leftLines[i]
		}
		right := ""
		if i < len(rightLines) {
			right = rightLines[i]
		}
		b.WriteString(left + sep + right + "\n")
	}

	// Footer
	b.WriteString(a.renderFooter())

	return b.String()
}

func (a App) renderFooter() string {
	if a.cmd != nil {
		if a.cmd.running {
			status := warnStyle.Render("Running " + a.cmd.name + "…")
			hints := footerKeyStyle.Render("↑/↓") + footerStyle.Render(":scroll") + "  " +
				footerKeyStyle.Render("f") + footerStyle.Render(":follow")
			return " " + status + "  " + hints
		}
		// Command finished
		var result string
		if a.cmd.err == nil {
			result = a.cmd.name + ": " + successStyle.Render("PASS")
		} else {
			result = a.cmd.name + ": " + errorStyle.Render("FAIL")
		}
		hints := footerKeyStyle.Render("esc") + footerStyle.Render(":close") + "  " +
			footerKeyStyle.Render("↑/↓") + footerStyle.Render(":scroll")
		return " " + result + "  " + hints
	}

	pairs := []struct{ key, desc string }{
		{"r", "restart starman"},
		{"t", "tidy"},
		{"c", "compile test"},
		{"b", "build static"},
		{"f", "follow"},
		{"tab", "focus"},
		{"?", "help"},
		{"q", "quit"},
	}

	parts := make([]string, len(pairs))
	for i, p := range pairs {
		parts[i] = footerKeyStyle.Render(p.key) + footerStyle.Render(":"+p.desc)
	}
	return " " + strings.Join(parts, "  ")
}

func (a App) viewHelp() string {
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(titleStyle.Render("  Keybindings") + "\n\n")

	helpItems := []struct{ key, desc string }{
		{"r", "Restart Starman server"},
		{"t", "Run tidyall (auto-format code)"},
		{"c", "Run compile test (t/00-compile.t)"},
		{"b", "Build static assets (CSS/JS)"},
		{"f", "Toggle follow mode on focused pane"},
		{"Tab", "Switch focus between log panes"},
		{"↑/k", "Scroll up in focused pane"},
		{"↓/j", "Scroll down in focused pane"},
		{"PgUp", "Page up in focused pane"},
		{"PgDn", "Page down in focused pane"},
		{"?", "Toggle this help overlay"},
		{"q", "Quit devtool"},
	}

	for _, item := range helpItems {
		keyStr := fmt.Sprintf("  %-8s", item.key)
		b.WriteString(footerKeyStyle.Render(keyStr) + "  " + item.desc + "\n")
	}

	b.WriteString("\n")
	b.WriteString(dimStyle.Render("  Press any key to close") + "\n")

	return b.String()
}
