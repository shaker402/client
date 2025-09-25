# UnifySec — The First All-in-One Open Source Security Platform 🌟

> **UnifySec SOC** unifies endpoint, network, SIEM, SIRP, forensics, and vulnerability management into a single open-source platform — built to eliminate tool sprawl, speed detection & response, and give security teams one single pane of glass. 🚀

---

## Table of Contents

1. [Overview](#overview)
2. [Key Features](#key-features)
3. [Why UnifySec ?](#why-UnifySec-soc)
4. [Architecture & Workflow](#architecture--workflow)
5. [Quick Start](#quick-start)
6. [Core Components & Actions](#core-components--actions)
7. [Compliance & Reporting](#compliance--reporting)
8. [Integrations & Extensibility](#integrations--extensibility)
9. [Operational Playbooks (short)](#operational-playbooks-short)
10. [Troubleshooting & FAQs](#troubleshooting--faqs)
11. [Contributing](#contributing)
12. [License & Credits](#license--credits)
13. [Contact US](#contact--US)

---

# Overview

UnifySec SOC consolidates proven open source projects into a tightly integrated security operations platform. It ships a **Unified Agent** (Wazuh + Elastic Beats + Velociraptor + packet-capture sensor), a **SIEM & correlation engine**, **instant response** capabilities, **automated forensics**, **deep network analysis**, continuous **vulnerability management**, and compliance monitoring — all accessible through a single dashboard.

---

# Key Features

* 🔹 **Unified Agent** — single install that deploys Wazuh, Elastic Beats (Filebeat/Metricbeat/Auditbeat/Heartbeat), Velociraptor, and a packet-capture sensor.
* 🔹 **SIEM & Correlation** — Elasticsearch + Kibana-based ingestion, correlation engine, playbooks, and case management.
* ⚡ **Instant Response** — block IPs/domains, isolate hosts, terminate malicious processes via Velociraptor API and integrated responders.
* 🔎 **Automated Forensics** — timeline analysis with HardeningKitty, Persistence Sniper, HAYABUSA, SIGMA-based artifacts.
* 🌐 **Network Analysis** — Arkime (PCAP), Zeek, Suricata, YARA/Capa/ClamAV, VirusTotal integration for malware scanning.
* ✅ **Compliance** — CIS, NIST, PCI-DSS, GDPR, HIPAA, SOC2, ISO 27001 readiness checks and reporting.
* 🛠️ **Vulnerability Management** — continuous scanning, Wazuh-based asset & vulnerability tracking.
* 🤖 **AI Analyst** — automated detection suggestions and triage (configurable).

---

# Why UnifySec SOC?

* Eliminates tool sprawl (replaces N8n, Elastalert, DFIR-IRIS, TheHive, Cortex).
* Reduces integration complexity and TCO.
* Provides true single-pane visibility and faster MTTR.
* Open-source foundation with enterprise integration options.

---

# Architecture & Workflow

UnifySec SOC flow (high level):

1. **Unified Agent Deployment** to endpoints → collects logs, metrics, artifacts, and PCAPs.
2. **Data Ingestion** into Elasticsearch via Beats/Logstash.
3. **Correlation & Alerting** — playbooks and case management create incidents.
4. **Instant Response** — responders call Velociraptor to contain/mitigate.
5. **Automated Forensics** — run timeline & persistence checks automatically.
6. **Network Forensics** — Arkime / Zeek / Suricata analyze traffic and link to alerts.
7. **Compliance & Vulnerability** reporting through Wazuh integrations.

(See the shipped architecture & detailed workflow PDF for diagrams and full data flows.)&#x20;

---

# Quick Start

> These steps give a minimal, ready-to-use starting point. Adapt to your infra and security policies before production use.

## Prerequisites

* Linux servers for core services (Ubuntu 20.04+ recommended).
* 48+ GB RAM for a small cluster (adjust by scale).
* Docker & docker-compose (or Kubernetes) if using containerized deployment.

##Quick Start script

> After the start_all_services.sh completes its initialization steps, open the UnifySec SOC web UI to finish configuration and download the Unified Agent package from the GUI to deploy to endpoints..

```
# clone the repo
git clone https://github.com/shaker402/client.git
cd client

# make sure the start script is executable then run it
chmod +x ./start_all_services.sh
sudo ./start_all_services.sh

```



> After services are up, you can access Esmart SOC GUI by https://your_IP:3003

---

## Demo — Full Video (click to play)


https://github.com/user-attachments/assets/3d30a40f-63f1-45b8-8530-93a5f44a8b81

**Duration:** 5:12 — Click the link above to open and play the demo directly from this repository .

---
# Core Components & Actions


## SIEM & Correlation

* Elasticsearch indexes logs and events; Kibana offers visualization & dashboards.
* Sigma/SIGMA rules and playbooks translate detections to incidents and escalations.

## one click Instant Response

* **Block IP:** **Block Domain:**  **Block Service :** **Block IP:** **Isolate host:**




## one click Automated Forensics

* Run artifact collectors and timeline builders automatically on confirmed incidents (HardeningKitty, Persistence Sniper, HAYABUSA).
* Generate investigation artifacts and attach them to cases.

## automatic Network Analysis

* PCAP capture (Arkime), DPI (Zeek/Suricata), and YARA/Capa/ClamAV scans produce network-level indicators and link to alerts.

---

# Compliance & Reporting

UnifySec SOC provides continuous compliance checks and reporting for:

* CIS Benchmarks, NIST 800-53 / CSF
* PCI-DSS, GDPR, HIPAA, SOC2, ISO 27001
* Audit trails and automated evidence collection via Wazuh rules.

---

# Integrations & Extensibility

UnifySec is built to integrate:

* Threat intel platforms (MISP), VirusTotal, external ticketing (Jira/ServiceNow), orchestration tools, and custom webhooks.
* Automation and workflow linking (e.g., Latenode) to automate routine processes and cross-platform flows.

---

# Operational Playbooks (short)

* **Malware on host:** Auto-quarantine → collect timeline → YARA/Capa analysis → submit to malware queue → enrich with VT → escalate if high risk.
* **C2 beaconing detected:** Block IP → isolate host → full memory + disk artifact collection → correlate with network PCAPs → generate IOC set.

---

# Troubleshooting & FAQs

**Q: Agent not reporting?**
A: Verify registration token, firewall connectivity to Velociraptor/Wazuh, and that Beats can reach Elasticsearch.

**Q: False positives?**
A: Tune SIGMA rules, adjust playbook thresholds, and leverage AI Analyst learning windows.

**Q: How to scale?**
A: Use Elasticsearch clusters with dedicated master/data nodes, scale Arkime storage, and horizontally scale Velociraptor collectors.

---

# Contributing

We welcome contributors. Common ways to get involved:

* Submit bug reports & feature requests.
* Contribute playbooks, SIGMA rules, dashboards, and integrations.
* Improve packaging and automation scripts.

Please follow CONTRIBUTING.md conventions (PRs, tests, and documentation).

---

# License & Credits

UnifySec SOC is built on top of many amazing open source projects (Wazuh, Elastic Beats, Velociraptor, Arkime, Zeek, Suricata, YARA, Capa, HardeningKitty, Persistence Sniper, HAYABUSA, etc.). Check each component’s license for details. ## License

UnifySec SOC is licensed under the **Apache License, Version 2.0** — see the [LICENSE](./LICENSE) file for details.

---

# Social / Tags

`#UnifySec #CyberSecurity #SIEM #SOCR #ThreatIntelligence #InfoSec #CyberDefense #SecurityOperations #OpenSourceSecurity #Innovation #CyberSecuritySolution #SOC #Compliance #VulnerabilityManagement #NetworkSecurity #DigitalTransformation`

---
# Contact Us

* **WhatsApp:** [+967 77 645 2756](https://wa.me/967776452756)
* **Email:** [shakeralkmali@gmail.com](mailto:shakeralkmali@gmail.com)

Feel free to message on WhatsApp for quick questions or send detailed requests by email.


