CREATE TABLE processed_jobs (
    id BIGSERIAL PRIMARY KEY,
    platform TEXT NOT NULL,
    external_job_id TEXT NOT NULL,
    title TEXT,
    description TEXT,
    budget TEXT,
    url TEXT,
    created_at TIMESTAMP,
    processed_at TIMESTAMP DEFAULT NOW(),
    status TEXT DEFAULT 'new',

    UNIQUE(platform, external_job_id)
);
