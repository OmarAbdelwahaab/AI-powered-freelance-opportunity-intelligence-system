# System Architecture — Deep Dive

## Overview

This document describes the system design decisions behind the AI-Powered Freelance Opportunity Intelligence System.

---

## Design Principles

### 1. Hot-Path Efficiency
The recency filter (`created_at > $now.minus({ minutes: 2 })`) is applied *before* hitting the database. This means the Supabase write and the Gemini API call are only triggered for genuinely new jobs, keeping per-cycle latency low and API costs minimal.

### 2. Schema Abstraction via Universal Schema
Both Freelancer.com and Truelancer.com return different JSON structures. Rather than letting platform-specific field names leak into downstream logic, all data is normalized at the earliest possible point into a single Universal Schema. This means:
- Filtering nodes reference `Universal_Title`, not `title` vs `name`
- The Gemini prompt template references `Universal_Description` regardless of which platform sourced the job
- Adding a third platform (e.g. Upwork) only requires adding a new `Edit Fields` node — nothing else changes

### 3. Human-in-the-Loop (HITL) as a First-Class Citizen
The system never auto-submits bids. Every qualifying job surfaces as a Telegram notification with Approve / Skip buttons. The `callback_data` encodes the job ID (`bid_{id}` / `skip_{id}`), making it straightforward to wire up a Telegram webhook handler that auto-submits the pre-generated proposal when the user taps "Approve."

### 4. Rate-Limit Respect
A `Wait` node is inserted between each Telegram message send. Telegram enforces a 30-message/second global rate limit per bot and a 20-message/minute limit per chat. Without this wait, bursts of qualifying jobs (e.g. 10 new jobs in one poll cycle) would cause 429 errors and dropped notifications.

---

## Data Flow

```
Cron (every 2 min)
    │
    ├─── Freelancer.com REST API ──► Split projects array
    │         │
    │         └─► Filter (keyword exclusion)
    │                   │
    │                   └─► Normalize → Universal Schema (Freelancer)
    │
    └─── Truelancer.com REST API ──► Split projects array
              │
              └─► Filter (recency gate: created_at > now - 2min)
                        │
                        └─► Filter (skill tag exclusion)
                                  │
                                  └─► Normalize → Universal Schema (Truelancer)

[Both streams] ──► Merge ──► Loop Over Items (batch size: 1)
                                   │
                                   ├─► Supabase INSERT (processed_jobs)
                                   │
                                   └─► Gemini Flash (proposal generation)
                                             │
                                             └─► Telegram Bot (notification + buttons)
                                                       │
                                                       └─► Wait ──► [next iteration]
```

---

## API Integration Details

### Freelancer.com
- **Endpoint**: `GET /api/projects/0.1/projects/active/`
- **Key params**:
  - `limit=15` — keeps each poll cycle lightweight
  - `job_details=true` — includes skill tag metadata inline
  - `jobs[]=<id>` — pre-filters by skill category IDs server-side (cheaper than client-side filtering)
  - `t={Date.now()}` — cache-busting parameter to ensure fresh results
- **Auth**: API key passed via HTTP header

### Truelancer.com
- **Endpoint**: `GET /api/v1/projects`
- **Auth**: API key in query parameters

---

## Filtering Logic

| Filter | Stage | Mechanism | Purpose |
|--------|-------|-----------|---------|
| Skill category IDs | API request | URL query params | Server-side filtering before data leaves Freelancer |
| Keyword exclusion | Post-split (Freelancer) | `title.toUpperCase().contains("UGC")` | Drop off-target project types |
| Skill tag exclusion | Post-split (Truelancer) | `skills.map(s => s.name).join(' \| ')` | Drop low-value categories |
| Recency gate | Post-split (Truelancer) | `created_at > $now.minus({minutes: 2})` | Deduplication without DB lookup |

---

## LLM Prompt Design

The Gemini prompt uses a **two-message structure**:

**System message** (persona + rules):
- Defines the role: "expert AI Automation Engineer bidding on freelance projects"
- Enforces anti-patterns to avoid (no buzzwords, no cross-tool pitching)
- Specifies exact output format (3-4 paragraphs, no markdown wrapper)
- Encodes a fixed value-add sentence that must appear verbatim in paragraph 3

**User message** (task):
```
Write a proposal for this job.
Title: {Universal_Title}
Description: {Universal_Description}
```

This separation allows the system prompt to be versioned and tested independently from the per-job input.

---

## Database Schema Rationale

```sql
CREATE TABLE processed_jobs (
  id              BIGSERIAL PRIMARY KEY,
  title           TEXT,
  platform        TEXT,
  external_job_id TEXT,       -- Not UNIQUE yet; planned for deduplication v2
  description     TEXT,
  budget          TEXT,       -- Stored as text to preserve currency string
  url             TEXT,
  created_at      TIMESTAMPTZ
);
```

**`budget` as TEXT**: Both platforms return budget in different formats (one as a number + separate currency object, one as a formatted string). Storing as normalized text (`"450 USD"`, `"1200 EGP"`) avoids lossy float conversion and preserves the currency label for display.

**`external_job_id` without UNIQUE constraint** (current): The recency gate handles deduplication on the hot path. A UNIQUE constraint is planned for v2 as a safety net for multi-instance deployments.

---

## Deployment

The system runs on an **Azure Linux VM** with n8n installed directly (not Dockerized in this configuration, to minimize overhead on a small VM tier). Key deployment considerations:

- **Process management**: n8n is managed via `pm2` to ensure it restarts on crash or reboot
- **Credential storage**: All API keys stored in n8n's encrypted credential vault (AES-256), not in environment files
- **Firewall**: Azure NSG rules restrict inbound traffic to port 5678 (n8n UI) from trusted IPs only
- **Monitoring**: n8n's built-in execution history provides audit logs for every workflow run

---

## Planned: Telegram Webhook Handler

Currently, the Approve / Skip buttons are instrumented (callback_data is set) but the receiving webhook is not yet implemented. The planned architecture:

```
User taps "✅ Approve & Bid"
    │
    └─► Telegram sends POST to webhook endpoint
              │
              └─► Parse callback_data ("bid_{job_id}")
                        │
                        └─► Lookup job in processed_jobs by external_job_id
                                  │
                                  └─► Submit proposal via platform API
                                            │
                                            └─► Confirm to user via Telegram
```

This will close the loop from intelligence (this system) to action (auto-bidding).
