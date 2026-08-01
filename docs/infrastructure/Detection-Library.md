---
title: Detection Library
tags: [infrastructure, blueteam, detection, sigma, yara, deliverable]
path: ~/engagements/detection-library/
updated: 2026-07-27
---

# Detection Library

Back to [[00-Index]]. The compounding output of the [[Architecture-Overview|red→blue loop]] — and a client deliverable in its own right.

## What it is
A persistent, growing corpus of detection rules generated from real red-team activity. Every TTP run through [[detection-engineer]] becomes production Sigma + YARA + network rules filed here. It gets more valuable with every engagement.

## Layout
```
~/engagements/detection-library/
├── INDEX.md                       # running table of all coverage
├── sigma/    {technique_id}-{slug}.yml
├── yara/     {technique_id}-{slug}.yar
└── network/  {technique_id}-{slug}.rules   # Suricata rules + IOC lists
```

## INDEX.md schema
```markdown
| Date | Technique | MITRE ID | Tactic | Huntress Coverage | Files |
|------|-----------|----------|--------|-------------------|-------|
| ...  | ...       | Txxxx    | ...    | COVERED / GAP     | sigma/, yara/, network/ |
```

## Written by
- [[detection-engineer]] (Step 6 appends the three rule files + updates INDEX)

## Referenced by
- [[debrief]] §8 (Detection Engineering Gaps) cites the INDEX and recommends `/detection-engineer` runs for the top undetected techniques
- [[triage-alerts]] feeds it the list of MISSED techniques worth writing rules for

## Related
- [[Network-Sensors]] (where the network rules get validated) · [[mcp-virustotal]] (behavioral strings for YARA)
