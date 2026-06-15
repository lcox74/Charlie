//go:build linux

package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/lcox74/bingo/src/internal/acpi"
	"github.com/lcox74/bingo/src/internal/app"
	"github.com/lcox74/bingo/src/internal/boot"
	"github.com/lcox74/bingo/src/internal/network"
)

const (
	Hostname  = "bingo"
	DHCPIface = "eth0"
)

var Interfaces = []string{"lo", "eth0"}

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stderr, nil))
	slog.SetDefault(logger)

	defer func() {
		if r := recover(); r != nil {
			logger.Error("fatal", slog.Any("error", r))
			os.Exit(1)
		}
	}()

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()

	bootPhase := boot.New(boot.Config{
		Logger:           logger.WithGroup("boot"),
		FallbackHostname: Hostname,
	})
	if err := bootPhase.Run(ctx); err != nil {
		logger.ErrorContext(ctx, "boot failed", slog.Any("error", err))
		panic(err)
	}

	networkManager := network.New(network.Config{
		Logger:     logger.WithGroup("network"),
		Interfaces: Interfaces,
		DHCPIface:  DHCPIface,
	})
	if err := networkManager.Start(ctx); err != nil {
		logger.ErrorContext(ctx, "network failed", slog.Any("error", err))
		panic(err)
	}

	err := bootPhase.UpdateHostname(ctx, networkManager.Hostname(Hostname))
	if err != nil {
		logger.WarnContext(ctx, "hostname update failed", slog.Any("error", err))
	}

	application := app.New(app.Config{
		Logger: logger.WithGroup("app"),
	})

	acpiHandler := acpi.New(acpi.Config{
		Logger: logger.WithGroup("acpi"),
	})

	powerCh := acpiHandler.ListenPowerButton(ctx)
	shutdownDone := handleShutdown(ctx, cancel, logger, application, networkManager, acpiHandler, powerCh)

	application.Run()
	<-shutdownDone
}

func handleShutdown(
	ctx context.Context,
	cancel context.CancelFunc,
	logger *slog.Logger,
	application *app.App,
	networkManager *network.Network,
	acpiHandler *acpi.ACPI,
	powerCh <-chan struct{},
) <-chan struct{} {
	done := make(chan struct{})

	// Create shutdown context before goroutine; use WithoutCancel so it
	// remains valid after the parent signal context is cancelled.
	shutdownCtx, shutdownCancel := context.WithTimeout(context.WithoutCancel(ctx), 30*time.Second)

	go func() {
		defer close(done)
		defer shutdownCancel()

		select {
		case <-ctx.Done():
			logger.InfoContext(ctx, "shutdown signal received")
		case <-powerCh:
			cancel()
			defer acpiHandler.Poweroff(shutdownCtx)
		}

		application.Shutdown(shutdownCtx)
		if err := networkManager.Stop(); err != nil {
			logger.ErrorContext(shutdownCtx, "network stop failed",
				slog.Any("error", err),
			)
		}
	}()

	return done
}
