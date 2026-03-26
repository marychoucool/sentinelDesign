# Sentinel Database Schema Documentation

On-Premise Meeting Intelligence Platform - PostgreSQL 16+ with pgvector

## Overview

The Sentinel database schema is designed to support a complete meeting intelligence platform that records, transcribes, analyzes, and enables semantic search of meeting content. The schema consists of **11 core tables** organized into **6 domains**:

1. **User Domain** - Authentication and authorization
2. **Session Domain** - Meeting recordings and processing
3. **Chat Domain** - Conversational AI interface
4. **Vector Domain** - Semantic search with pgvector
5. **Workflow Domain** - Async job processing
6. **Notification Domain** - User alerts and system events

---

## Table of Contents

- [Custom Types](#custom-types)
- [Core Tables](#core-tables)
- [Supporting Tables](#supporting-tables)
- [Relationship Diagram](#relationship-diagram)
- [Index Strategy](#index-strategy)
- [Query Patterns](#query-patterns)
- [Functions Reference](#functions-reference)
- [Views Reference](#views-reference)

---

## Custom Types

### User Roles
```sql
user_role: ENUM('NORMAL', 'ADMIN', 'ROOT')
```
- **NORMAL**: Regular users with Basic or Mid plan
- **ADMIN**: Dashboard access, system monitoring (no content access)
- **ROOT**: Full system access for debugging and development

### User Plans
```sql
user_plan: ENUM('BASIC', 'MID')
```
- **BASIC**: RAG chat only
- **MID**: RAG + Agent with tool calling

### Session Status
```sql
session_status: ENUM('PENDING', 'RECORDING', 'UPLOADING', 'ASR_PROCESSING',
                     'LLM_PROCESSING', 'COMPLETED', 'FAILED')
```

### Action Item Priority/Status
```sql
action_priority: ENUM('LOW', 'MEDIUM', 'HIGH', 'URGENT')
action_status: ENUM('PENDING', 'IN_PROGRESS', 'COMPLETED', 'OVERDUE', 'CANCELLED')
```

### Job Types/Status
```sql
job_type: ENUM('ASR_REALTIME', 'ASR_BATCH', 'LLM_SUMMARY', 'LLM_ACTION_ITEMS',
               'LLM_EMBEDDING', 'CHAT_RAG', 'CHAT_AGENT')
job_status: ENUM('PENDING', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED', 'RETRYING')
```

---

## Core Tables

### 1. users

Authentication and authorization table.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| username | VARCHAR(50) | Unique username |
| email | VARCHAR(255) | Unique email with validation |
| password_hash | VARCHAR(255) | Bcrypt hash |
| full_name | VARCHAR(100) | Display name |
| role | user_role | NORMAL/ADMIN/ROOT |
| plan | user_plan | BASIC/MID |
| is_active | BOOLEAN | Soft delete flag |
| last_login_at | TIMESTAMPTZ | Last login timestamp |
| last_login_ip | INET | Last login IP address |

**Indexes:**
- `idx_users_username` (partial, active users)
- `idx_users_email` (partial, active users)
- `idx_users_role`, `idx_users_plan`
- `idx_users_last_login` (descending)

---

### 2. sessions

Meeting session metadata and processing state.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| user_id | UUID | Foreign key to users |
| title | VARCHAR(255) | Meeting title |
| description | TEXT | Optional description |
| status | session_status | Processing state |
| audio_file_path | VARCHAR(500) | Local storage path |
| audio_duration_ms | INTEGER | Duration in milliseconds |
| audio_format | VARCHAR(20) | mp3, wav, m4a, etc. |
| is_scheduled | BOOLEAN | Pre-booked vs ad-hoc |
| scheduled_start_at | TIMESTAMPTZ | Planned start time |
| actual_start_at | TIMESTAMPTZ | Actual start time |
| asr_started_at | TIMESTAMPTZ | ASR processing start |
| asr_completed_at | TIMESTAMPTZ | ASR processing end |
| llm_started_at | TIMESTAMPTZ | LLM processing start |
| llm_completed_at | TIMESTAMPTZ | LLM processing end |
| is_deleted | BOOLEAN | Soft delete flag |

**Indexes:**
- `idx_sessions_user_id` (partial, not deleted)
- `idx_sessions_status` (partial, not deleted)
- `idx_sessions_created_at` (descending)
- `idx_sessions_scheduled_start` (partial, scheduled only)
- `idx_sessions_actual_range` (brin for time ranges)

---

### 3. session_participants

Many-to-many relationship for meeting participants.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| session_id | UUID | Foreign key to sessions |
| user_id | UUID | Foreign key to users (nullable) |
| speaker_label | VARCHAR(50) | ASR speaker identifier |
| participant_name | VARCHAR(100) | Display name |
| participant_email | VARCHAR(255) | Contact email |
| joined_at | TIMESTAMPTZ | Join timestamp |
| left_at | TIMESTAMPTZ | Leave timestamp |

**Constraints:**
- Unique `(session_id, speaker_label)`

---

### 4. transcripts

ASR output with timestamps for full-text search.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| session_id | UUID | Foreign key to sessions |
| text | TEXT | Transcribed content |
| start_ms | INTEGER | Start time (ms from session start) |
| end_ms | INTEGER | End time |
| speaker_label | VARCHAR(50) | Speaker identifier |
| participant_id | UUID | Foreign key to session_participants |
| confidence | DECIMAL(5,4) | ASR confidence score |
| language | VARCHAR(10) | Language code (default: zh-TW) |
| text_tsv | TSVECTOR | Generated full-text search vector |

**Indexes:**
- `idx_transcripts_session_id`
- `idx_transcripts_timestamps` (session_id, start_ms, end_ms)
- `idx_transcripts_speaker`
- `idx_transcripts_text_search` (GIN on text_tsv)

---

### 5. reports

LLM-generated meeting summaries.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| session_id | UUID | Foreign key to sessions (unique) |
| summary | TEXT | Meeting summary |
| key_points | JSONB | Array of key point objects |
| topics | JSONB | Array of topic strings |
| model_name | VARCHAR(100) | LLM model used |
| prompt_tokens | INTEGER | Input token count |
| completion_tokens | INTEGER | Output token count |
| total_tokens | INTEGER | Total tokens |
| export_format | VARCHAR(20) | pdf/docx/markdown |
| export_path | VARCHAR(500) | Export file path |

**Indexes:**
- `idx_reports_session_id` (unique)
- `idx_reports_created_at` (descending)
- `idx_reports_key_points` (GIN)
- `idx_reports_topics` (GIN)

---

### 6. action_items

Tasks extracted from meetings by LLM.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| session_id | UUID | Foreign key to sessions |
| report_id | UUID | Foreign key to reports |
| title | VARCHAR(255) | Task title |
| description | TEXT | Detailed description |
| priority | action_priority | LOW/MEDIUM/HIGH/URGENT |
| status | action_status | PENDING/IN_PROGRESS/COMPLETED/OVERDUE |
| assigned_to | UUID | Foreign key to users |
| created_by | UUID | Foreign key to users |
| due_date | TIMESTAMPTZ | Deadline |
| completed_at | TIMESTAMPTZ | Completion timestamp |
| overdue_notified | BOOLEAN | Notification sent flag |
| extraction_confidence | DECIMAL(5,4) | LLM confidence |
| extraction_context | TEXT | Source context |
| tags | JSONB | Flexible tagging |

**Indexes:**
- `idx_action_items_session_id`
- `idx_action_items_assigned_to` (partial, active)
- `idx_action_items_status`
- `idx_action_items_priority`
- `idx_action_items_due_date` (partial, pending)
- `idx_action_items_tags` (GIN)
- `idx_action_items_pending` (composite for dashboard)

**Triggers:**
- Auto-update status to OVERDUE when due_date passes

---

### 7. chat_conversations

Chat conversation containers.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| user_id | UUID | Foreign key to users |
| title | VARCHAR(255) | Conversation title |
| mode | chat_mode | RAG/AGENT |
| message_count | INTEGER | Total messages |
| last_message_at | TIMESTAMPTZ | Last activity |
| context_session_id | UUID | Optional session context |
| context_action_item_ids | JSONB | Related action items |
| is_archived | BOOLEAN | Archive flag |

**Indexes:**
- `idx_chat_conversations_user_id` (partial, active)
- `idx_chat_conversations_mode`
- `idx_chat_conversations_last_message` (descending)
- `idx_chat_conversations_context_session`

---

### 8. chat_messages

Individual chat messages with streaming support.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| conversation_id | UUID | Foreign key to chat_conversations |
| role | message_role | USER/ASSISTANT/SYSTEM |
| content | TEXT | Message content |
| is_streaming | BOOLEAN | Streaming flag |
| stream_started_at | TIMESTAMPTZ | Stream start |
| stream_completed_at | TIMESTAMPTZ | Stream end |
| model_name | VARCHAR(100) | LLM model |
| tool_calls | JSONB | Agent tool calls |
| referenced_sessions | JSONB | RAG context sessions |
| referenced_transcripts | JSONB | RAG context with scores |
| similarity_threshold | DECIMAL(3,2) | RAG threshold |
| feedback_score | INTEGER | User rating (1-5) |
| feedback_text | TEXT | User feedback |

**Indexes:**
- `idx_chat_messages_conversation_id`
- `idx_chat_messages_created_at` (descending)
- `idx_chat_messages_role`
- `idx_chat_messages_tool_calls` (GIN)
- `idx_chat_messages_referenced_sessions` (GIN)

**Triggers:**
- Auto-update conversation message_count

---

## Supporting Tables

### 9. embeddings

Vector embeddings for semantic search with pgvector.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| session_id | UUID | Foreign key to sessions |
| content_type | VARCHAR(20) | transcript/report/action_item |
| source_id | UUID | Source record ID |
| chunk_index | INTEGER | Chunk sequence |
| chunk_count | INTEGER | Total chunks |
| parent_embedding_id | UUID | Self-referencing |
| content | TEXT | Text content |
| embedding | vector(1536) | OpenAI embedding |
| metadata | JSONB | Flexible metadata |

**Indexes:**
- `idx_embeddings_session_id`
- `idx_embeddings_content_type`
- `idx_embeddings_source_id`
- `idx_embeddings_vector_ivfflat` (IVFFlat for cosine similarity)

---

### 10. workflow_jobs

Async job tracking for ASR and LLM processing.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| job_type | job_type | Job category |
| status | job_status | Processing state |
| session_id | UUID | Foreign key to sessions |
| related_job_id | UUID | Job dependency |
| progress_percent | INTEGER | 0-100 |
| current_step | VARCHAR(100) | Current step name |
| retry_count | INTEGER | Retry attempts |
| max_retries | INTEGER | Max retry limit |
| worker_id | VARCHAR(100) | Worker instance |
| queue_name | VARCHAR(50) | Queue name |
| workflow_id | VARCHAR(100) | Temporal workflow ID |
| input_data | JSONB | Job input |
| output_data | JSONB | Job output |
| error_message | TEXT | Error description |
| error_stack | TEXT | Stack trace |

**Indexes:**
- `idx_workflow_jobs_type_status` (composite)
- `idx_workflow_jobs_session_id`
- `idx_workflow_jobs_created_at` (descending)
- `idx_workflow_jobs_status` (partial, active)
- `idx_workflow_jobs_retry` (partial, retryable failures)

---

### 11. notifications

User notifications for system events.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| user_id | UUID | Foreign key to users |
| type | notification_type | Event type |
| title | VARCHAR(255) | Notification title |
| message | TEXT | Notification content |
| related_session_id | UUID | Context session |
| related_action_item_id | UUID | Context action item |
| related_job_id | UUID | Context job |
| status | notification_status | PENDING/SENT/DELIVERED/FAILED |
| delivery_attempts | INTEGER | Send attempts |
| sent_at | TIMESTAMPTZ | Sent timestamp |
| delivered_at | TIMESTAMPTZ | Delivery confirmation |
| read_at | TIMESTAMPTZ | Read timestamp |
| expires_at | TIMESTAMPTZ | Expiry time |
| action_url | VARCHAR(500) | Deep link |

**Indexes:**
- `idx_notifications_user_id`
- `idx_notifications_status`
- `idx_notifications_type`
- `idx_notifications_created_at` (descending)
- `idx_notifications_unread` (partial, unread)
- `idx_notifications_pending_delivery` (partial, pending)

---

### 12. audit_logs

Audit trail for debugging and Root access.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| user_id | UUID | Foreign key to users |
| user_role | user_role | Role at time of action |
| action_ip | INET | IP address |
| action_type | VARCHAR(50) | CREATE/UPDATE/DELETE/etc |
| table_name | VARCHAR(50) | Affected table |
| record_id | UUID | Affected record |
| action_description | TEXT | Description |
| before_value | JSONB | State before |
| after_value | JSONB | State after |
| request_id | VARCHAR(100) | Request identifier |
| user_agent | TEXT | Client user agent |

**Indexes:**
- `idx_audit_logs_user_id`
- `idx_audit_logs_action_type`
- `idx_audit_logs_table_record` (composite)
- `idx_audit_logs_created_at` (descending, ready for partitioning)

---

## Relationship Diagram

```
users (1) ----< (N) sessions
users (1) ----< (N) session_participants
users (1) ----< (N) action_items (assigned_to)
users (1) ----< (N) chat_conversations
users (1) ----< (N) notifications

sessions (1) ----< (N) session_participants
sessions (1) ----< (N) transcripts
sessions (1) ----|| (1) reports
sessions (1) ----< (N) action_items
sessions (1) ----< (N) embeddings
sessions (1) ----< (N) workflow_jobs
sessions (1) ----< (N) notifications

session_participants (1) ----< (N) transcripts
reports (1) ----< (N) action_items

chat_conversations (1) ----< (N) chat_messages

workflow_jobs (1) ----< (N) workflow_jobs (dependencies)
workflow_jobs (1) ----< (N) notifications

embeddings (1) ----< (N) embeddings (chunks)
```

---

## Index Strategy

### B-tree Indexes
- **Foreign keys**: All foreign key columns have B-tree indexes
- **Timestamps**: Descending indexes for time-based queries
- **Status columns**: Partial indexes for common filters (is_active, is_deleted)

### GIN Indexes
- **JSONB columns**: key_points, topics, tags, tool_calls, metadata
- **Full-text search**: text_tsv on transcripts for natural language queries

### IVFFlat Index (pgvector)
- **Vector similarity**: `idx_embeddings_vector_ivfflat` with cosine distance
- **Configuration**: 100 lists (adjust based on row count: sqrt(rows))

### Partial Indexes
- **Active data**: Only index non-deleted, active records
- **Unread notifications**: Optimize notification center queries
- **Pending jobs**: Workflow queue monitoring

---

## Query Patterns

### 1. User Dashboard Summary

```sql
SELECT * FROM user_dashboard_view WHERE user_id = $1;
```

Returns: Session counts, pending action items, unread notifications, storage usage

### 2. RAG Vector Search

```sql
SELECT * FROM search_similar_content(
    query_vector := $1,      -- Query embedding
    p_session_id := NULL,    -- Optional session filter
    p_content_type := NULL,  -- Optional type filter
    p_limit := 5,            -- Max results
    p_threshold := 0.7       -- Similarity threshold
);
```

Returns: Similar content chunks with similarity scores

### 3. Action Items by User

```sql
SELECT * FROM get_action_items_by_session(
    p_user_id := $1,
    p_status := NULL,
    p_include_overdue := true
);
```

Returns: User's action items with overdue status

### 4. Transcript by Time Range

```sql
SELECT * FROM get_transcript_by_timestamp(
    p_session_id := $1,
    p_start_ms := 0,
    p_end_ms := 60000
);
```

Returns: Transcript segments within time range

### 5. Chat History

```sql
SELECT * FROM get_chat_history(
    p_conversation_id := $1,
    p_limit := 50
);
```

Returns: Conversation messages in chronological order

---

## Functions Reference

### Vector Search

| Function | Description |
|----------|-------------|
| `search_similar_content()` | Semantic similarity search with pgvector |
| `create_embedding_for_transcript()` | Create single embedding |
| `batch_create_embeddings()` | Bulk insert embeddings |
| `rebuild_embedding_index()` | Rebuild IVFFlat index |

### Action Items

| Function | Description |
|----------|-------------|
| `get_action_items_by_session()` | Query with filters |
| `notify_overdue_action_items()` | Create overdue notifications |

### Chat

| Function | Description |
|----------|-------------|
| `get_chat_history()` | Retrieve conversation |
| `get_user_dashboard_summary()` | Dashboard aggregates |

### System

| Function | Description |
|----------|-------------|
| `get_session_statistics()` | Session metrics |
| `cleanup_old_notifications()` | Delete expired notifications |
| `create_audit_log()` | Create audit entry |
| `get_workflow_job_stats()` | Job monitoring |
| `get_storage_statistics()` | Storage usage |

---

## Views Reference

### Materialized Views

| View | Refresh Strategy | Use Case |
|------|------------------|----------|
| `session_summary_view` | After processing completes | Session list with stats |
| `user_dashboard_view` | Periodically/on action | User dashboard data |
| `action_items_overdue_view` | Hourly | Overdue tracking |
| `chat_conversation_summary_view` | After new messages | Chat list |
| `workflow_job_stats_view` | Every 5 minutes | Monitoring dashboard |

### Regular Views

| View | Use Case |
|------|----------|
| `session_transcript_flat_view` | Transcript queries with timestamps |
| `user_activity_view` | Admin monitoring |
| `notification_aggregated_view` | Notification center |

---

## Verification Queries

### Check All Tables

```sql
SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
```

Expected count: 12 tables

### Verify Indexes

```sql
SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' ORDER BY indexname;
```

Expected count: 40+ indexes

### Check ENUM Types

```sql
SELECT typname FROM pg_type WHERE typtype = 'e';
```

Expected: 9 custom ENUM types

### Test Vector Search

```sql
-- Requires sample embedding
SELECT * FROM search_similar_content(
    '[0.1, 0.2, ...]'::vector(1536),
    NULL,
    NULL,
    5,
    0.7
);
```

### Verify RLS Policies

```sql
SELECT * FROM pg_policies WHERE schemaname = 'public';
```

---

## Migration Files

| File | Description |
|------|-------------|
| `001_initial_schema.sql` | DDL: tables, types, indexes, triggers |
| `002_functions.sql` | Utility functions |
| `003_views.sql` | Materialized and regular views |

---

## ER Diagram

See `/Users/mary/code/sentinel/schema/diagram/erDiagram.mmd` for the complete Mermaid ER diagram.

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| **UUID primary keys** | Distributed system friendly, no ID collision |
| **pgvector(1536)** | Standard dimension for OpenAI embeddings |
| **IVFFlat index** | Approximate nearest neighbor, good for large datasets |
| **JSONB for flexibility** | Tool calls, metadata, participant summary |
| **Custom ENUMs** | Type safety for job_status, notification_type |
| **Partial indexes** | Optimize for common queries (unread, pending, active) |
| **Timestamp partitioning** | Ready for high-volume transcripts/audit logs |
| **RLS policies** | Multi-user data isolation at DB level |
| **Soft delete pattern** | `is_active` flag instead of hard deletes |

---

## Next Steps

1. **Review and validate** schema with stakeholders
2. **Test DDL execution** in PostgreSQL development environment
3. **Create seed data** for testing
4. **Implement application layer** (NestJS repositories)
5. **Set up CI/CD** for schema migrations
