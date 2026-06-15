//go:build linux

package app

import (
	"context"
	"log/slog"
	"net/http"
	"time"
)

// ctxKey is a type for context keys to avoid collisions.
type ctxKey string

const requestIDKey ctxKey = "request_id"

// App holds the HTTP server and its dependencies.
type App struct {
	server *http.Server
	logger *slog.Logger
}

// Config holds configuration for creating an ACPI instance.
type Config struct {
	Logger *slog.Logger
}

// New creates a new App with the given logger.
func New(cfg Config) *App {
	app := &App{
		logger: cfg.Logger,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", app.handleRequests)

	wrapper := app.middlewareRecovery(app.middlewareRequestID(mux))
	app.server = &http.Server{
		Addr:              ":8080",
		Handler:           wrapper,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	return app
}

// Run starts the HTTP server. This blocks until the server is shut down.
func (a *App) Run() {
	a.logger.Info("server starting", slog.String("addr", ":8080"))

	err := a.server.ListenAndServe()
	if err == http.ErrServerClosed {
		a.logger.Info("server stopped")
		return
	}
}

// Shutdown gracefully stops the HTTP server.
func (a *App) Shutdown(ctx context.Context) {
	a.logger.InfoContext(ctx, "stopping HTTP server")

	if err := a.server.Shutdown(ctx); err != nil {
		a.logger.ErrorContext(ctx, "shutdown failed",
			slog.Any("error", err),
		)
	}
}
