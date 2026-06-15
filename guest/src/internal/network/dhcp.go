//go:build linux

package network

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"os"
	"sync/atomic"
	"time"

	"github.com/insomniacslk/dhcp/dhcpv4"
	"github.com/insomniacslk/dhcp/dhcpv4/nclient4"
)

// Lease holds the information obtained from a DHCP server.
type Lease struct {
	IP          net.IP
	Mask        net.IPMask
	Gateway     net.IP
	DNS         []net.IP
	Hostname    string
	LeaseTime   time.Duration
	RenewalTime time.Duration
	RebindTime  time.Duration
	AcquiredAt  time.Time
}

// parseDurationOption extracts a duration from a 4 byte DHCP option.
func parseDurationOption(opts dhcpv4.Options, code dhcpv4.OptionCode, fallback time.Duration) time.Duration {
	if data := opts.Get(code); len(data) == 4 {
		return time.Duration(binary.BigEndian.Uint32(data)) * time.Second
	}

	return fallback
}

// DHCPClient manages DHCP lease acquisition and renewal for an interface.
type DHCPClient struct {
	logger  *slog.Logger
	iface   string
	lease   atomic.Pointer[Lease]
	onRenew atomic.Pointer[func(*Lease)]
	cancel  context.CancelFunc
	done    chan struct{}
}

// NewDHCPClient creates a new DHCP client for the given interface.
func NewDHCPClient(logger *slog.Logger, iface string) *DHCPClient {
	return &DHCPClient{
		logger: logger,
		iface:  iface,
		done:   make(chan struct{}),
	}
}

// Acquire performs a full DHCP exchange and returns the lease.
func (d *DHCPClient) Acquire(ctx context.Context) (*Lease, error) {
	// The insomniacslk/dhcp library uses getrandom(2) for transaction IDs,
	// which blocks until the kernel CRNG is initialized. In minimal VMs
	// without hardware entropy this can stall indefinitely. Fall back to
	// /dev/urandom which is sufficient for DHCP.
	if err := os.Setenv("UROOT_NOHWRNG", "1"); err != nil {
		return nil, fmt.Errorf("setenv UROOT_NOHWRNG: %w", err)
	}

	d.logger.InfoContext(ctx, "starting DHCP exchange",
		slog.String("iface", d.iface),
	)

	lease, err := d.exchange(ctx)
	if err != nil {
		return nil, err
	}

	d.lease.Store(lease)

	ones, _ := lease.Mask.Size()
	d.logger.InfoContext(ctx, "DHCP lease acquired",
		slog.String("ip", fmt.Sprintf("%s/%d", lease.IP, ones)),
		slog.String("gateway", lease.Gateway.String()),
		slog.Any("dns", lease.DNS),
		slog.Duration("lease_time", lease.LeaseTime),
	)

	return lease, nil
}

// exchange performs the actual DHCP protocol exchange.
func (d *DHCPClient) exchange(ctx context.Context) (*Lease, error) {
	client, err := nclient4.New(d.iface)
	if err != nil {
		return nil, fmt.Errorf("dhcp client: %w", err)
	}
	defer func() {
		if err2 := client.Close(); err2 != nil {
			d.logger.WarnContext(ctx, "dhcp client close",
				slog.Any("error", err2),
			)
		}
	}()

	raw, err := client.Request(ctx)
	if err != nil {
		return nil, fmt.Errorf("dhcp request: %w", err)
	}

	return parseLease(raw.ACK), nil
}

// parseLease extracts lease information from a DHCP ACK packet.
func parseLease(ack *dhcpv4.DHCPv4) *Lease {
	leaseTime := ack.IPAddressLeaseTime(time.Hour)
	lease := &Lease{
		IP:          ack.YourIPAddr,
		Mask:        ack.SubnetMask(),
		Hostname:    ack.HostName(),
		LeaseTime:   leaseTime,
		RenewalTime: parseDurationOption(ack.Options, dhcpv4.OptionRenewTimeValue, leaseTime/2),
		RebindTime:  parseDurationOption(ack.Options, dhcpv4.OptionRebindingTimeValue, leaseTime*7/8),
		AcquiredAt:  time.Now(),
	}

	if routers := ack.Router(); len(routers) > 0 {
		lease.Gateway = routers[0]
	}

	if dns := ack.DNS(); len(dns) > 0 {
		lease.DNS = dns
	}

	return lease
}

// StartRenewal starts a background goroutine that handles lease renewal
// following RFC 2131 timing (T1 for renewal, T2 for rebind).
func (d *DHCPClient) StartRenewal(ctx context.Context) error {
	if d.lease.Load() == nil {
		return errors.New("no lease acquired")
	}

	ctx, d.cancel = context.WithCancel(ctx)
	go d.renewalLoop(ctx)

	return nil
}

// waitUntil blocks until the target time or context cancellation.
func waitUntil(ctx context.Context, target time.Time) bool {
	if wait := time.Until(target); wait > 0 {
		select {
		case <-ctx.Done():
			return false
		case <-time.After(wait):
		}
	}

	return true
}

// renewalLoop runs the DHCP renewal state machine.
func (d *DHCPClient) renewalLoop(ctx context.Context) {
	defer close(d.done)

	for {
		lease := d.lease.Load()
		if lease == nil {
			d.logger.ErrorContext(ctx, "renewal loop: no lease")
			return
		}

		t1 := lease.AcquiredAt.Add(lease.RenewalTime)
		t2 := lease.AcquiredAt.Add(lease.RebindTime)

		d.logger.DebugContext(ctx, "waiting for T1",
			slog.Duration("wait", time.Until(t1)),
		)

		if !waitUntil(ctx, t1) {
			d.logger.InfoContext(ctx, "renewal stopped")
			return
		}

		// Try renewal at T1, then rebind at T2, then full rediscovery
		if d.tryRenew(ctx, "renewal", 30*time.Second) {
			continue
		}

		if !waitUntil(ctx, t2) {
			d.logger.InfoContext(ctx, "renewal stopped")
			return
		}

		if d.tryRenew(ctx, "rebind", 30*time.Second) {
			continue
		}

		if d.tryRenew(ctx, "rediscovery", 30*time.Second) {
			continue
		}

		// All attempts failed, back off before retrying
		if !waitUntil(ctx, time.Now().Add(10*time.Second)) {
			return
		}
	}
}

// tryRenew attempts a DHCP exchange and stores the lease on success.
func (d *DHCPClient) tryRenew(ctx context.Context, phase string, timeout time.Duration) bool {
	d.logger.InfoContext(ctx, "attempting lease "+phase)
	exchCtx, cancel := context.WithTimeout(ctx, timeout)
	newLease, err := d.exchange(exchCtx)
	cancel()

	if err != nil {
		d.logger.WarnContext(ctx, phase+" failed", slog.Any("error", err))
		return false
	}

	d.lease.Store(newLease)
	d.logger.InfoContext(ctx, "lease "+phase+" succeeded",
		slog.Duration("lease_time", newLease.LeaseTime),
	)

	d.notifyRenew(newLease)
	return true
}

// OnRenew registers a callback to be invoked when the lease is renewed.
func (d *DHCPClient) OnRenew(fn func(*Lease)) {
	d.onRenew.Store(&fn)
}

// notifyRenew calls the registered callback with the new lease.
func (d *DHCPClient) notifyRenew(lease *Lease) {
	if fn := d.onRenew.Load(); fn != nil {
		(*fn)(lease)
	}
}

// Stop gracefully stops the renewal goroutine.
func (d *DHCPClient) Stop() error {
	if d.cancel != nil {
		d.cancel()
		<-d.done
	}

	return nil
}

// Lease returns a copy of the current lease.
func (d *DHCPClient) Lease() *Lease {
	lease := d.lease.Load()
	if lease == nil {
		return nil
	}

	result := *lease
	return &result
}
