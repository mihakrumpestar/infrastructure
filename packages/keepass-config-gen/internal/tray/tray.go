// Package tray runs a generic system tray whose refresh action is supplied by
// the caller.
package tray

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"fyne.io/systray"
)

// Config describes a tray application.
type Config struct {
	Title     string
	Refresh   func() error
	OpenPath  string
	OpenLabel string
	LogFile   string
}

type trayApp struct {
	config Config
	mu     sync.Mutex
	busy   bool
}

// Run runs the StatusNotifierItem tray until Quit. SetOnTapped is called before
// Run so the SNI item advertises ItemIsMenu=false, making a left click activate
// Refresh directly (right click still opens the menu).
func Run(config Config) {
	if config.OpenLabel == "" {
		config.OpenLabel = "Open config"
	}
	app := &trayApp{config: config}
	systray.SetOnTapped(func() { go app.refresh() })
	systray.Run(app.ready, func() {})
}

func (a *trayApp) ready() {
	systray.SetIcon(trayIcon(false))
	systray.SetTitle(a.config.Title)
	systray.SetTooltip(a.config.Title)

	refreshItem := systray.AddMenuItem("Refresh", "Regenerate from KeePassXC")
	openItem := systray.AddMenuItem(a.config.OpenLabel, "Open the generated config fragment")
	logItem := systray.AddMenuItem("Show log", "Open the last-run log")
	systray.AddSeparator()
	quitItem := systray.AddMenuItem("Quit", "Exit the tray")

	go func() {
		for {
			select {
			case <-refreshItem.ClickedCh:
				go a.refresh()
			case <-openItem.ClickedCh:
				go openPath(a.config.OpenPath)
			case <-logItem.ClickedCh:
				go openPath(a.config.LogFile)
			case <-quitItem.ClickedCh:
				systray.Quit()
				return
			}
		}
	}()
}

func (a *trayApp) refresh() {
	a.mu.Lock()
	if a.busy {
		a.mu.Unlock()
		return
	}
	a.busy = true
	a.mu.Unlock()
	defer func() {
		a.mu.Lock()
		a.busy = false
		a.mu.Unlock()
	}()

	stamp := time.Now().Format("2006-01-02 15:04:05")
	if err := a.config.Refresh(); err != nil {
		systray.SetIcon(trayIcon(true))
		systray.SetTooltip(fmt.Sprintf("%s: failed %s (Show log)", a.config.Title, stamp))
		appendLog(a.config.LogFile, fmt.Sprintf("[%s] %s: failed: %v\n", stamp, a.config.Title, err))
		return
	}
	systray.SetIcon(trayIcon(false))
	systray.SetTooltip(fmt.Sprintf("%s: updated %s", a.config.Title, stamp))
	appendLog(a.config.LogFile, fmt.Sprintf("[%s] %s: updated\n", stamp, a.config.Title))
}

// trayIcon renders a small keyhole icon at runtime (blue normally, red on the
// last failure), so there is no asset to ship or icon theme to depend on.
func trayIcon(failed bool) []byte {
	const size = 64
	img := image.NewRGBA(image.Rect(0, 0, size, size))
	background := color.RGBA{R: 0x1f, G: 0x6f, B: 0xeb, A: 0xff}
	if failed {
		background = color.RGBA{R: 0xd1, G: 0x24, B: 0x2f, A: 0xff}
	}
	foreground := color.RGBA{R: 0xff, G: 0xff, B: 0xff, A: 0xff}
	for y := range size {
		for x := range size {
			if dx, dy := x-32, y-32; dx*dx+dy*dy <= 30*30 {
				img.Set(x, y, background)
			}
			dx, dy := x-32, y-24
			inDisc := dx*dx+dy*dy <= 8*8
			inStem := x >= 29 && x <= 35 && y >= 28 && y <= 46
			if inDisc || inStem {
				img.Set(x, y, foreground)
			}
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return nil
	}
	return buf.Bytes()
}

func appendLog(path, line string) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer func() { _ = file.Close() }()
	// Tighten a log created by an older version with 0644.
	_ = file.Chmod(0o600)
	_, _ = file.WriteString(line)
}

func openPath(path string) {
	// Start alone leaves a zombie once xdg-open exits; reap it in the
	// background instead.
	go func() { _ = exec.Command("xdg-open", path).Run() }()
}
