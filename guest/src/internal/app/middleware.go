//go:build linux

package app

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
)

// middlewareRequestID generates a unique request ID for each request and
// adds it to the request context for tracing through logs.
func (a *App) middlewareRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := generateRequestID()
		ctx := context.WithValue(r.Context(), requestIDKey, id)

		a.logger.InfoContext(ctx, "request started",
			slog.String("request_id", id),
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.String("remote_addr", r.RemoteAddr),
		)

		w.Header().Set("X-Request-ID", id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// middlewareRecovery will recover from a panic and log it. Ideally, this
// never gets called.
func (a *App) middlewareRecovery(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func(ctx context.Context) {
			if rec := recover(); rec != nil {
				a.logger.ErrorContext(ctx, "request panic recovered")
			}
		}(r.Context())

		next.ServeHTTP(w, r)
	})
}

// generateRequestID creates a random 8 byte hex string for request tracing.
func generateRequestID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "unknown"
	}

	return hex.EncodeToString(b)
}
