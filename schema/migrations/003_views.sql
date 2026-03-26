-- ============================================================================
-- Sentinel System Database Views
-- Materialized views for optimized common queries
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Materialized View: session_summary_view
-- Description: Aggregated session statistics and metadata
-- Refresh Strategy: Refresh after session processing completes
-- ----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW session_summary_view AS
SELECT
    s.id AS session_id,
    s.user_id,
    u.username AS user_name,
    s.title,
    s.status,
    s.audio_duration_ms,
    s.actual_start_at,
    s.actual_end_at,
    s.created_at,

    -- Transcript statistics
    COUNT(DISTINCT t.id) AS transcript_count,
    SUM(array_length(regexp_split_to_array(t.text, '\s+'), 1)) AS total_words,
    COUNT(DISTINCT t.speaker_label) AS unique_speakers,
    MIN(t.start_ms) AS first_transcript_ms,
    MAX(t.end_ms) AS last_transcript_ms,

    -- Report availability
    r.id IS NOT NULL AS has_report,
    r.summary IS NOT NULL AND r.summary != '' AS has_summary,
    jsonb_array_length(r.key_points) AS key_points_count,

    -- Action item statistics
    COUNT(ai.id) AS total_action_items,
    COUNT(ai.id) FILTER (WHERE ai.status = 'PENDING') AS pending_action_items,
    COUNT(ai.id) FILTER (WHERE ai.status = 'COMPLETED') AS completed_action_items,
    COUNT(ai.id) FILTER (WHERE ai.status = 'OVERDUE') AS overdue_action_items,

    -- Participant count
    COUNT(DISTINCT sp.id) AS participant_count,

    -- Processing metrics
    EXTRACT(EPOCH FROM (s.asr_completed_at - s.asr_started_at)) * 1000 AS asr_processing_ms,
    EXTRACT(EPOCH FROM (s.llm_completed_at - s.llm_started_at)) * 1000 AS llm_processing_ms

FROM sessions s
LEFT JOIN users u ON s.user_id = u.id
LEFT JOIN transcripts t ON s.id = t.session_id
LEFT JOIN reports r ON s.id = r.session_id
LEFT JOIN action_items ai ON s.id = ai.session_id
LEFT JOIN session_participants sp ON s.id = sp.session_id
WHERE s.is_deleted = false
GROUP BY
    s.id, s.user_id, u.username, s.title, s.status, s.audio_duration_ms,
    s.actual_start_at, s.actual_end_at, s.created_at,
    s.asr_started_at, s.asr_completed_at, s.llm_started_at, s.llm_completed_at,
    r.id, r.summary, r.key_points
WITH DATA;

-- Create unique index on session_summary_view for refresh operations
CREATE UNIQUE INDEX idx_session_summary_view_session_id ON session_summary_view(session_id);

-- Create indexes for common query patterns
CREATE INDEX idx_session_summary_view_user_id ON session_summary_view(user_id);
CREATE INDEX idx_session_summary_view_status ON session_summary_view(status);
CREATE INDEX idx_session_summary_view_created_at ON session_summary_view(created_at DESC);

-- ----------------------------------------------------------------------------
-- Materialized View: user_dashboard_view
-- Description: User-specific dashboard data with aggregates
-- Refresh Strategy: Refresh periodically or on user action
-- ----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW user_dashboard_view AS
SELECT
    u.id AS user_id,
    u.username,
    u.full_name,
    u.role,
    u.plan,
    u.created_at AS user_created_at,

    -- Session statistics
    COUNT(DISTINCT s.id) FILTER (WHERE s.is_deleted = false) AS total_sessions,
    COUNT(DISTINCT s.id) FILTER (WHERE s.status = 'COMPLETED' AND s.is_deleted = false) AS completed_sessions,
    COUNT(DISTINCT s.id) FILTER (WHERE s.status IN ('ASR_PROCESSING', 'LLM_PROCESSING') AND s.is_deleted = false) AS processing_sessions,

    -- Audio statistics
    SUM(s.audio_duration_ms) FILTER (WHERE s.is_deleted = false) AS total_audio_duration_ms,
    AVG(s.audio_duration_ms) FILTER (WHERE s.is_deleted = false) AS avg_audio_duration_ms,

    -- Action item statistics
    COUNT(ai.id) FILTER (WHERE ai.assigned_to = u.id AND ai.status IN ('PENDING', 'IN_PROGRESS')) AS pending_action_items,
    COUNT(ai.id) FILTER (WHERE ai.assigned_to = u.id AND ai.status = 'OVERDUE') AS overdue_action_items,
    COUNT(ai.id) FILTER (WHERE ai.assigned_to = u.id AND ai.status = 'COMPLETED') AS completed_action_items,

    -- Notification statistics
    COUNT(n.id) FILTER (WHERE n.read_at IS NULL) AS unread_notifications,
    MAX(n.created_at) FILTER (WHERE n.read_at IS NULL) AS latest_notification_at,

    -- Chat statistics
    COUNT(DISTINCT cc.id) FILTER (WHERE cc.is_archived = false) AS active_chat_conversations,
    COUNT(DISTINCT cc.id) AS total_chat_conversations,
    SUM(cc.message_count) AS total_chat_messages,

    -- Storage statistics
    (SELECT COUNT(*) FROM embeddings e WHERE EXISTS (
        SELECT 1 FROM sessions s2 WHERE s2.id = e.session_id AND s2.user_id = u.id
    )) AS total_embeddings

FROM users u
LEFT JOIN sessions s ON u.id = s.user_id
LEFT JOIN action_items ai ON s.id = ai.session_id
LEFT JOIN notifications n ON u.id = n.user_id
LEFT JOIN chat_conversations cc ON u.id = cc.user_id
GROUP BY
    u.id, u.username, u.full_name, u.role, u.plan, u.created_at
WITH DATA;

-- Create unique index on user_dashboard_view
CREATE UNIQUE INDEX idx_user_dashboard_view_user_id ON user_dashboard_view(user_id);

-- ----------------------------------------------------------------------------
-- Materialized View: action_items_overdue_view
-- Description: Overdue and urgent action items tracking
-- Refresh Strategy: Refresh hourly or on action item change
-- ----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW action_items_overdue_view AS
SELECT
    ai.id AS action_item_id,
    ai.title,
    ai.description,
    ai.priority,
    ai.status,
    ai.due_date,
    ai.assigned_to,
    u.username AS assigned_to_name,
    u.email AS assigned_to_email,
    ai.session_id,
    s.title AS session_title,
    s.actual_end_at AS session_date,
    ai.overdue_notified,
    ai.created_at,

    -- Overdue calculation
    CURRENT_TIMESTAMP - ai.due_date AS overdue_duration,
    EXTRACT(DAY FROM CURRENT_TIMESTAMP - ai.due_date) AS overdue_days,

    -- Priority score for sorting
    CASE ai.priority
        WHEN 'URGENT' THEN 4
        WHEN 'HIGH' THEN 3
        WHEN 'MEDIUM' THEN 2
        WHEN 'LOW' THEN 1
    END AS priority_score

FROM action_items ai
JOIN users u ON ai.assigned_to = u.id
JOIN sessions s ON ai.session_id = s.id
WHERE
    ai.status IN ('PENDING', 'IN_PROGRESS', 'OVERDUE')
    AND (
        ai.due_date < CURRENT_TIMESTAMP
        OR ai.priority IN ('HIGH', 'URGENT')
    )
    AND ai.status != 'CANCELLED'
    AND s.is_deleted = false
WITH DATA;

-- Create indexes for overdue view
CREATE INDEX idx_action_items_overdue_view_assigned_to ON action_items_overdue_view(assigned_to);
CREATE INDEX idx_action_items_overdue_view_status ON action_items_overdue_view(status);
CREATE INDEX idx_action_items_overdue_view_priority_score ON action_items_overdue_view(priority_score DESC, due_date ASC);
CREATE INDEX idx_action_items_overdue_view_overdue_notified ON action_items_overdue_view(overdue_notified) WHERE overdue_notified = false;

-- ----------------------------------------------------------------------------
-- Materialized View: chat_conversation_summary_view
-- Description: Chat conversation metadata and statistics
-- Refresh Strategy: Refresh after new messages
-- ----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW chat_conversation_summary_view AS
SELECT
    cc.id AS conversation_id,
    cc.user_id,
    u.username AS user_name,
    cc.title,
    cc.mode,
    cc.message_count,
    cc.created_at,
    cc.last_message_at,
    cc.context_session_id,
    s.title AS context_session_title,

    -- First and last message info
    (SELECT cm.content FROM chat_messages cm WHERE cm.conversation_id = cc.id ORDER BY cm.created_at ASC LIMIT 1) AS first_message,
    (SELECT cm.content FROM chat_messages cm WHERE cm.conversation_id = cc.id ORDER BY cm.created_at DESC LIMIT 1) AS last_message,

    -- Tool usage statistics
    (SELECT COUNT(*) FROM chat_messages cm WHERE cm.conversation_id = cc.id AND cm.tool_calls IS NOT NULL AND jsonb_array_length(cm.tool_calls) > 0) AS tool_call_count,

    -- Average feedback score
    (SELECT AVG(cm.feedback_score) FROM chat_messages cm WHERE cm.conversation_id = cc.id AND cm.feedback_score IS NOT NULL) AS avg_feedback_score,

    -- RAG vs Agent breakdown
    COUNT(DISTINCT cm.id) FILTER (WHERE cm.role = 'USER') AS user_message_count,
    COUNT(DISTINCT cm.id) FILTER (WHERE cm.role = 'ASSISTANT') AS assistant_message_count,

    -- Token usage
    SUM(cm.prompt_tokens) FILTER (WHERE cm.prompt_tokens IS NOT NULL) AS total_prompt_tokens,
    SUM(cm.completion_tokens) FILTER (WHERE cm.completion_tokens IS NOT NULL) AS total_completion_tokens

FROM chat_conversations cc
JOIN users u ON cc.user_id = u.id
LEFT JOIN sessions s ON cc.context_session_id = s.id
LEFT JOIN chat_messages cm ON cc.id = cm.conversation_id
WHERE cc.is_archived = false
GROUP BY
    cc.id, cc.user_id, u.username, cc.title, cc.mode, cc.message_count,
    cc.created_at, cc.last_message_at, cc.context_session_id, s.title
WITH DATA;

-- Create indexes for chat conversation view
CREATE UNIQUE INDEX idx_chat_conversation_summary_view_conversation_id ON chat_conversation_summary_view(conversation_id);
CREATE INDEX idx_chat_conversation_summary_view_user_id ON chat_conversation_summary_view(user_id);
CREATE INDEX idx_chat_conversation_summary_view_mode ON chat_conversation_summary_view(mode);
CREATE INDEX idx_chat_conversation_summary_view_last_message ON chat_conversation_summary_view(last_message_at DESC);

-- ----------------------------------------------------------------------------
-- Materialized View: workflow_job_stats_view
-- Description: Workflow job processing statistics and health metrics
-- Refresh Strategy: Refresh every 5 minutes for monitoring
-- ----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW workflow_job_stats_view AS
SELECT
    -- Current time for reference
    CURRENT_TIMESTAMP AS stats_generated_at,

    -- Job counts by status
    COUNT(*) FILTER (WHERE status = 'PENDING') AS pending_jobs,
    COUNT(*) FILTER (WHERE status = 'RUNNING') AS running_jobs,
    COUNT(*) FILTER (WHERE status = 'COMPLETED') AS completed_jobs,
    COUNT(*) FILTER (WHERE status = 'FAILED') AS failed_jobs,
    COUNT(*) FILTER (WHERE status = 'RETRYING') AS retrying_jobs,

    -- Job counts by type
    COUNT(*) FILTER (WHERE job_type = 'ASR_REALTIME') AS asr_realtime_jobs,
    COUNT(*) FILTER (WHERE job_type = 'ASR_BATCH') AS asr_batch_jobs,
    COUNT(*) FILTER (WHERE job_type = 'LLM_SUMMARY') AS llm_summary_jobs,
    COUNT(*) FILTER (WHERE job_type = 'LLM_ACTION_ITEMS') AS llm_action_items_jobs,
    COUNT(*) FILTER (WHERE job_type = 'LLM_EMBEDDING') AS llm_embedding_jobs,
    COUNT(*) FILTER (WHERE job_type = 'CHAT_RAG') AS chat_rag_jobs,
    COUNT(*) FILTER (WHERE job_type = 'CHAT_AGENT') AS chat_agent_jobs,

    -- Average processing times (in milliseconds)
    AVG(EXTRACT(EPOCH FROM (completed_at - started_at)) * 1000) FILTER (WHERE job_type = 'ASR_BATCH' AND status = 'COMPLETED') AS avg_asr_batch_duration_ms,
    AVG(EXTRACT(EPOCH FROM (completed_at - started_at)) * 1000) FILTER (WHERE job_type = 'LLM_SUMMARY' AND status = 'COMPLETED') AS avg_llm_summary_duration_ms,
    AVG(EXTRACT(EPOCH FROM (completed_at - started_at)) * 1000) FILTER (WHERE job_type = 'LLM_EMBEDDING' AND status = 'COMPLETED') AS avg_llm_embedding_duration_ms,

    -- Failure rates
    CASE
        WHEN COUNT(*) FILTER (WHERE job_type = 'ASR_BATCH') > 0 THEN
            (COUNT(*) FILTER (WHERE job_type = 'ASR_BATCH' AND status = 'FAILED')::DECIMAL /
             COUNT(*) FILTER (WHERE job_type = 'ASR_BATCH') * 100)
        ELSE 0
    END AS asr_batch_failure_rate,

    CASE
        WHEN COUNT(*) FILTER (WHERE job_type = 'LLM_SUMMARY') > 0 THEN
            (COUNT(*) FILTER (WHERE job_type = 'LLM_SUMMARY' AND status = 'FAILED')::DECIMAL /
             COUNT(*) FILTER (WHERE job_type = 'LLM_SUMMARY') * 100)
        ELSE 0
    END AS llm_summary_failure_rate,

    -- Queue depth (jobs waiting)
    COUNT(*) FILTER (WHERE status IN ('PENDING', 'RETRYING')) AS queue_depth,

    -- Oldest pending job age
    CURRENT_TIMESTAMP - MIN(created_at) FILTER (WHERE status = 'PENDING') AS oldest_pending_job_age,

    -- Workers active (unique worker IDs)
    COUNT(DISTINCT worker_id) FILTER (WHERE status = 'RUNNING') AS active_workers

FROM workflow_jobs
WITH DATA;

-- ----------------------------------------------------------------------------
-- Regular View: session_transcript_flat_view
-- Description: Flattened view of sessions with transcript segments
-- Not materialized - used for ad-hoc queries
-- ----------------------------------------------------------------------------
CREATE VIEW session_transcript_flat_view AS
SELECT
    s.id AS session_id,
    s.user_id,
    s.title AS session_title,
    s.status AS session_status,
    s.actual_start_at,
    s.actual_end_at,
    t.id AS transcript_id,
    t.text AS transcript_text,
    t.start_ms,
    t.end_ms,
    t.speaker_label,
    sp.participant_name,
    sp.participant_email,
    t.confidence,
    t.language,
    -- Calculate timestamp relative to session start
    CASE
        WHEN s.actual_start_at IS NOT NULL THEN
            s.actual_start_at + (make_interval(secs => t.start_ms::FLOAT / 1000))
        ELSE NULL
    END AS absolute_timestamp
FROM sessions s
LEFT JOIN transcripts t ON s.id = t.session_id
LEFT JOIN session_participants sp ON t.participant_id = sp.id
WHERE s.is_deleted = false;

-- Create index on the view's underlying columns (through sessions table)
-- Note: Can't index views directly, but we index the base tables

-- ----------------------------------------------------------------------------
-- Regular View: user_activity_view
-- Description: User activity tracking and statistics
-- Not materialized - used for admin monitoring
-- ----------------------------------------------------------------------------
CREATE VIEW user_activity_view AS
SELECT
    u.id AS user_id,
    u.username,
    u.full_name,
    u.role,
    u.plan,
    u.is_active,
    u.last_login_at,
    u.last_login_ip,

    -- Recent activity counts (last 7 days)
    COUNT(DISTINCT s.id) FILTER (WHERE s.created_at > CURRENT_TIMESTAMP - INTERVAL '7 days' AND s.is_deleted = false) AS sessions_last_7_days,
    COUNT(DISTINCT cc.id) FILTER (WHERE cc.created_at > CURRENT_TIMESTAMP - INTERVAL '7 days') AS chats_last_7_days,
    COUNT(DISTINCT cm.id) FILTER (WHERE cm.created_at > CURRENT_TIMESTAMP - INTERVAL '7 days') AS messages_last_7_days,

    -- Total activity
    COUNT(DISTINCT s.id) FILTER (WHERE s.is_deleted = false) AS total_sessions,
    COUNT(DISTINCT cc.id) AS total_chats,
    SUM(cc.message_count) AS total_messages,

    -- Storage usage
    COALESCE(SUM(s.audio_duration_ms), 0) FILTER (WHERE s.is_deleted = false) AS total_audio_ms

FROM users u
LEFT JOIN sessions s ON u.id = s.user_id
LEFT JOIN chat_conversations cc ON u.id = cc.user_id
LEFT JOIN chat_messages cm ON cc.id = cm.conversation_id
GROUP BY
    u.id, u.username, u.full_name, u.role, u.plan, u.is_active,
    u.last_login_at, u.last_login_ip;

-- ----------------------------------------------------------------------------
-- Regular View: notification_aggregated_view
-- Description: Aggregated notifications by user and type
-- Not materialized - used for notification center queries
-- ----------------------------------------------------------------------------
CREATE VIEW notification_aggregated_view AS
SELECT
    n.user_id,
    n.type,
    COUNT(*) FILTER (WHERE n.status = 'PENDING' AND (n.expires_at IS NULL OR n.expires_at > CURRENT_TIMESTAMP)) AS pending_count,
    COUNT(*) FILTER (WHERE n.status = 'SENT' AND n.read_at IS NULL) AS sent_unread_count,
    COUNT(*) FILTER (WHERE n.read_at IS NULL) AS total_unread_count,
    MAX(n.created_at) AS latest_notification_at,
    MAX(n.created_at) FILTER (WHERE n.read_at IS NULL) AS latest_unread_at

FROM notifications n
WHERE
    (n.expires_at IS NULL OR n.expires_at > CURRENT_TIMESTAMP)
GROUP BY n.user_id, n.type;

-- ============================================================================
-- Refresh Functions for Materialized Views
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Function: refresh_session_summary()
-- Description: Refresh session_summary_view for a specific session
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_session_summary(p_session_id UUID DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    IF p_session_id IS NULL THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY session_summary_view;
    ELSE
        -- For single session, we'd need to refresh the whole view
        -- or implement incremental updates
        REFRESH MATERIALIZED VIEW CONCURRENTLY session_summary_view;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Function: refresh_user_dashboard()
-- Description: Refresh user_dashboard_view for a specific user
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_user_dashboard(p_user_id UUID DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY user_dashboard_view;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Function: refresh_all_views()
-- Description: Refresh all materialized views
-- Note: Run this during maintenance windows or low-traffic periods
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_all_views()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY session_summary_view;
    REFRESH MATERIALIZED VIEW CONCURRENTLY user_dashboard_view;
    REFRESH MATERIALIZED VIEW CONCURRENTLY action_items_overdue_view;
    REFRESH MATERIALIZED VIEW CONCURRENTLY chat_conversation_summary_view;
    REFRESH MATERIALIZED VIEW CONCURRENTLY workflow_job_stats_view;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Grant Permissions (if needed for specific users)
-- ============================================================================

-- Grant select on views to appropriate roles
-- GRANT SELECT ON session_summary_view TO normal_user;
-- GRANT SELECT ON user_dashboard_view TO normal_user;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO admin_user;

COMMIT;
