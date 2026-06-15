//go:build linux

package app

import (
	"fmt"
	"log/slog"
	"net/http"
)

// handleRequests handles incoming HTTP requests.
func (a *App) handleRequests(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	requestID, ok := ctx.Value(requestIDKey).(string)
	if !ok {
		requestID = "unknown"
	}

	if _, err := fmt.Fprintln(w, "Hello, World!"); err != nil {
		a.logger.ErrorContext(ctx, "write response failed",
			slog.String("request_id", requestID),
			slog.Any("error", err),
		)
	}
}
