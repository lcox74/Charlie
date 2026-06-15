//go:build linux

package network

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"os"
	"strings"
	"time"

	"github.com/vishvananda/netlink"
)

// Network manages network interface configuration and DHCP.
type Network struct {
	logger     *slog.Logger
	interfaces []string
	dhcpIface  string
	dhcp       *DHCPClient
}

// Config holds configuration for creating a Network.
type Config struct {
	Logger     *slog.Logger
	Interfaces []string
	DHCPIface  string
}

// New creates a new Network with the given configuration.
func New(cfg Config) *Network {
	return &Network{
		logger:     cfg.Logger,
		interfaces: cfg.Interfaces,
		dhcpIface:  cfg.DHCPIface,
	}
}

// getLink looks up a network interface by name.
func getLink(name string) (netlink.Link, error) {
	link, err := netlink.LinkByName(name)
	if err != nil {
		return nil, fmt.Errorf("%s lookup: %w", name, err)
	}
	return link, nil
}

// Start brings up interfaces, acquires a DHCP lease, and starts renewal.
func (n *Network) Start(ctx context.Context) error {
	if err := n.bringUpInterfaces(ctx); err != nil {
		return fmt.Errorf("bring up interfaces: %w", err)
	}

	n.dhcp = NewDHCPClient(n.logger, n.dhcpIface)

	dhcpCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	lease, err := n.dhcp.Acquire(dhcpCtx)
	if err != nil {
		return fmt.Errorf("dhcp acquire: %w", err)
	}

	if err := n.configureNetwork(ctx, lease); err != nil {
		return fmt.Errorf("configure network: %w", err)
	}

	n.dhcp.OnRenew(n.handleLeaseRenewal(ctx))

	if err := n.dhcp.StartRenewal(ctx); err != nil {
		return fmt.Errorf("start renewal: %w", err)
	}

	return nil
}

// handleLeaseRenewal returns a callback that updates hostname on renewal.
func (n *Network) handleLeaseRenewal(ctx context.Context) func(*Lease) {
	return func(lease *Lease) {
		if lease.Hostname == "" {
			return
		}

		if err := SetHostname(lease.Hostname); err != nil {
			n.logger.WarnContext(ctx, "failed to update hostname on renewal",
				slog.Any("error", err),
			)

			return
		}

		n.logger.InfoContext(ctx, "hostname updated on renewal",
			slog.String("hostname", lease.Hostname),
		)
	}
}

func (n *Network) bringUpInterfaces(ctx context.Context) error {
	for _, name := range n.interfaces {
		link, err := getLink(name)
		if err != nil {
			return err
		}

		if err := netlink.LinkSetUp(link); err != nil {
			return fmt.Errorf("%s up: %w", name, err)
		}

		n.logger.InfoContext(ctx, "interface up", slog.String("iface", name))
	}
	return nil
}

func (n *Network) configureNetwork(ctx context.Context, lease *Lease) error {
	link, err := getLink(n.dhcpIface)
	if err != nil {
		return err
	}

	addr := &netlink.Addr{
		IPNet: &net.IPNet{IP: lease.IP, Mask: lease.Mask},
	}

	if err := netlink.AddrAdd(link, addr); err != nil {
		return fmt.Errorf("add addr: %w", err)
	}

	if err := netlink.RouteAdd(&netlink.Route{Gw: lease.Gateway}); err != nil {
		return fmt.Errorf("add route: %w", err)
	}

	if len(lease.DNS) > 0 {
		var sb strings.Builder
		for _, dns := range lease.DNS {
			fmt.Fprintf(&sb, "nameserver %s\n", dns)
		}

		err := os.WriteFile("/etc/resolv.conf", []byte(sb.String()), 0o644)
		if err != nil {
			return fmt.Errorf("write resolv.conf: %w", err)
		}
	}

	ones, _ := lease.Mask.Size()
	n.logger.InfoContext(ctx, "network configured",
		slog.String("ip", fmt.Sprintf("%s/%d", lease.IP, ones)),
		slog.String("gateway", lease.Gateway.String()),
	)

	return nil
}

// Stop gracefully stops the DHCP renewal goroutine.
func (n *Network) Stop() error {
	if n.dhcp != nil {
		return n.dhcp.Stop()
	}
	return nil
}

// Lease returns the current DHCP lease.
func (n *Network) Lease() *Lease {
	if n.dhcp == nil {
		return nil
	}
	return n.dhcp.Lease()
}

// Hostname returns the hostname from the DHCP lease, or generates one from
// the MAC address if no hostname was provided. Returns the fallback if neither
// is available.
func (n *Network) Hostname(fallback string) string {
	if lease := n.Lease(); lease != nil && lease.Hostname != "" {
		return lease.Hostname
	}

	if hostname := HostnameFromMAC(n.dhcpIface, fallback); hostname != "" {
		return hostname
	}

	return fallback
}
