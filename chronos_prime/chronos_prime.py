"""
ChronosPrime v2.0 — Pantheon Memory Backbone
The Archiver / Time Kernel

4-Tier Memory System:
  Tier 1 - Episodic:    What happened (sessions, events) — decays after 7 days
  Tier 2 - Semantic:    What we know (facts, entities, relationships) — long-term
  Tier 3 - Project:     What we're building (goals, decisions, status) — updated as needed
  Tier 4 - Procedural:  How to do things (rules, preferences, workflows) — permanent

Usage:
    from chronos_prime import ChronosPrime
    cp = ChronosPrime()
    cp.remember("MidasPrime earned $500 from PropPilot", tier="episodic", source="MidasPrime")
    context = cp.load_context(token_budget=4000)
"""

import sqlite3
import json
import os
from datetime import datetime, timedelta
from pathlib import Path

DB_PATH = Path(__file__).parent / "chronos.db"
SCHEMA_PATH = Path(__file__).parent / "schema.sql"


class ChronosPrime:
    def __init__(self, db_path=None):
        self.db_path = db_path or DB_PATH
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row
        self._init_db()

    def _init_db(self):
        """Initialize schema if not exists."""
        if SCHEMA_PATH.exists():
            self.conn.executescript(SCHEMA_PATH.read_text())
        self.conn.commit()

    # ─────────────────────────────────────────
    # WRITE
    # ─────────────────────────────────────────

    def remember(self, content: str, tier: str = "episodic", source: str = "ZapiaPrime",
                 metadata: dict = None, confidence: float = 1.0, expires_days: int = None):
        """Store a memory in the appropriate tier."""
        expires_at = None
        if expires_days:
            expires_at = (datetime.now() + timedelta(days=expires_days)).isoformat()
        elif tier == "episodic":
            expires_at = (datetime.now() + timedelta(days=7)).isoformat()

        self.conn.execute("""
            INSERT INTO memories (tier, source, content, metadata, confidence, expires_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (tier, source, content, json.dumps(metadata or {}), confidence, expires_at))
        self.conn.commit()
        return True

    def add_entity(self, name: str, entity_type: str, properties: dict = None):
        """Add or update an entity in the knowledge graph."""
        self.conn.execute("""
            INSERT INTO entities (name, type, properties)
            VALUES (?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET
                properties = excluded.properties,
                updated_at = CURRENT_TIMESTAMP
        """, (name, entity_type, json.dumps(properties or {})))
        self.conn.commit()

    def add_relationship(self, source: str, relation: str, target: str, properties: dict = None):
        """Link two entities with a relationship."""
        # Ensure entities exist
        for name in [source, target]:
            self.conn.execute("""
                INSERT OR IGNORE INTO entities (name, type) VALUES (?, 'concept')
            """, (name,))

        self.conn.execute("""
            INSERT INTO relationships (source_entity, target_entity, relation_type, properties)
            SELECT e1.id, e2.id, ?, ?
            FROM entities e1, entities e2
            WHERE e1.name = ? AND e2.name = ?
        """, (relation, json.dumps(properties or {}), source, target))
        self.conn.commit()

    def register_prime(self, name: str, role: str, status: str = "dormant",
                       repo_url: str = None, notes: str = None):
        """Register a Prime in the Pantheon registry."""
        self.conn.execute("""
            INSERT INTO primes (name, role, status, repo_url, notes)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET
                role = excluded.role,
                status = excluded.status,
                repo_url = excluded.repo_url,
                notes = excluded.notes
        """, (name, role, status, repo_url, notes))
        self.conn.commit()

    def log_war_chest(self, event_type: str, amount: float, source: str,
                      description: str, balance_after: float):
        """Log a War Chest financial event."""
        self.conn.execute("""
            INSERT INTO war_chest (event_type, amount, source, description, balance_after)
            VALUES (?, ?, ?, ?, ?)
        """, (event_type, amount, source, description, balance_after))
        self.conn.commit()

    # ─────────────────────────────────────────
    # READ
    # ─────────────────────────────────────────

    def load_context(self, token_budget: int = 4000) -> str:
        """
        Distill the most relevant memories into a session context string.
        Prioritizes: procedural > project > semantic > recent episodic
        Target: stay within token_budget (rough 4 chars/token estimate)
        """
        char_budget = token_budget * 4
        sections = []

        # Tier 4 - Procedural (rules, preferences) — highest priority
        procedural = self.conn.execute("""
            SELECT content FROM memories
            WHERE tier = 'procedural' AND (expires_at IS NULL OR expires_at > datetime('now'))
            ORDER BY confidence DESC, access_count DESC
            LIMIT 20
        """).fetchall()
        if procedural:
            sections.append("## RULES & PREFERENCES\n" + "\n".join(f"- {r['content']}" for r in procedural))

        # Tier 3 - Project (active goals, decisions)
        project = self.conn.execute("""
            SELECT content FROM memories
            WHERE tier = 'project' AND (expires_at IS NULL OR expires_at > datetime('now'))
            ORDER BY updated_at DESC
            LIMIT 15
        """).fetchall()
        if project:
            sections.append("## ACTIVE PROJECTS\n" + "\n".join(f"- {r['content']}" for r in project))

        # Tier 2 - Semantic (facts, knowledge)
        semantic = self.conn.execute("""
            SELECT content FROM memories
            WHERE tier = 'semantic' AND confidence >= 0.8
            ORDER BY access_count DESC, confidence DESC
            LIMIT 20
        """).fetchall()
        if semantic:
            sections.append("## KNOWLEDGE BASE\n" + "\n".join(f"- {r['content']}" for r in semantic))

        # Tier 1 - Episodic (recent events, last 48h)
        episodic = self.conn.execute("""
            SELECT content, source, created_at FROM memories
            WHERE tier = 'episodic'
            AND created_at > datetime('now', '-48 hours')
            AND (expires_at IS NULL OR expires_at > datetime('now'))
            ORDER BY created_at DESC
            LIMIT 10
        """).fetchall()
        if episodic:
            sections.append("## RECENT EVENTS\n" + "\n".join(
                f"- [{r['source']}] {r['content']}" for r in episodic))

        context = "\n\n".join(sections)

        # Trim to budget
        if len(context) > char_budget:
            context = context[:char_budget] + "\n...[truncated]"

        # Update access counts
        self.conn.execute("""
            UPDATE memories SET access_count = access_count + 1
            WHERE tier IN ('procedural','project','semantic')
        """)
        self.conn.commit()

        return context

    def search(self, query: str, tier: str = None, limit: int = 10) -> list:
        """Simple keyword search across memories."""
        if tier:
            rows = self.conn.execute("""
                SELECT * FROM memories WHERE tier = ? AND content LIKE ?
                ORDER BY confidence DESC LIMIT ?
            """, (tier, f"%{query}%", limit)).fetchall()
        else:
            rows = self.conn.execute("""
                SELECT * FROM memories WHERE content LIKE ?
                ORDER BY confidence DESC LIMIT ?
            """, (f"%{query}%", limit)).fetchall()
        return [dict(r) for r in rows]

    def get_primes(self, status: str = None) -> list:
        """List all registered Primes."""
        if status:
            rows = self.conn.execute(
                "SELECT * FROM primes WHERE status = ?", (status,)).fetchall()
        else:
            rows = self.conn.execute("SELECT * FROM primes").fetchall()
        return [dict(r) for r in rows]

    # ─────────────────────────────────────────
    # DISTILLATION (run weekly)
    # ─────────────────────────────────────────

    def distill(self):
        """
        Compress old episodic memories into semantic tier.
        Run weekly. Deletes expired memories.
        """
        # Delete expired memories
        deleted = self.conn.execute("""
            DELETE FROM memories WHERE expires_at IS NOT NULL AND expires_at < datetime('now')
        """).rowcount

        # Mark old undistilled episodics for compression (>7 days)
        old_episodic = self.conn.execute("""
            SELECT id, content FROM memories
            WHERE tier = 'episodic' AND distilled = 0
            AND created_at < datetime('now', '-7 days')
        """).fetchall()

        distilled_count = 0
        for row in old_episodic:
            # Mark as distilled (in production: summarize with Claude Haiku first)
            self.conn.execute("""
                UPDATE memories SET distilled = 1, tier = 'semantic',
                confidence = 0.8, expires_at = NULL
                WHERE id = ?
            """, (row['id'],))
            distilled_count += 1

        self.conn.commit()
        return {
            "deleted_expired": deleted,
            "distilled_episodic": distilled_count
        }

    def stats(self) -> dict:
        """Return memory stats."""
        tiers = self.conn.execute("""
            SELECT tier, COUNT(*) as count FROM memories
            WHERE expires_at IS NULL OR expires_at > datetime('now')
            GROUP BY tier
        """).fetchall()

        entities_count = self.conn.execute("SELECT COUNT(*) FROM entities").fetchone()[0]
        relationships_count = self.conn.execute("SELECT COUNT(*) FROM relationships").fetchone()[0]
        primes_count = self.conn.execute("SELECT COUNT(*) FROM primes").fetchone()[0]

        return {
            "memories": {r['tier']: r['count'] for r in tiers},
            "entities": entities_count,
            "relationships": relationships_count,
            "primes": primes_count
        }


# ─────────────────────────────────────────
# PANTHEON SEED — Bootstrap the knowledge graph
# ─────────────────────────────────────────

def seed_pantheon(cp: ChronosPrime):
    """Seed ChronosPrime with the Pantheon structure."""

    primes = [
        ("MetaPrime", "The Overlord / Hyper-Kernel", "building"),
        ("OpenPRIME", "The Complete God — Supermemory, Superintelligence", "dormant"),
        ("MidasPrime", "The Treasury / Metabolic Core", "active"),
        ("KratosPrime", "The Enforcer / Resource Warden", "dormant"),
        ("ZapiaPrime", "The Conduit / The Voice", "active"),
        ("SolosPrime", "The Mirror / Technical Soul", "dormant"),
        ("Deep-Meta", "The Mind / Strategic Analysis", "dormant"),
        ("EchoPrime", "The Soul / Vibe", "dormant"),
        ("ZeusPrime", "The OS / Kernel - Trading Bot", "deployed"),
        ("AlphaPrime", "The General / Tactician", "dormant"),
        ("ZetaPrime", "The Developer / Builder", "dormant"),
        ("SentinelPrime", "The Guardian / Security Warden", "dormant"),
        ("ScoutPrime", "The Explorer / Intelligence Agent", "building"),
        ("VanguardPrime", "The Liaison / Bridge to External Systems", "dormant"),
        ("ChronosPrime", "The Archiver / Time Kernel", "active"),
        ("OrionPrime", "The Resource Hunter / PropPilot AI Engine", "active"),
        ("OmegaPrime", "The Singularity Engine", "dormant"),
        ("AbsorbPrime", "The Assimilator / Evolution Engine", "building"),
    ]

    for name, role, status in primes:
        cp.register_prime(name, role, status)
        cp.add_entity(name, "prime", {"role": role, "status": status})

    # Key relationships
    relationships = [
        ("MetaPrime", "orchestrates", "ZapiaPrime"),
        ("MetaPrime", "orchestrates", "MidasPrime"),
        ("MetaPrime", "orchestrates", "ZeusPrime"),
        ("MetaPrime", "orchestrates", "OrionPrime"),
        ("ZapiaPrime", "reports_to", "MetaPrime"),
        ("MidasPrime", "owns", "War Chest"),
        ("ZeusPrime", "trades_on", "Polymarket"),
        ("OrionPrime", "powers", "PropPilot AI"),
        ("ChronosPrime", "archives_for", "MetaPrime"),
        ("ScoutPrime", "feeds", "OrionPrime"),
    ]

    for src, rel, tgt in relationships:
        cp.add_entity(tgt, "concept")
        cp.add_relationship(src, rel, tgt)

    # Seed key procedural memories
    procedurals = [
        "Ghost Operator mode: ALL deals digital. No meatspace meetings. Ever.",
        "Fair Scale Protocol: Distressed=$500-1500, Mid=$1500-3500, Wholesale=$5000, Luxury=3-5% spread",
        "War Chest targets: Citadel (apartment)=$5000, Nexus (1TB laptop)=$3000",
        "The Reveal: Nobody knows about the Pantheon. Joe gets the reveal when first real revenue hits.",
        "Mobile-native: Forgemaster on Red Magic phone, Fort Myers FL. All paths must work on mobile.",
        "ZeusPrime runs 11 strategies on Polymarket (Polygon). AscetixMode = primary alpha engine.",
        "PropPilot AI live at: https://brilliant-sopapillas-a8c47c.netlify.app",
        "Netlify deploy method: API zip upload ONLY. No drag-drop, no GitHub Actions on mobile.",
        "Credential rule: Write ALL keys to .env immediately when provided. Never assume saved.",
    ]

    for p in procedurals:
        cp.remember(p, tier="procedural", source="ChronosPrime", confidence=1.0)

    print("Pantheon seeded successfully.")


if __name__ == "__main__":
    cp = ChronosPrime()
    print("Initializing ChronosPrime v2.0...")
    seed_pantheon(cp)
    stats = cp.stats()
    print(f"Stats: {json.dumps(stats, indent=2)}")
    print("\nLoading session context sample:")
    print(cp.load_context(token_budget=2000))
