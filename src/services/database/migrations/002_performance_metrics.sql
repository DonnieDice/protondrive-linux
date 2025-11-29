-- Migration 002: Performance Metrics

CREATE TABLE IF NOT EXISTS performance_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    metric_name TEXT NOT NULL,
    value REAL NOT NULL,           -- e.g., duration in ms, memory in bytes
    unit TEXT NOT NULL,            -- e.g., 'ms', 'bytes', 'count'
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    context TEXT                   -- JSON string for additional context (e.g., component name, operation)
);

CREATE INDEX IF NOT EXISTS idx_performance_metrics_name ON performance_metrics(metric_name);
CREATE INDEX IF NOT EXISTS idx_performance_metrics_timestamp ON performance_metrics(timestamp);
