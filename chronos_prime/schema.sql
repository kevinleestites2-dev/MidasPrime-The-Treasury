-- ============================================================
-- ChronosPrime v2.0 — Pantheon Memory Architecture
-- The Archiver / Time Kernel
-- Based on SuperSchema 4-Tier System
-- ============================================================

-- Core memory store
CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tier TEXT NOT NULL CHECK(tier IN ('episodic','semantic','project','procedural')),
    source TEXT NOT NULL,           -- which Prime wrote this
    content TEXT NOT NULL,
    metadata JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME,
    distilled BOOLEAN DEFAULT 0,
    confidence REAL DEFAULT 1.0,    -- 0.6=unverified, 0.9+=cross-referenced
    access_count INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_memories_tier ON memories(tier);
CREATE INDEX IF NOT EXISTS idx_memories_source ON memories(source);
CREATE INDEX IF NOT EXISTS idx_memories_distilled ON memories(distilled);
CREATE INDEX IF NOT EXISTS idx_memories_expires ON memories(expires_at);

-- Knowledge graph - entities
CREATE TABLE IF NOT EXISTS entities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL,             -- prime, project, person, tool, decision, concept, asset
    properties JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(type);

-- Knowledge graph - relationships
CREATE TABLE IF NOT EXISTS relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_entity INTEGER REFERENCES entities(id),
    target_entity INTEGER REFERENCES entities(id),
    relation_type TEXT NOT NULL,    -- works_on, depends_on, decided_by, uses, controls, reports_to, owns
    properties JSON,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_rel_source ON relationships(source_entity);
CREATE INDEX IF NOT EXISTS idx_rel_target ON relationships(target_entity);

-- Pantheon Prime registry
CREATE TABLE IF NOT EXISTS primes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    role TEXT NOT NULL,
    status TEXT DEFAULT 'dormant',  -- active, dormant, building, deployed
    repo_url TEXT,
    notes TEXT,
    last_active DATETIME
);

-- War Chest ledger (MidasPrime integration)
CREATE TABLE IF NOT EXISTS war_chest (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,       -- income, expense, milestone
    amount REAL,
    source TEXT,
    description TEXT,
    logged_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    balance_after REAL
);

-- Session log (episodic bootstrap)
CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    ended_at DATETIME,
    summary TEXT,
    key_decisions TEXT,
    primes_involved TEXT            -- JSON array
);
