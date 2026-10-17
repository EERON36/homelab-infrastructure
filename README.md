# Homelab / Infrastructure

An evolving homelab inventory and infrastructure portfolio covering virtualization, networking, storage, monitoring, documentation, and small automations.

## Status

The first discovery snapshot was collected on 17 October 2026. This is a partial inventory, not a complete or continuously monitored infrastructure map.

Start with the [first infrastructure map](docs/infrastructure-map.md), the [sanitized inventory](inventory/initial-snapshot.json), and the [discovery instructions](docs/discovery.md).

The initial pass observed 13 responding LAN addresses, in addition to the Windows discovery host; 7 locally registered Hyper-V VMs, with 1 running; and 6 Tailscale registrations, with 4 reported online including the discovery host. These counts overlap and must not be added together.

## Future scope

Over time, this repository should document:

- Sanitized homelab architecture and infrastructure decisions.
- Troubleshooting examples, lessons learned, and useful documentation.
- Configurations without secrets or sensitive information.
- Useful small Bash and PowerShell automations.

Raw results remain in the ignored `local-discovery/` directory. Committed examples use aliases and omit IP addresses, MAC addresses, personal device names, account details, and tailnet domains. Never commit passwords, tokens, private keys, or other secrets.
