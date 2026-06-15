//go:build linux

package boot

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"syscall"
)

// mounts defines the virtual filesystems to mount during boot.
// Format: source, target, fstype
var mounts = [][3]string{
	{"proc", "/proc", "proc"},        // Process info
	{"sysfs", "/sys", "sysfs"},       // Hardware/driver info
	{"devtmpfs", "/dev", "devtmpfs"}, // Device nodes
	{"devpts", "/dev/pts", "devpts"}, // Pseudoterminals
	{"tmpfs", "/dev/shm", "tmpfs"},   // Shared memory
	{"tmpfs", "/tmp", "tmpfs"},       // Temp files
	{"tmpfs", "/run", "tmpfs"},       // Runtime data
}

// mountFilesystems mounts all required virtual filesystems.
func (b *Boot) mountFilesystems(ctx context.Context) error {
	for _, m := range mounts {
		source, target, fstype := m[0], m[1], m[2]

		if err := os.MkdirAll(target, 0o750); err != nil {
			return fmt.Errorf("mkdir %s: %w", target, err)
		}

		if err := syscall.Mount(source, target, fstype, 0, ""); err != nil {
			return fmt.Errorf("mount %s: %w", target, err)
		}

		b.logger.DebugContext(ctx, "mounted",
			slog.String("target", target),
			slog.String("fstype", fstype),
		)
	}
	return nil
}
