# Azure Enclaves: Architecture Samples

A collection of deployable reference architectures for [Azure Enclaves](https://learn.microsoft.com/en-us/azure/enclave/). Each architecture is self-contained, written in Bicep, and has its own README with deploy, validate, and teardown steps.

> **Disclaimer:** These are sample templates for learning and demos for the Azure Enclave service. They are not an official Microsoft product, come with no warranty or support, and are not hardened for production. All names, domains (`contoso.local`), and IP ranges are placeholders.

## Architectures

| # | Architecture | What it shows | Time to deploy |
|---|---|---|---|
| 01 | [Transit hub peering to corporate Active Directory](architectures/01-transit-hub-peering-ad/README.md) | An enclave VM reaches a domain controller outside the enclave through the community firewall and a peered transit hub. | 1.5–3 hours |
| *next* | *Planned, contributions welcome* | See [docs/ADDING-AN-ARCHITECTURE.md](docs/ADDING-AN-ARCHITECTURE.md). | |

## Key concepts

| Concept | In one sentence |
|---|---|
| **Community** | A shared governance and network boundary (hub, firewall, address space, approval policy) that owns every enclave. |
| **Enclave** | An isolated, policy-governed network carved out of a community. Nothing gets in or out by default. |
| **Workload** | Resource groups linked to an enclave that inherit its guardrails. |
| **Transit hub** | The controlled connection from a community to a network outside it. |
| **Community endpoint** | Publishes what outside the community can be reached, and through which transit hub. |
| **Enclave connection** | An enclave's explicit opt-in to a community endpoint. |

## Common prerequisites

- An Azure subscription where you are **Owner**, or **Contributor + User Access Administrator**.
- Access to the `Microsoft.Mission` resource provider.
- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) with the Az modules (or the Azure CLI for the `AzCli` script variants).
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install).

Each architecture README lists anything extra.

## Getting started

1. Pick an architecture from the table above.
2. Open its README and follow **Quick start**.
3. **Tear down** when you finish. Firewalls, Bastion hosts, and VMs bill while they exist.

## Repository layout

```
README.md                      # this file
LICENSE
docs/                          # contributor guides
architectures/
  01-transit-hub-peering-ad/   # one self-contained folder per architecture
    README.md
    Deploy-AVEDemo.ps1
    bicep/
    scripts/
```

## License

[MIT](LICENSE)
