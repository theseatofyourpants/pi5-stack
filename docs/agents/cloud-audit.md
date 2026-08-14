---
title: /cloud-audit
tags: [skill, agent, offensive, cloud, container, iac, assessment]
skill_name: cloud-audit
model: claude-opus-5
file: ~/.claude/agents/cloud-audit.md
updated: 2026-08-14
---

# /cloud-audit

Part of [[Operator-Skills]]. Fills the one domain the rest of the suite never covered:
**cloud + container + IaC** security. The [[web-assess]]/[[device-assess]] sibling for
everything above the network layer.

- **Cloud posture:** `prowler`, `scout-suite` (AWS/Azure/GCP, CIS).
- **IaC:** `checkov`, `terrascan` (Terraform/CFN/k8s manifests) — shift-left the runtime findings.
- **Containers/images:** `trivy` (CVEs + secrets), `docker-bench-security` (CIS Docker).
- **Kubernetes:** `kube-bench` (CIS), `kube-hunter` (attack surface).

**Non-destructive by design** — read-only posture/config review; the active-exploitation
tool (`pacu`) is deliberately excluded. Hard-gated to operator-supplied *authorized,
read-only* creds / IaC paths / images. Logs into [[wstg-pentest|wstg]] so [[debrief]] and
[[detection-engineer]] inherit findings. Depends on the extended toolset (see [[mcp-hexstrike]]).
