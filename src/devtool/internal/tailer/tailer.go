package tailer

import (
	"bufio"
	"io"
	"os"
)

// Tailer reads new lines appended to a file since the last check.
// It handles file rotation (detected when the file shrinks).
type Tailer struct {
	path     string
	lastSize int64
	lines    []string
	maxLines int
}

// New creates a Tailer for the given file path, keeping at most maxLines in memory.
func New(path string, maxLines int) *Tailer {
	return &Tailer{
		path:     path,
		maxLines: maxLines,
	}
}

// CheckForUpdates stats the file and reads any new bytes appended since the
// last check. Returns true if new lines were added.
func (t *Tailer) CheckForUpdates() (bool, error) {
	fi, err := os.Stat(t.path)
	if err != nil {
		return false, nil // file doesn't exist yet
	}

	size := fi.Size()

	// File was rotated or truncated
	if size < t.lastSize {
		t.lastSize = 0
		t.lines = nil
	}

	// No new data
	if size == t.lastSize {
		return false, nil
	}

	f, err := os.Open(t.path)
	if err != nil {
		return false, err
	}
	defer f.Close()

	if _, err := f.Seek(t.lastSize, io.SeekStart); err != nil {
		return false, err
	}

	scanner := bufio.NewScanner(f)
	var newLines []string
	for scanner.Scan() {
		newLines = append(newLines, scanner.Text())
	}

	if len(newLines) == 0 {
		t.lastSize = size
		return false, nil
	}

	t.lines = append(t.lines, newLines...)

	// Trim to max lines
	if len(t.lines) > t.maxLines {
		t.lines = t.lines[len(t.lines)-t.maxLines:]
	}

	t.lastSize = size
	return true, nil
}

// Lines returns the buffered log lines.
func (t *Tailer) Lines() []string {
	return t.lines
}
