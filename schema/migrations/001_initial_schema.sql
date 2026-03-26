-- ============================================================================
-- Sentinel System Database Schema
-- On-Premise Meeting Intelligence Platform
-- PostgreSQL 16+ with pgvector extension
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgvector";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- ============================================================================
-- Custom ENUM Types
-- ============================================================================

-- User roles with hierarchical permissions
CREATE TYPE user_role AS ENUM ('NORMAL', 'ADMIN', 'ROOT');

-- User subscription plans
CREATE TYPE user_plan AS ENUM ('BASIC', 'MID');

-- Session processing status
CREATE TYPE session_status AS ENUM (
    'PENDING',       -- Awaiting processing
    'RECORDING',     -- Currently recording
    'UPLOADING',     -- Uploading to server
    'ASR_PROCESSING',-- ASR in progress
    'LLM_PROCESSING',-- LLM analysis in progress
    'COMPLETED',     -- Fully processed
    'FAILED'         -- Processing failed
);

-- Action item priority levels
CREATE TYPE action_priority AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'URGENT');

-- Action item completion status
CREATE TYPE action_status AS ENUM ('PENDING', 'IN_PROGRESS', 'COMPLETED', 'OVERDUE', 'CANCELLED');

-- Chat mode types
CREATE TYPE chat_mode AS ENUM ('RAG', 'AGENT');

-- Message role in conversation
CREATE TYPE message_role AS ENUM ('USER', 'ASSISTANT', 'SYSTEM');

-- Workflow job types
CREATE TYPE job_type AS ENUM (
    'ASR_REALTIME',      -- Real-time ASR processing
    'ASR_BATCH',         -- Batch ASR processing
    'LLM_SUMMARY',       -- LLM summary generation
    'LLM_ACTION_ITEMS',  -- Action item extraction
    'LLM_EMBEDDING',     -- Vector embedding generation
    'CHAT_RAG',          -- RAG chat query
    'CHAT_AGENT'         -- Agent chat query
);

-- Workflow job status
CREATE TYPE job_status AS ENUM (
    'PENDING',
    'RUNNING',
    'COMPLETED',
    'FAILED',
    'CANCELLED',
    'RETRYING'
);

-- Notification types
CREATE TYPE notification_type AS ENUM (
    'SESSION_COMPLETE',
    'REPORT_READY',
    'ACTION_ASSIGNED',
    'ACTION_OVERDUE',
    'SYSTEM_ALERT',
    'PROCESSING_FAILED'
);

-- Notification delivery status
CREATE TYPE notification_status AS ENUM ('PENDING', 'SENT', 'DELIVERED', 'FAILED');

-- ============================================================================
-- Core Tables
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: users
-- Description: User authentication and authorization
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    role user_role NOT NULL DEFAULT 'NORMAL',
    plan user_plan NOT NULL DEFAULT 'BASIC',
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_login_at TIMESTAMP WITH TIME ZONE,
    last_login_ip INET,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Indexes for users
CREATE INDEX idx_users_username ON users(username) WHERE is_active = true;
CREATE INDEX idx_users_email ON users(email) WHERE is_active = true;
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_plan ON users(plan);
CREATE INDEX idx_users_last_login ON users(last_login_at DESC);

-- ----------------------------------------------------------------------------
-- Table: sessions
-- Description: Meeting session metadata and tracking
-- ----------------------------------------------------------------------------
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status session_status NOT NULL DEFAULT 'PENDING',

    -- Audio metadata
    audio_file_path VARCHAR(500),
    audio_duration_ms INTEGER,
    audio_format VARCHAR(20), -- mp3, wav, m4a, etc.

    -- Session mode
    is_scheduled BOOLEAN NOT NULL DEFAULT false,
    scheduled_start_at TIMESTAMP WITH TIME ZONE,
    scheduled_end_at TIMESTAMP WITH TIME ZONE,
    actual_start_at TIMESTAMP WITH TIME ZONE,
    actual_end_at TIMESTAMP WITH TIME ZONE,

    -- Processing timestamps
    asr_started_at TIMESTAMP WITH TIME ZONE,
    asr_completed_at TIMESTAMP WITH TIME ZONE,
    llm_started_at TIMESTAMP WITH TIME ZONE,
    llm_completed_at TIMESTAMP WITH TIME ZONE,

    -- Statistics
    transcript_word_count INTEGER DEFAULT 0,
    participant_count INTEGER DEFAULT 0,

    -- Soft delete
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    deleted_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for sessions
CREATE INDEX idx_sessions_user_id ON sessions(user_id) WHERE is_deleted = false;
CREATE INDEX idx_sessions_status ON sessions(status) WHERE is_deleted = false;
CREATE INDEX idx_sessions_created_at ON sessions(created_at DESC) WHERE is_deleted = false;
CREATE INDEX idx_sessions_scheduled_start ON sessions(scheduled_start_at) WHERE is_scheduled = true AND is_deleted = false;
CREATE INDEX idx_sessions_actual_range ON sessions(actual_start_at, actual_end_at) WHERE is_deleted = false;

-- ----------------------------------------------------------------------------
-- Table: session_participants
-- Description: Many-to-many relationship between sessions and participants
-- ----------------------------------------------------------------------------
CREATE TABLE session_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- NULL for external participants
    speaker_label VARCHAR(50), -- Speaker_A, Speaker_B, etc. from ASR
    participant_name VARCHAR(100) NOT NULL,
    participant_email VARCHAR(255),

    -- Participation timestamps
    joined_at TIMESTAMP WITH TIME ZONE,
    left_at TIMESTAMP WITH TIME ZONE,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Ensure unique speaker label per session
    CONSTRAINT unique_speaker_label UNIQUE (session_id, speaker_label)
);

-- Indexes for session_participants
CREATE INDEX idx_session_participants_session_id ON session_participants(session_id);
CREATE INDEX idx_session_participants_user_id ON session_participants(user_id);

-- ----------------------------------------------------------------------------
-- Table: transcripts
-- Description: ASR output with timestamps and speaker labels
-- Supports full-text search and GIN indexing
-- ----------------------------------------------------------------------------
CREATE TABLE transcripts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,

    -- Transcript content
    text TEXT NOT NULL,

    -- Timestamp (milliseconds from session start)
    start_ms INTEGER NOT NULL,
    end_ms INTEGER NOT NULL,

    -- Speaker identification
    speaker_label VARCHAR(50),
    participant_id UUID REFERENCES session_participants(id) ON DELETE SET NULL,

    -- ASR metadata
    confidence DECIMAL(5,4), -- 0.0000 to 1.0000
    language VARCHAR(10) DEFAULT 'zh-TW',

    -- Search optimization
    text_tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', text)) STORED,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Ensure chronological order per session
    CONSTRAINT valid_timestamps CHECK (end_ms > start_ms)
);

-- Indexes for transcripts
CREATE INDEX idx_transcripts_session_id ON transcripts(session_id);
CREATE INDEX idx_transcripts_timestamps ON transcripts(session_id, start_ms, end_ms);
CREATE INDEX idx_transcripts_speaker ON transcripts(speaker_label);
CREATE INDEX idx_transcripts_text_search ON transcripts USING GIN(text_tsv);

-- ----------------------------------------------------------------------------
-- Table: reports
-- Description: LLM-generated meeting summaries
-- One-to-one relationship with sessions
-- ----------------------------------------------------------------------------
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL UNIQUE REFERENCES sessions(id) ON DELETE CASCADE,

    -- Summary content
    summary TEXT NOT NULL,
    key_points JSONB DEFAULT '[]'::jsonb, -- Array of key point objects
    topics JSONB DEFAULT '[]'::jsonb, -- Array of topic strings

    -- LLM processing metadata
    model_name VARCHAR(100),
    model_version VARCHAR(50),
    prompt_tokens INTEGER,
    completion_tokens INTEGER,
    total_tokens INTEGER,

    -- Export formats
    export_format VARCHAR(20), -- pdf, docx, markdown
    export_path VARCHAR(500),

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for reports
CREATE INDEX idx_reports_session_id ON reports(session_id);
CREATE INDEX idx_reports_created_at ON reports(created_at DESC);
CREATE INDEX idx_reports_key_points ON reports USING GIN(key_points);
CREATE INDEX idx_reports_topics ON reports USING GIN(topics);

-- ----------------------------------------------------------------------------
-- Table: action_items
-- Description: Tasks extracted from meetings by LLM
-- ----------------------------------------------------------------------------
CREATE TABLE action_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    report_id UUID REFERENCES reports(id) ON DELETE SET NULL,

    -- Action item details
    title VARCHAR(255) NOT NULL,
    description TEXT,
    priority action_priority NOT NULL DEFAULT 'MEDIUM',
    status action_status NOT NULL DEFAULT 'PENDING',

    -- Assignment
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Due dates
    due_date TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    overdue_notified BOOLEAN NOT NULL DEFAULT false,

    -- LLM extraction metadata
    extraction_confidence DECIMAL(5,4),
    extraction_context TEXT, -- Surrounding text that triggered extraction

    -- Metadata
    tags JSONB DEFAULT '{}'::jsonb,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_completion CHECK (
        (status = 'COMPLETED' AND completed_at IS NOT NULL) OR
        (status != 'COMPLETED')
    ),
    CONSTRAINT valid_overdue CHECK (
        (status = 'OVERDUE' AND due_date < CURRENT_TIMESTAMP) OR
        (status != 'OVERDUE')
    )
);

-- Indexes for action_items
CREATE INDEX idx_action_items_session_id ON action_items(session_id);
CREATE INDEX idx_action_items_assigned_to ON action_items(assigned_to) WHERE status != 'CANCELLED';
CREATE INDEX idx_action_items_status ON action_items(status);
CREATE INDEX idx_action_items_priority ON action_items(priority);
CREATE INDEX idx_action_items_due_date ON action_items(due_date) WHERE status IN ('PENDING', 'IN_PROGRESS');
CREATE INDEX idx_action_items_tags ON action_items USING GIN(tags);

-- Partial index for uncompleted action items
CREATE INDEX idx_action_items_pending ON action_items(assigned_to, status, due_date)
    WHERE status IN ('PENDING', 'IN_PROGRESS', 'OVERDUE');

-- ----------------------------------------------------------------------------
-- Table: chat_conversations
-- Description: Chat conversation containers for organizing messages
-- ----------------------------------------------------------------------------
CREATE TABLE chat_conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255),
    mode chat_mode NOT NULL DEFAULT 'RAG',

    -- Conversation metadata
    message_count INTEGER DEFAULT 0,
    last_message_at TIMESTAMP WITH TIME ZONE,

    -- Session context (optional - for session-specific chats)
    context_session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    context_action_item_ids JSONB DEFAULT '[]'::jsonb,

    is_archived BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for chat_conversations
CREATE INDEX idx_chat_conversations_user_id ON chat_conversations(user_id) WHERE is_archived = false;
CREATE INDEX idx_chat_conversations_mode ON chat_conversations(mode);
CREATE INDEX idx_chat_conversations_last_message ON chat_conversations(last_message_at DESC);
CREATE INDEX idx_chat_conversations_context_session ON chat_conversations(context_session_id);

-- ----------------------------------------------------------------------------
-- Table: chat_messages
-- Description: Individual chat messages with streaming support
-- ----------------------------------------------------------------------------
CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,

    -- Message content
    role message_role NOT NULL,
    content TEXT NOT NULL,

    -- Streaming metadata
    is_streaming BOOLEAN NOT NULL DEFAULT false,
    stream_started_at TIMESTAMP WITH TIME ZONE,
    stream_completed_at TIMESTAMP WITH TIME ZONE,

    -- LLM metadata
    model_name VARCHAR(100),
    prompt_tokens INTEGER,
    completion_tokens INTEGER,

    -- Tool calls (for Agent mode)
    tool_calls JSONB, -- Array of tool call objects

    -- Referenced context (for RAG mode)
    referenced_sessions JSONB DEFAULT '[]'::jsonb, -- Array of session IDs
    referenced_transcripts JSONB DEFAULT '[]'::jsonb, -- Array of transcript IDs with relevance scores
    similarity_threshold DECIMAL(3,2), -- 0.00 to 1.00

    -- Feedback
    feedback_score INTEGER, -- 1 to 5
    feedback_text TEXT,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for chat_messages
CREATE INDEX idx_chat_messages_conversation_id ON chat_messages(conversation_id);
CREATE INDEX idx_chat_messages_created_at ON chat_messages(created_at DESC);
CREATE INDEX idx_chat_messages_role ON chat_messages(role);
CREATE INDEX idx_chat_messages_tool_calls ON chat_messages USING GIN(tool_calls);
CREATE INDEX idx_chat_messages_referenced_sessions ON chat_messages USING GIN(referenced_sessions);

-- ----------------------------------------------------------------------------
-- Table: embeddings
-- Description: Vector embeddings for semantic search using pgvector
-- Supports chunking for large content
-- ----------------------------------------------------------------------------
CREATE TABLE embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,

    -- Source content
    content_type VARCHAR(20) NOT NULL, -- transcript, report, action_item
    source_id UUID NOT NULL, -- References the source record

    -- Chunk information (for splitting large content)
    chunk_index INTEGER DEFAULT 0,
    chunk_count INTEGER DEFAULT 1,
    parent_embedding_id UUID REFERENCES embeddings(id) ON DELETE CASCADE,

    -- Content and vector
    content TEXT NOT NULL,
    embedding vector(1536) NOT NULL, -- OpenAI embedding dimension

    -- Metadata for filtering
    metadata JSONB DEFAULT '{}'::jsonb,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for embeddings
CREATE INDEX idx_embeddings_session_id ON embeddings(session_id);
CREATE INDEX idx_embeddings_content_type ON embeddings(content_type);
CREATE INDEX idx_embeddings_source_id ON embeddings(source_id);

-- IVFFlat index for approximate nearest neighbor search
-- Create after inserting some data (lists = sqrt(rows))
CREATE INDEX idx_embeddings_vector_ivfflat ON embeddings
    USING ivfflat(embedding vector_cosine_ops)
    WITH (lists = 100);

-- ----------------------------------------------------------------------------
-- Table: workflow_jobs
-- Description: Async job tracking for ASR and LLM processing
-- ----------------------------------------------------------------------------
CREATE TABLE workflow_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_type job_type NOT NULL,
    status job_status NOT NULL DEFAULT 'PENDING',

    -- Job linkage
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    related_job_id UUID REFERENCES workflow_jobs(id) ON DELETE SET NULL, -- For job dependencies

    -- Progress tracking
    progress_percent INTEGER DEFAULT 0 CHECK (progress_percent BETWEEN 0 AND 100),
    current_step VARCHAR(100),
    total_steps INTEGER,

    -- Retry logic
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    last_retry_at TIMESTAMP WITH TIME ZONE,

    -- Execution metadata
    worker_id VARCHAR(100), -- Worker instance that processed the job
    queue_name VARCHAR(50), -- Temporal/BullMQ queue name
    workflow_id VARCHAR(100), -- Temporal workflow ID

    -- Input/output
    input_data JSONB,
    output_data JSONB,
    result_summary TEXT,

    -- Error handling
    error_message TEXT,
    error_stack TEXT,
    failed_at TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for workflow_jobs
CREATE INDEX idx_workflow_jobs_type_status ON workflow_jobs(job_type, status);
CREATE INDEX idx_workflow_jobs_session_id ON workflow_jobs(session_id);
CREATE INDEX idx_workflow_jobs_created_at ON workflow_jobs(created_at DESC);
CREATE INDEX idx_workflow_jobs_status ON workflow_jobs(status) WHERE status IN ('PENDING', 'RUNNING', 'RETRYING');
CREATE INDEX idx_workflow_jobs_retry ON workflow_jobs(created_at) WHERE status = 'FAILED' AND retry_count < max_retries;

-- ----------------------------------------------------------------------------
-- Table: notifications
-- Description: User notifications for system events
-- ----------------------------------------------------------------------------
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Notification details
    type notification_type NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,

    -- Related entities
    related_session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    related_action_item_id UUID REFERENCES action_items(id) ON DELETE SET NULL,
    related_job_id UUID REFERENCES workflow_jobs(id) ON DELETE SET NULL,

    -- Delivery tracking
    status notification_status NOT NULL DEFAULT 'PENDING',
    delivery_attempts INTEGER DEFAULT 0,
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    read_at TIMESTAMP WITH TIME ZONE,

    -- Expiry
    expires_at TIMESTAMP WITH TIME ZONE,

    -- Action URL
    action_url VARCHAR(500),

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_delivery CHECK (
        (status = 'DELIVERED' AND delivered_at IS NOT NULL) OR
        (status != 'DELIVERED')
    )
);

-- Indexes for notifications
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_status ON notifications(status);
CREATE INDEX idx_notifications_type ON notifications(type);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);

-- Partial index for unread notifications
CREATE INDEX idx_notifications_unread ON notifications(user_id, created_at DESC)
    WHERE read_at IS NULL AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP);

-- Partial index for pending delivery
CREATE INDEX idx_notifications_pending_delivery ON notifications(id, created_at)
    WHERE status = 'PENDING' AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP);

-- ----------------------------------------------------------------------------
-- Table: audit_logs
-- Description: Audit trail for debugging and Root user access
-- ----------------------------------------------------------------------------
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Actor
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    user_role user_role,
    action_ip INET,

    -- Action details
    action_type VARCHAR(50) NOT NULL, -- CREATE, UPDATE, DELETE, LOGIN, LOGOUT, etc.
    table_name VARCHAR(50),
    record_id UUID,
    action_description TEXT,

    -- State changes
    before_value JSONB,
    after_value JSONB,

    -- Request context
    request_id VARCHAR(100),
    user_agent TEXT,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for audit_logs (ready for partitioning by created_at)
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action_type ON audit_logs(action_type);
CREATE INDEX idx_audit_logs_table_record ON audit_logs(table_name, record_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);

-- ============================================================================
-- Functions and Triggers
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Function: update_updated_at_column()
-- Description: Automatically update updated_at timestamp on row modification
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to all relevant tables
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sessions_updated_at
    BEFORE UPDATE ON sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_reports_updated_at
    BEFORE UPDATE ON reports
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_action_items_updated_at
    BEFORE UPDATE ON action_items
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_chat_conversations_updated_at
    BEFORE UPDATE ON chat_conversations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_chat_messages_updated_at
    BEFORE UPDATE ON chat_messages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_workflow_jobs_updated_at
    BEFORE UPDATE ON workflow_jobs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ----------------------------------------------------------------------------
-- Function: update_overdue_action_items()
-- Description: Mark action items as overdue when due date passes
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_overdue_action_items()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.due_date < CURRENT_TIMESTAMP AND NEW.status IN ('PENDING', 'IN_PROGRESS') THEN
        NEW.status := 'OVERDUE';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply overdue trigger (fires on insert or update of due_date)
CREATE TRIGGER check_action_item_overdue
    BEFORE INSERT OR UPDATE OF due_date, status
    ON action_items
    FOR EACH ROW
    WHEN (NEW.due_date IS NOT NULL)
    EXECUTE FUNCTION update_overdue_action_items();

-- ----------------------------------------------------------------------------
-- Function: update_conversation_message_count()
-- Description: Update conversation message count and last message timestamp
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_conversation_message_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE chat_conversations
    SET message_count = message_count + 1,
        last_message_at = NEW.created_at
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply message count trigger on new messages
CREATE TRIGGER update_conversation_on_new_message
    AFTER INSERT ON chat_messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_message_count();

-- ============================================================================
-- Row Level Security (Optional - for multi-tenancy)
-- ============================================================================

-- Enable RLS on sensitive tables
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE transcripts ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE action_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- Users can only access their own data (except Admin and Root)
CREATE POLICY users_own_sessions ON sessions
    FOR ALL
    USING (
        user_id = current_setting('app.current_user_id')::uuid
        OR EXISTS (
            SELECT 1 FROM users
            WHERE id = current_setting('app.current_user_id')::uuid
            AND role IN ('ADMIN', 'ROOT')
        )
    );

CREATE POLICY users_own_transcripts ON transcripts
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM sessions
            WHERE sessions.id = transcripts.session_id
            AND (
                sessions.user_id = current_setting('app.current_user_id')::uuid
                OR EXISTS (
                    SELECT 1 FROM users
                    WHERE id = current_setting('app.current_user_id')::uuid
                    AND role IN ('ADMIN', 'ROOT')
                )
            )
        )
    );

-- Similar policies for reports, action_items, chat tables...

-- ============================================================================
-- Initial Data
-- ============================================================================

-- Create default Root user (password should be changed on first login)
INSERT INTO users (username, email, password_hash, full_name, role, plan)
VALUES (
    'root',
    'root@sentinel.local',
    '$2b$10$placeholder_hash_replace_on_deploy', -- Placeholder - use bcrypt in production
    'System Administrator',
    'ROOT',
    'MID'
) ON CONFLICT (username) DO NOTHING;

-- ============================================================================
-- Verification Queries
-- ============================================================================

-- Check all tables created
-- SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;

-- Verify indexes
-- SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' ORDER BY indexname;

-- Check ENUM types
-- SELECT typname FROM pg_type WHERE typtype = 'e';

-- Verify RLS policies
-- SELECT * FROM pg_policies WHERE schemaname = 'public';

COMMIT;
