//go:build linux

package boot

import (
	"context"
	"log/slog"
	"syscall"

	"github.com/lcox74/bingo/src/internal/network"
)

// Boot handles early system initialization before networking.
type Boot struct {
	logger   *slog.Logger
	hostname string
}

// Config holds configuration for creating a Boot instance.
type Config struct {
	Logger           *slog.Logger
	FallbackHostname string
}

// New creates a new Boot with the given configuration.
func New(cfg Config) *Boot {
	hostname := cfg.FallbackHostname
	if hostname == "" {
		hostname = "bingo"
	}

	return &Boot{
		logger:   cfg.Logger,
		hostname: hostname,
	}
}

// Run performs early boot initialization: mounts filesystems and sets
// a fallback hostname. Network configuration should be done separately
// after Run completes, which may update the hostname via DHCP.
func (b *Boot) Run(ctx context.Context) error {
	b.logger.InfoContext(ctx, "mounting filesystems")
	if err := b.mountFilesystems(ctx); err != nil {
		return err
	}

	b.logger.InfoContext(ctx, "setting fallback hostname",
		slog.String("hostname", b.hostname),
	)

	return syscall.Sethostname([]byte(b.hostname))
}

// UpdateHostname updates the system hostname. This is typically called
// after DHCP provides a hostname, or to generate one from the MAC address.
func (b *Boot) UpdateHostname(ctx context.Context, hostname string) error {
	if hostname == "" {
		return nil
	}

	b.logger.InfoContext(ctx, "updating hostname",
		slog.String("hostname", hostname),
	)

	return network.SetHostname(hostname)
}
