package main

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

type trayApp struct {
	o    options
	mu   sync.Mutex
	busy bool
}

// runTray runs the StatusNotifierItem tray until Quit. SetOnTapped is called
// before Run so the SNI item advertises ItemIsMenu=false, making a left click
// activate Refresh directly (right click still opens the menu).
func runTray(o options) {
	app := &trayApp{o: o}
	systray.SetOnTapped(func() { go app.refresh() })
	systray.Run(app.ready, func() {})
}

func (a *trayApp) ready() {
	systray.SetIcon(trayIcon(false))
	systray.SetTitle("ssh-config-gen")
	systray.SetTooltip("ssh-config-gen")

	refreshItem := systray.AddMenuItem("Refresh", "Regenerate the ssh config from KeePassXC")
	openItem := systray.AddMenuItem("Open config", "Open the generated config fragment")
	logItem := systray.AddMenuItem("Show log", "Open the last-run log")
	systray.AddSeparator()
	quitItem := systray.AddMenuItem("Quit", "Exit the tray")

	go func() {
		for {
			select {
			case <-refreshItem.ClickedCh:
				go a.refresh()
			case <-openItem.ClickedCh:
				go openPath(expand(a.o.output))
			case <-logItem.ClickedCh:
				go openPath(expand(a.o.logFile))
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
	err := generate(a.o)
	if err != nil {
		systray.SetIcon(trayIcon(true))
		systray.SetTooltip("ssh-config-gen: failed " + stamp + " (Show log)")
		appendLog(expand(a.o.logFile), fmt.Sprintf("[%s] failed: %v\n", stamp, err))
		return
	}
	systray.SetIcon(trayIcon(false))
	systray.SetTooltip("ssh-config-gen: updated " + stamp)
	appendLog(expand(a.o.logFile), fmt.Sprintf("[%s] updated\n", stamp))
}

func appendLog(path, line string) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer file.Close()
	_, _ = file.WriteString(line)
}

func openPath(path string) {
	_ = exec.Command("xdg-open", path).Start()
}
