package proc

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// Status represents the current state of the Starman server.
type Status struct {
	Running   bool
	PID       int
	Port      int
	Host      string
	Workers   int
	StartedAt time.Time
}

func pidFile(ljHome string) string {
	return filepath.Join(ljHome, "logs", "starman.pid")
}

// ReadStatus reads the Starman PID file and checks whether the process is alive.
func ReadStatus(ljHome string) Status {
	s := Status{
		Port:    8080,
		Host:    "0.0.0.0",
		Workers: 3,
	}

	data, err := os.ReadFile(pidFile(ljHome))
	if err != nil {
		return s
	}

	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil || pid <= 0 {
		return s
	}

	s.PID = pid

	// Check if process is running
	if err := syscall.Kill(pid, 0); err != nil {
		return s
	}

	s.Running = true

	// Use PID file mtime as approximate start time
	if fi, err := os.Stat(pidFile(ljHome)); err == nil {
		s.StartedAt = fi.ModTime()
	}

	return s
}

// Stop sends SIGTERM to the running Starman process and waits for it to exit.
func Stop(ljHome string) error {
	s := ReadStatus(ljHome)
	if !s.Running {
		return nil
	}

	proc, err := os.FindProcess(s.PID)
	if err != nil {
		return fmt.Errorf("find process %d: %w", s.PID, err)
	}

	if err := proc.Signal(syscall.SIGTERM); err != nil {
		return fmt.Errorf("signal process %d: %w", s.PID, err)
	}

	// Wait up to 5 seconds for graceful exit
	for i := 0; i < 50; i++ {
		time.Sleep(100 * time.Millisecond)
		if err := syscall.Kill(s.PID, 0); err != nil {
			return nil
		}
	}

	// Force kill
	_ = proc.Signal(syscall.SIGKILL)
	time.Sleep(200 * time.Millisecond)
	return nil
}

// Start launches Starman in daemon mode with logging enabled.
func Start(ljHome string) error {
	logDir := filepath.Join(ljHome, "logs")
	if err := os.MkdirAll(logDir, 0755); err != nil {
		return fmt.Errorf("create log dir: %w", err)
	}

	cmd := exec.Command("perl", filepath.Join(ljHome, "bin", "starman"),
		"--port", "8080",
		"--log", logDir,
		"--daemonize",
	)
	cmd.Dir = ljHome
	cmd.Env = append(os.Environ(), "LJHOME="+ljHome)

	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("start starman: %w\n%s", err, string(out))
	}

	return nil
}

// Restart stops the running Starman and starts a fresh instance.
func Restart(ljHome string) error {
	if err := Stop(ljHome); err != nil {
		return fmt.Errorf("stop: %w", err)
	}
	if err := Start(ljHome); err != nil {
		return fmt.Errorf("start: %w", err)
	}
	return nil
}
