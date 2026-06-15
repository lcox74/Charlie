//go:build linux

package acpi

import (
	"context"
	"encoding/binary"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	evKey       = 0x01
	keyPower    = 116
	eventSize   = 24
	sysInputDir = "/sys/class/input"
	devInputDir = "/dev/input"
)

type inputEvent struct {
	TimeSec  int64
	TimeUsec int64
	Type     uint16
	Code     uint16
	Value    int32
}

// readDeviceName reads the device name from sysfs.
func readDeviceName(eventName string) string {
	path := filepath.Join(sysInputDir, eventName, "device", "name")

	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}

	return strings.TrimSpace(string(data))
}

// findPowerButtonDevice scans /sys/class/input/ to find the ACPI power button.
func (a *ACPI) findPowerButtonDevice(ctx context.Context) string {
	entries, err := os.ReadDir(sysInputDir)
	if err != nil {
		a.logger.WarnContext(ctx, "cannot read input directory",
			slog.String("path", sysInputDir),
			slog.Any("error", err),
		)
		return ""
	}

	for _, entry := range entries {
		if !strings.HasPrefix(entry.Name(), "event") {
			continue
		}

		if name := readDeviceName(entry.Name()); name == "Power Button" {
			return filepath.Join(devInputDir, entry.Name())
		}
	}
	return ""
}

// listenPowerButton monitors the ACPI power button and signals on press.
func (a *ACPI) listenPowerButton(ctx context.Context, ch chan<- struct{}) {
	devPath := a.findPowerButtonDevice(ctx)
	if devPath == "" {
		a.logger.WarnContext(ctx, "power button device not found, listener disabled")
		return
	}

	f, err := os.Open(devPath)
	if err != nil {
		a.logger.WarnContext(ctx, "cannot open power button device",
			slog.String("path", devPath),
			slog.Any("error", err),
		)
		return
	}
	defer f.Close()

	a.logger.InfoContext(ctx, "listening for power button",
		slog.String("device", devPath),
	)

	buf := make([]byte, eventSize)
	for {
		f.SetReadDeadline(time.Now().Add(1 * time.Second))

		n, err := f.Read(buf)
		if err != nil {
			if os.IsTimeout(err) {
				if ctx.Err() != nil {
					a.logger.InfoContext(ctx, "power button listener stopped")
					return
				}
				continue
			}

			a.logger.WarnContext(ctx, "power button read error",
				slog.Any("error", err),
			)

			return
		}
		if n != eventSize {
			continue
		}

		ev := parseInputEvent(buf)
		if ev.Type == evKey && ev.Code == keyPower && ev.Value == 1 {
			a.logger.InfoContext(ctx, "power button pressed")

			select {
			case ch <- struct{}{}:
			default:
				// Have a default for the event that the channel is blocked
			}

			return
		}
	}
}

func parseInputEvent(buf []byte) inputEvent {
	return inputEvent{
		TimeSec:  int64(binary.LittleEndian.Uint64(buf[0:8])),  //nolint:gosec // Linux input_event timeval
		TimeUsec: int64(binary.LittleEndian.Uint64(buf[8:16])), //nolint:gosec // Linux input_event timeval
		Type:     binary.LittleEndian.Uint16(buf[16:18]),
		Code:     binary.LittleEndian.Uint16(buf[18:20]),
		Value:    int32(binary.LittleEndian.Uint32(buf[20:24])), //nolint:gosec // Linux input_event value
	}
}
