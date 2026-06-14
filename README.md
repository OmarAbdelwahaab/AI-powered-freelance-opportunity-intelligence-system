# AI-Powered Freelance Opportunity Intelligence System

[![Status](https://img.shields.io/badge/status-live%20on%20Azure-brightgreen?style=flat-square)](https://azure.microsoft.com/)
[![n8n](https://img.shields.io/badge/n8n-self--hosted-FF6D5A?style=flat-square)](https://n8n.io/)
[![Database](https://img.shields.io/badge/Supabase-PostgreSQL-3ECF8E?style=flat-square&logo=supabase)](https://supabase.com/)
[![LLM](https://img.shields.io/badge/LLM-Google%20Gemini-4285F4?style=flat-square&logo=google)](https://ai.google.dev/)
[![Telegram](https://img.shields.io/badge/Notifications-Telegram%20Bot-26A5E4?style=flat-square&logo=telegram)](https://core.telegram.org/bots)

A **production-deployed** backend automation system that monitors multiple freelance platforms in real-time, normalizes heterogeneous API responses into a unified schema, applies multi-stage filtering, generates AI-powered bid proposals via LLM, and delivers human-in-the-loop alerts through a Telegram bot — all self-hosted on an Azure Linux VM.

---

## 📌 Problem

Manually checking multiple freelance platforms every few minutes to catch newly-posted, relevant jobs is impractical. Opportunities are time-sensitive: the earlier you bid, the higher your visibility. A human simply cannot be fast enough.

## ✅ Solution

A fully automated backend pipeline that:
1. Polls **Freelancer.com** and **Truelancer.com** REST APIs every **2 minutes**
2. Normalizes platform-specific JSON responses into a **Universal Schema**
3. Applies **multi-stage filtering** (skill matching + recency gate)
4. Generates a tailored **AI proposal** using Google Gemini Flash
5. Pushes a rich Telegram notification with interactive **Approve / Skip** inline buttons
6. Persists processed jobs in **Supabase (PostgreSQL)** for auditability

---

## 🏗️ System Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                     Azure Linux Server (self-hosted n8n)               │
│                                                                        │
│  ┌─────────────────┐                                                   │
│  │  Cron Trigger   │  Every 2 minutes                                  │ 
│  └────────┬────────┘                                                   │
│           │                                                            │
│    ┌──────┴──────────────────────────────────┐                         │
│    │           Parallel Ingestion             │                        │
│    │                                          │                        │
│  ┌─┴──────────────────┐  ┌───────────────────┴──┐                      │
│  │   Freelancer.com   │  │    Truelancer.com     │                     │
│  │    REST API        │  │      REST API         │                     │
│  │  /projects/active  │  │  /api/v1/projects     │                     │
│  └────────────────────┘  └───────────────────────┘                     │
│           │                          │                                 │
│  ┌────────▼──────────────────────────▼────────┐                        │
│  │           Data Normalization Layer           │                      │
│  │   Universal Schema: title, description,      │                      │
│  │   budget, url, platform, external_job_id,    │                      │
│  │   created_at (ISO 8601)                      │                      │
│  └──────────────────────┬─────────────────────┘                        │
│                         │                                              │
│              ┌──────────▼──────────┐                                   │
│              │     Merge Node      │  Combines both platform feeds     │
│              └──────────┬──────────┘                                   │
│                         │                                              │
│          ┌──────────────▼─────────────────┐                            │
│          │      Multi-Stage Filtering       │                          │
│          │  Stage A: Skill keyword match    │                          │
│          │  Stage B: Recency gate (<2 min)  │                          │
│          └──────────────┬─────────────────┘                            │
│                         │                                              │
│          ┌──────────────▼─────────────────┐                            │
│          │       Loop Over Items           │  Batch processing         │
│          └──┬───────────────────────────┬─┘                            │
│             │ (per item)                │                              │
│    ┌────────▼────────┐   ┌─────────────▼────────────┐                  │
│    │  Supabase Write │   │   Google Gemini LLM      │                  │
│    │  processed_jobs │   │   Generates AI proposal  │                  │
│    └─────────────────┘   └─────────────┬────────────┘                  │
│                                         │                              │
│                               ┌─────────▼─────────────┐                │
│                               │   Telegram Bot API    │                │ 
│                               │   Rich notification   │                │
│                               │   + Inline Buttons:   │                │
│                               │   ✅ Approve  ❌ Skip│                │
│                               └───────────────────────┘                │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Tech Stack

| Layer | Technology | Role |
|---|---|---|
| Orchestration | **n8n** (self-hosted) | Workflow engine & scheduler |
| Infrastructure | **Azure Linux VM** | Production hosting |
| Data Sources | **Freelancer.com API**, **Truelancer.com API** | Real-time job ingestion |
| AI / LLM | **Google Gemini Flash** | Proposal generation |
| Database | **Supabase (PostgreSQL)** | Job persistence & auditability |
| Notifications | **Telegram Bot API** | Human-in-the-loop approvals |
| Protocol | **REST / HTTP + JSON** | All external integrations |

---

## 🔄 Workflow Walkthrough (17 Nodes)

### Stage 1 — Scheduled Ingestion
A cron trigger fires every **2 minutes**, branching into two parallel REST API calls:

**Freelancer.com** — hits `/projects/active/` with skill category IDs pre-filtered for AI automation, Python, Node.js, and API integrations:
```
GET https://www.freelancer.com/api/projects/0.1/projects/active/
  ?limit=15
  &job_details=true
  &jobs[]=95      # Python
  &jobs[]=1977    # Node.js
  &jobs[]=2806    # n8n / automation
  &jobs[]=208     # APIs
  &jobs[]=1075    # AI / ML
  &t={timestamp}  # cache-busting
```

**Truelancer.com** — hits `/api/v1/projects` with relevant query parameters.

### Stage 2 — Data Normalization
Both APIs return different JSON shapes. Two `Edit Fields` nodes map each into a **platform-agnostic Universal Schema**, isolating all downstream logic from API-specific field names:

```json
{
  "Universal_Title":       "string",
  "Universal_Description": "string",
  "Universal_Budget":      "string (amount + currency code)",
  "Universal_URL":         "string (direct project link)",
  "Source_Platform":       "Freelancer | Truelancer",
  "External_Job_ID":       "string",
  "created_at":            "ISO 8601 datetime"
}
```

**Freelancer** conversion example:
```
$json.budget + $json.currency.code  →  Universal_Budget
new Date($json.submitdate * 1000).toISOString()  →  created_at
```

**Truelancer** uses different field names (`bid_stats.bid_avg`, `seo_url`) — the normalization layer absorbs this difference cleanly.

### Stage 3 — Merge
A `Merge` node combines both normalized streams into a single item list, enabling all downstream filtering and processing to be platform-agnostic.

### Stage 4 — Multi-Stage Filtering

**Filter A — Keyword Exclusion (Freelancer path)**
Drops jobs where the title contains `UGC` (not in scope). Applied before normalization for efficiency.

**Filter B — Skill Tag Exclusion (Truelancer path)**
Inspects the `skills` array of each job. Jobs tagged with out-of-scope categories are dropped:
```javascript
$json.skills.map(skill => skill.name).join(' | ')
// Excludes: Web Scraping, Data Entry, Lead Generation,
//           Advertising, Google Adwords, CRM
```

**Filter C — Recency Gate (Truelancer path)**
Only passes jobs posted within the last 2 minutes:
```javascript
$json.created_at > $now.minus({ minutes: 2 })
```
This prevents reprocessing the same listings on every poll cycle without requiring an expensive database lookup on the hot path. The 2-minute window matches the cron interval exactly.

### Stage 5 — AI Proposal Generation
Each matching job is passed to a **LLM Chain** (Google Gemini Flash) with a structured system prompt that enforces:
- No marketing buzzwords
- Stack-matched recommendations (if client mentions Make.com → propose Make.com, not n8n)
- A fixed 4-paragraph structure: Hook → Execution → Offer → Question
- Raw text output only (no markdown, no subject lines)

```
System: You are an expert AI Automation Engineer bidding on freelance projects...
User:   Write a proposal for: Title: {title} Description: {description}
```

### Stage 6 — Human-in-the-Loop Notification
A Telegram message is sent for every qualifying job, containing:
- Platform source
- Job title, description, and budget
- Direct link to apply
- The AI-generated proposal
- Two inline keyboard buttons with `callback_data` encoding the job ID:

```
✅ Approve & Bid  →  callback_data: "bid_{job_id}"
❌ Skip           →  callback_data: "skip_{job_id}"
```

A `Wait` node between iterations enforces a delay to avoid Telegram's rate limiter (30 messages/second per bot).

### Stage 7 — Persistence
Each processed job is written to Supabase (`processed_jobs` table) with all Universal Schema fields for auditability and future deduplication upgrades.

---

## 🗄️ Database Schema

```sql
CREATE TABLE processed_jobs (
  id              BIGSERIAL PRIMARY KEY,
  title           TEXT,
  platform        TEXT,               -- "Freelancer" or "Truelancer"
  external_job_id TEXT,               -- Platform's own job ID
  description     TEXT,
  budget          TEXT,
  url             TEXT,
  created_at      TIMESTAMPTZ
);
```

---

## 🚀 Setup & Deployment

### Prerequisites
- n8n instance (self-hosted via Docker or npm)
- [Supabase](https://supabase.com) project with the schema above
- [Google AI Studio](https://aistudio.google.com) API key
- Telegram Bot token (from [@BotFather](https://t.me/BotFather))
- Freelancer.com developer API key
- Truelancer.com API credentials

### 1. Clone the Repository
```bash
git clone https://github.com/OmarAbdelwahaab/AI-powered-freelance-opportunity-intelligence-system.git
cd AI-powered-freelance-opportunity-intelligence-system
```

### 2. Configure Environment Variables
```bash
cp .env.example .env
# Edit .env with your credentials
```

### 3. Deploy n8n (Docker)
```bash
docker run -d \
  --name n8n \
  -p 5678:5678 \
  -e N8N_ENCRYPTION_KEY=your_key \
  -v n8n_data:/home/node/.n8n \
  n8nio/n8n
```

### 4. Import the Workflow
1. Open your n8n instance at `http://localhost:5678`
2. Go to **Workflows → Import from File**
3. Select `workflow/freelance-intelligence.json`
4. Add credentials for: Freelancer API, Truelancer API, Google Gemini, Telegram Bot, Supabase
5. Set your Telegram Chat ID in the "Send a text message" node
6. **Activate** the workflow

---

## ⚙️ Environment Variables

See [`.env.example`](.env.example) for all required variables.

| Variable | Description |
|---|---|
| `N8N_ENCRYPTION_KEY` | n8n credential encryption key |
| `FREELANCER_API_KEY` | Freelancer.com developer API key |
| `TRUELANCER_API_KEY` | Truelancer.com API key |
| `GOOGLE_GEMINI_API_KEY` | Google AI Studio API key |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token from @BotFather |
| `TELEGRAM_CHAT_ID` | Your Telegram user/group chat ID |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anonymous API key |

---

## 🧠 Backend Engineering Concepts Demonstrated

| Concept | Implementation |
|---|---|
| **REST API Integration** | Consuming authenticated third-party APIs (Freelancer, Truelancer) with parameterized requests |
| **ETL Pipeline Design** | Extract → Transform (normalize) → Load pattern across two heterogeneous API schemas |
| **Data Normalization** | Platform-agnostic Universal Schema decouples ingestion from processing logic |
| **Scheduled Jobs** | Cron-style 2-minute polling using n8n's Schedule Trigger |
| **Deduplication Strategy** | Recency gate (time-window filter) avoids DB lookup on hot path; UNIQUE constraint on `external_job_id` as a safety net |
| **LLM API Integration** | Structured prompt engineering with system/user message separation; Google Gemini Flash |
| **Event-Driven Messaging** | Telegram Bot API with stateful `callback_data` for downstream action routing |
| **Batch Processing** | SplitInBatches loop with per-item rate-limit management via Wait node |
| **Multi-source Aggregation** | Parallel API calls merged into a single processing stream |
| **Cloud Deployment** | Production deployment on Azure Linux VM (self-hosted n8n) |
| **Database Design** | PostgreSQL schema via Supabase with appropriate field types for time-series job data |

---

## 📁 Repository Structure

```
├── workflow/
│   └── freelance-intelligence.json    # n8n workflow export (importable)
├── docs/
│   └── ARCHITECTURE.md                # Extended system design notes
├── .env.example                        # Environment variable template
└── README.md
```

---

## 🔮 Planned Improvements

- [ ] Webhook-based Telegram response handler to auto-submit bids on "Approve"
- [ ] Supabase-based deduplication lookup (replace recency filter for multi-instance safety)
- [ ] Upwork API as a third ingestion source
- [ ] Budget scoring model to rank opportunities by estimated value
- [ ] Slack / Discord as additional notification channels
- [ ] Unit tests for the normalization and filtering logic

---

## 👤 Author

**Omar Abdelwahab** · AI Automation Engineer · Cairo, Egypt

> This system is actively running in production on an Azure Linux server, processing job listings every 2 minutes and delivering real-time AI-generated proposals to a Telegram bot.
