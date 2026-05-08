# ChronosPrime v2.0 — Pantheon Memory Backbone

**The Archiver / Time Kernel**

4-Tier SQLite memory system. No vector DB. No cloud cost. $0/month.

## Architecture

| Tier | Name | Decay |
|------|------|-------|
| 1 | Episodic — what happened | 7 days |
| 2 | Semantic — what we know | Long-term |
| 3 | Project — what we're building | Updated as needed |
| 4 | Procedural — rules & preferences | Permanent |

## Usage

```python
from chronos_prime import ChronosPrime

cp = ChronosPrime()

# Write a memory
cp.remember("MidasPrime earned $500 from PropPilot", tier="episodic", source="MidasPrime")

# Load session context (stays under 4000 tokens)
context = cp.load_context(token_budget=4000)

# Search memories
results = cp.search("PropPilot", tier="project")

# Run weekly distillation
cp.distill()

# Stats
print(cp.stats())
```

## Seeded With
- 18 Primes registered
- 21 entities in knowledge graph
- 10 relationships mapped
- 9 procedural rules locked in

## Wire Into Every Prime

Add this to the top of any Prime's session startup:

```python
from chronos_prime import ChronosPrime
cp = ChronosPrime()
context = cp.load_context(token_budget=4000)
# Inject context into your system prompt
```
