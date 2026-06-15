//go:build linux

package acpi

import (
	"context"
	"log/slog"
	"syscall"
)

// ACPI handles ACPI events such as power button presses and system shutdown.
type ACPI struct {
	logger     *slog.Logger
	onShutdown func(context.Context)
}

// Config holds configuration for creating an ACPI instance.
type Config struct {
	Logger *slog.Logger
}

// New creates a new ACPI handler.
func New(cfg Config) *ACPI {
	return &ACPI{
		logger: cfg.Logger,
	}
}

// OnShutdown registers a callback to be invoked during shutdown.
// The callback should stop application services (HTTP server, network, etc).
func (a *ACPI) OnShutdown(fn func(context.Context)) {
	a.onShutdown = fn
}

// ListenPowerButton starts listening for ACPI power button events.
// When the power button is pressed, it signals via the returned channel.
// This function spawns a goroutine and returns immediately.
func (a *ACPI) ListenPowerButton(ctx context.Context) <-chan struct{} {
	ch := make(chan struct{}, 1)
	go a.listenPowerButton(ctx, ch)
	return ch
}

// Poweroff performs a graceful system shutdown.
// It calls the registered shutdown callback, syncs filesystems, and powers off.
func (a *ACPI) Poweroff(ctx context.Context) {
	a.logger.InfoContext(ctx, "initiating system poweroff")

	// Call the shutdown callback to stop services
	if a.onShutdown != nil {
		a.logger.InfoContext(ctx, "stopping services")
		a.onShutdown(ctx)
	}

	// Sync filesystems
	a.logger.InfoContext(ctx, "syncing filesystems")
	syscall.Sync()

	a.logger.InfoContext(ctx, "powering off")
	if err := syscall.Reboot(syscall.LINUX_REBOOT_CMD_POWER_OFF); err != nil {
		a.logger.ErrorContext(ctx, "reboot syscall failed",
			slog.Any("error", err),
		)
	}
}
