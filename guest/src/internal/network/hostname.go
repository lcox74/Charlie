//go:build linux

package network

import (
	"fmt"
	"syscall"

	"github.com/vishvananda/netlink"
)

// HostnameFromMAC generates a hostname from the last 3 bytes of the given
// interface's MAC address. Returns empty string if the interface cannot be
// found or has an invalid MAC.
func HostnameFromMAC(ifname, prefix string) string {
	link, err := netlink.LinkByName(ifname)
	if err != nil {
		return ""
	}

	mac := link.Attrs().HardwareAddr
	if len(mac) < 3 {
		return ""
	}

	return fmt.Sprintf("%s-%02x%02x%02x", prefix, mac[len(mac)-3], mac[len(mac)-2], mac[len(mac)-1])
}

// SetHostname sets the system hostname using the sethostname syscall.
func SetHostname(hostname string) error {
	return syscall.Sethostname([]byte(hostname))
}
