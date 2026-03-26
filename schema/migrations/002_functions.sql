-- ============================================================================
-- Sentinel System Database Functions
-- Utility functions for common operations
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Function: search_similar_content()
-- Description: Vector similarity search using pgvector for RAG
-- Parameters:
--   query_vector: The query embedding vector (1536 dimensions)
--   p_session_id: Optional session ID to filter results
--   p_content_type: Optional content type filter (transcript, report, action_item)
--   p_limit: Maximum number of results (default: 5)
--   p_threshold: Minimum similarity threshold 0-1 (default: 0.7)
-- Returns: Table of similar content chunks with metadata
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION search_similar_content(
    query_vector vector(1536),
    p_session_id UUID DEFAULT NULL,
    p_content_type VARCHAR DEFAULT NULL,
    p_limit INTEGER DEFAULT 5,
    p_threshold DECIMAL DEFAULT 0.7
)
RETURNS TABLE (
    id UUID,
    session_id UUID,
    content_type VARCHAR,
    source_id UUID,
    content TEXT,
    similarity DECIMAL,
    metadata JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id,
        e.session_id,
        e.content_type,
        e.source_id,
        e.content,
        (1 - (e.embedding <=> query_vector))::DECIMAL(3,2) AS similarity,
        e.metadata
    FROM embeddings e
    WHERE
        (p_session_id IS NULL OR e.session_id = p_session_id)
        AND (p_content_type IS NULL OR e.content_type = p_content_type)
        AND (e.embedding <=> query_vector) < (1 - p_threshold)
    ORDER BY e.embedding <=> query_vector
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- ----------------------------------------------------------------------------
-- Function: get_action_items_by_session()
-- Description: Query action items with various filters
-- Parameters:
--   p_user_id: User ID to filter assigned items
--   p_session_id: Optional session ID filter
--   p_status: Optional status filter
--   p_priority: Optional priority filter
--   p_include_overdue: Include overdue items (default: true)
-- Returns: Table of action items with session and user details
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_action_items_by_session(
    p_user_id UUID DEFAULT NULL,
    p_session_id UUID DEFAULT NULL,
    p_status action_status DEFAULT NULL,
    p_priority action_priority DEFAULT NULL,
    p_include_overdue BOOLEAN DEFAULT true
)
RETURNS TABLE (
    id UUID,
    title VARCHAR,
    description TEXT,
    priority action_priority,
    status action_status,
    assigned_to UUID,
    assigned_to_name VARCHAR,
    session_id UUID,
    session_title VARCHAR,
    due_date TIMESTAMP WITH TIME ZONE,
    is_overdue BOOLEAN,
    days_until_due INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ai.id,
        ai.title,
        ai.description,
        ai.priority,
        ai.status,
        ai.assigned_to,
        u.full_name AS assigned_to_name,
        ai.session_id,
        s.title AS session_title,
        ai.due_date,
        (ai.due_date < CURRENT_TIMESTAMP AND ai.status NOT IN ('COMPLETED', 'CANCELLED')) AS is_overdue,
        EXTRACT(DAY FROM (ai.due_date - CURRENT_TIMESTAMP))::INTEGER AS days_until_due
    FROM action_items ai
    LEFT JOIN users u ON ai.assigned_to = u.id
    LEFT JOIN sessions s ON ai.session_id = s.id
    WHERE
        (p_user_id IS NULL OR ai.assigned_to = p_user_id)
        AND (p_session_id IS NULL OR ai.session_id = p_session_id)
        AND (p_status IS NULL OR ai.status = p_status)
        AND (p_priority IS NULL OR ai.priority = p_priority)
        AND (p_include_overdue = true OR ai.status != 'OVERDUE')
        AND ai.status != 'CANCELLED'
    ORDER BY
        CASE ai.priority
            WHEN 'URGENT' THEN 1
            WHEN 'HIGH' THEN 2
            WHEN 'MEDIUM' THEN 3
            WHEN 'LOW' THEN 4
        END,
        ai.due_date ASC NULLS LAST,
        ai.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- ----------------------------------------------------------------------------
-- Function: notify_overdue_action_items()
-- Description: Find and notify overdue action items
-- Runs periodically to check for overdue items and create notifications
-- Returns: Number of notifications created
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_overdue_action_items()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_overdue_item RECORD;
BEGIN
    -- Find overdue items that haven't been notified
    FOR v_overdue_item IN
        SELECT ai.id, ai.assigned_to, ai.title, ai.session_id
        FROM action_items ai
        WHERE
            ai.due_date < CURRENT_TIMESTAMP
            AND ai.status IN ('PENDING', 'IN_PROGRESS')
            AND ai.overdue_notified = false
            AND ai.assigned_to IS NOT NULL
    LOOP
        -- Create notification
        INSERT INTO notifications (
            user_id,
            type,
            title,
            message,
            related_action_item_id,
            related_session_id,
            status,
            expires_at
        ) VALUES (
            v_overdue_item.assigned_to,
            'ACTION_OVERDUE',
            'Action Item Overdue',
            'Your action item "' || v_overdue_item.title || '" is now overdue.',
            v_overdue_item.id,
            v_overdue_item.session_id,
            'PENDING',
            CURRENT_TIMESTAMP + INTERVAL '7 days'
        );

        -- Mark as notified
        UPDATE action_items
        SET overdue_notified = true
        WHERE id = v_overdue_item.id;

        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Function: get_chat_history()
-- Description: Retrieve chat conversation history with context
-- Parameters:
--   p_conversation_id: Conversation ID
--   p_limit: Maximum number of messages (default: 50)
--   p_include_system: Include system messages (default: false)
-- Returns: Chat messages with referenced content
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_chat_history(
    p_conversation_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_include_system BOOLEAN DEFAULT false
)
RETURNS TABLE (
    id UUID,
    role message_role,
    content TEXT,
    tool_calls JSONB,
    referenced_sessions JSONB,
    referenced_transcripts JSONB,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        cm.id,
        cm.role,
        cm.content,
        cm.tool_calls,
        cm.referenced_sessions,
        cm.referenced_transcripts,
        cm.created_at
    FROM chat_messages cm
    WHERE
        cm.conversation_id = p_conversation_id
        AND (p_include_system = true OR cm.role != 'SYSTEM')
    ORDER BY cm.created_at ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- ----------------------------------------------------------------------------
-- Function: create_embedding_for_transcript()
-- Description: Create vector embedding for a transcript chunk
-- This is a placeholder - actual embedding generation happens in LLM service
-- Parameters:
--   p_session_id: Session ID
--   p_transcript_id: Transcript ID
--   p_content: Content to embed
--   p_embedding: The embedding vector (1536 dimensions)
-- Returns: The new embedding ID
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_embedding_for_transcript(
    p_session_id UUID,
    p_transcript_id UUID,
    p_content TEXT,
    p_embedding vector(1536)
)
RETURNS UUID AS $$
DECLARE
    v_embedding_id UUID;
BEGIN
    INSERT INTO embeddings (
        session_id,
        content_type,
        source_id,
        content,
        embedding,
        metadata
    ) VALUES (
        p_session_id,
        'transcript',
        p_transcript_id,
        p_content,
        p_embedding,
        jsonb_build_object(
            'transcript_id', p_transcript_id,
            'created_at', CURRENT_TIMESTAMP
        )
    )
    RETURNING id INTO v_embedding_id;

    RETURN v_embedding_id;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Function: batch_create_embeddings()
-- Description: Batch insert embeddings for efficiency
-- Parameters:
--   p_embeddings: Array of embedding records
-- Returns: Number of embeddings created
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TYPE embedding_record AS (
    session_id UUID,
    content_type VARCHAR,
    source_id UUID,
    content TEXT,
    embedding vector(1536),
    metadata JSONB
);

CREATE OR REPLACE FUNCTION batch_create_embeddings(
    p_embeddings embedding_record[]
)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_rec embedding_record;
BEGIN
    FOREACH v_rec IN ARRAY p_embeddings
    LOOP
        INSERT INTO embeddings (
            session_id,
            content_type,
            source_id,
            content,
            embedding,
            metadata
        ) VALUES (
            v_rec.session_id,
            v_rec.content_type,
            v_rec.source_id,
            v_rec.content,
            v_rec.embedding,
            v_rec.metadata
        );
        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Function: get_session_statistics()
-- Description: Aggregate statistics for a session
-- Parameters:
--   p_session_id: Session ID
-- Returns: Session statistics including word counts, duration, etc.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_session_statistics(
    p_session_id UUID
)
RETURNS TABLE (
    session_id UUID,
    total_transcripts INTEGER,
    total_words INTEGER,
    total_duration_ms INTEGER,
    unique_speakers INTEGER,
    average_confidence DECIMAL,
    processing_status session_status,
    asr_processing_time_ms BIGINT,
    llm_processing_time_ms BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id AS session_id,
        COUNT(t.id) AS total_transcripts,
        COALESCE(SUM(array_length(regexp_split_to_array(t.text, '\s+'), 1)), 0) AS total_words,
        s.audio_duration_ms,
        COUNT(DISTINCT t.speaker_label) AS unique_speakers,
        AVG(t.confidence) AS average_confidence,
        s.status AS processing_status,
        EXTRACT(EPOCH FROM (s.asr_completed_at - s.asr_started_at)) * 1000 AS asr_processing_time_ms,
        EXTRACT(EPOCH FROM (s.llm_completed_at - s.llm_started_at)) * 1000 AS llm_processing_time_ms
    FROM sessions s
    LEFT JOIN transcripts t ON s.id = t.session_id
    WHERE s.id = p_session_id
    GROUP BY s.id;
END;
$$ LANGUAGE plpgsql STABLE;

-- ----------------------------------------------------------------------------
-- Function: get_user_dashboard_summary()
-- Description: Get dashboard summary for a user
-- Parameters:
--   p_user_id: User ID
-- Returns: Dashboard summary with counts and recent items
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_user_dashboard_summary(
    p_user_id UUID
)
RETURNS TABLE (
    total_sessions INTEGER,
    completed_sessions INTEGER,
    pending_action_items INTEGER,
    overdue_action_items INTEGER,
    unread_notifications INTEGER,
    total_chat_conversations INTEGER,
    most_recent_session_date TIMESTAMP WITH TIME ZONE,
    storage_used_bytes BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(*) FROM sessions WHERE user_id = p_user_id AND is_deleted = false) AS total_sessions,
        (SELECT COUNT(*) FROM sessions WHERE user_id = p_user_id AND status = 'COMPLETED' AND is_deleted = false) AS completed_sessions,
        (SELECT COUNT(*) FROM action_items WHERE assigned_to = p_user_id AND status IN ('PENDING', 'IN_PROGRESS')) AS pending_action_items,
        (SELECT COUNT(*) FROM action_items WHERE assigned_to = p_user_id AND status = 'OVERDUE') AS overdue_action_items,
        (SELECT COUNT(*) FROM notifications WHERE user_id = p_user_id AND read_at IS NULL) AS unread_notifications,
        (SELECT COUNT(*) FROM chat_conversations WHERE user_id = p_user_id AND is_archived = false) AS total_chat_conversations,
        (SELECT MAX(actual_end_at) FROM sessions WHERE user_id = p_user_id AND is_deleted = false) AS most_recent_session_date,
        COALESCE(
            (SELECT SUM(audio_duration_ms * 16) / 8 FROM sessions WHERE user_id = p_user_id AND is_deleted = false),
            0
        ) AS storage_used_bytes; -- Rough estimate
END;
$$ LANGUAGE plpgsql STABLE;

-- ----------------------------------------------------------------------------
-- Function: cleanup_old_notifications()
-- Description: Clean up expired and read notifications older than specified days
-- Parameters:
--   p_days_old: Delete notifications older than this many days (default: 90)
-- Returns: Number of notifications deleted
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cleanup_old_notifications(
    p_days_old INTEGER DEFAULT 90
)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    DELETE FROM notifications
    WHERE
        (read_at IS NOT NULL AND read_at < CURRENT_TIMESTAMP - (p_days_old || ' days')::INTERVAL)
        OR (expires_at IS NOT NULL AND expires_at < CURRENT_TIMESTAMP);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Function: rebuild_embedding_index()
-- Description: Rebuild the IVFFlat vector index for better accuracy
-- Note: Should be run after significant data insertion
-- Returns: Success status
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rebuild_embedding_index()
RETURNS VARCHAR AS $$
BEGIN
    -- Drop existing index
    DROP INDEX IF EXISTS idx_embeddings_vector_ivfflat;

    -- Recreate with appropriate list count based on row count
    -- lists = sqrt(rows) is a good heuristic
    EXECUTE format(
        'CREATE INDEX idx_embeddings_vector_ivfflat ON embeddings
         USING ivfflat(embedding vector_cosine_ops)
         WITH (lists = %s)',
        (SELECT GREATEST(100, CAST(SQRT(COUNT(*)) AS INTEGER)) FROM embeddings)
    );

    RETURN 'Index rebuilt successfully';
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Function: get_transcript_by_timestamp()
-- Description: Get transcript segments for a time range
-- Parameters:
--   p_session_id: Session ID
--   p_start_ms: Start timestamp in milliseconds
--   p_end_ms: End timestamp in milliseconds
-- Returns: Transcript segments in the time range
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_transcript_by_timestamp(
    p_session_id UUID,
    p_start_ms INTEGER,
    p_end_ms INTEGER
)
RETURNS TABLE (
    id UUID,
    text TEXT,
    start_ms INTEGER,
    end_ms INTEGER,
    speaker_label VARCHAR,
    confidence DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id,
        t.text,
        t.start_ms,
        t.end_ms,
        t.speaker_label,
        t.confidence
    FROM transcripts t
    WHERE
        t.session_id = p_session_id
        AND (
            (t.start_ms >= p_start_ms AND t.start_ms < p_end_ms)
            OR (t.end_ms > p_start_ms AND t.end_ms <= p_end_ms)
            OR (t.start_ms <= p_start_ms AND t.end_ms >= p_end_ms)
        )
    ORDER BY t.start_ms;
END;
$$ LANGUAGE plpgsql STABLE;

-- ----------------------------------------------------------------------------
-- Function: create_audit_log()
-- Description: Helper function to create audit log entries
-- Parameters:
--   p_user_id: User ID performing the action
--   p_action_type: Type of action (CREATE, UPDATE, DELETE, etc.)
--   p_table_name: Table name affected
--   p_record_id: Record ID affected
--   p_before_value: JSON representation of before state
--   p_after_value: JSON representation of after state
-- Returns: The new audit log ID
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_audit_log(
    p_user_id UUID,
    p_action_type VARCHAR,
    p_table_name VARCHAR,
    p_record_id UUID,
    p_before_value JSONB DEFAULT NULL,
    p_after_value JSONB DEFAULT NULL,
    p_request_id VARCHAR DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_audit_id UUID;
    v_user_role user_role;
BEGIN
    -- Get user role for audit context
    SELECT role INTO v_user_role FROM users WHERE id = p_user_id;

    INSERT INTO audit_logs (
        user_id,
        user_role,
        action_type,
        table_name,
        record_id,
        before_value,
        after_value,
        request_id
    ) VALUES (
        p_user_id,
        v_user_role,
        p_action_type,
        p_table_name,
        p_record_id,
        p_before_value,
        p_after_value,
        p_request_id
    )
    RETURNING id INTO v_audit_id;

    RETURN v_audit_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Trigger Functions for Audit Logging
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Generic audit trigger function
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_trigger_func()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_before JSONB;
    v_after JSONB;
BEGIN
    -- Get current user from application context
    v_user_id := NULLIF(current_setting('app.current_user_id', true), '')::UUID;

    -- Build before/after JSON based on operation
    IF (TG_OP = 'DELETE') THEN
        v_before := to_jsonb(OLD);
        v_after := NULL;
    ELSIF (TG_OP = 'UPDATE') THEN
        v_before := to_jsonb(OLD);
        v_after := to_jsonb(NEW);
    ELSIF (TG_OP = 'INSERT') THEN
        v_before := NULL;
        v_after := to_jsonb(NEW);
    END IF;

    -- Create audit log entry
    INSERT INTO audit_logs (
        user_id,
        action_type,
        table_name,
        record_id,
        before_value,
        after_value
    ) VALUES (
        v_user_id,
        TG_OP,
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        v_before,
        v_after
    );

    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Performance Monitoring Functions
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Function: get_workflow_job_stats()
-- Description: Get workflow job statistics for monitoring
-- Returns: Job counts by type and status
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_workflow_job_stats()
RETURNS TABLE (
    job_type job_type,
    status job_status,
    job_count BIGINT,
    avg_duration_ms BIGINT,
    failure_rate DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        j.job_type,
        j.status,
        COUNT(*) AS job_count,
        AVG(EXTRACT(EPOCH FROM (j.completed_at - j.started_at)) * 1000)::BIGINT AS avg_duration_ms,
        CASE
            WHEN COUNT(*) > 0 THEN
                (COUNT(*) FILTER (WHERE j.status = 'FAILED')::DECIMAL / COUNT(*) * 100)
            ELSE 0
        END AS failure_rate
    FROM workflow_jobs j
    WHERE j.started_at IS NOT NULL
    GROUP BY j.job_type, j.status
    ORDER BY j.job_type, j.status;
END;
$$ LANGUAGE plpgsql STABLE;

-- ----------------------------------------------------------------------------
-- Function: get_storage_statistics()
-- Description: Get storage statistics for monitoring
-- Returns: Storage usage by entity type
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_storage_statistics()
RETURNS TABLE (
    entity_type VARCHAR,
    total_count BIGINT,
    total_size_bytes BIGINT,
    avg_size_bytes DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        'sessions'::VARCHAR AS entity_type,
        COUNT(*) AS total_count,
        COALESCE(SUM(audio_duration_ms * 16) / 8, 0)::BIGINT AS total_size_bytes,
        COALESCE(AVG(audio_duration_ms * 16) / 8, 0) AS avg_size_bytes
    FROM sessions
    WHERE is_deleted = false AND audio_duration_ms IS NOT NULL

    UNION ALL

    SELECT
        'transcripts'::VARCHAR,
        COUNT(*),
        COALESCE(SUM(octet_length(text)), 0)::BIGINT,
        COALESCE(AVG(octet_length(text)), 0)
    FROM transcripts

    UNION ALL

    SELECT
        'embeddings'::VARCHAR,
        COUNT(*),
        COALESCE(SUM(octet_length(content) + 1536 * 4), 0)::BIGINT, -- 1536 dims * 4 bytes (float32)
        COALESCE(AVG(octet_length(content) + 1536 * 4), 0)
    FROM embeddings;
END;
$$ LANGUAGE plpgsql STABLE;

COMMIT;
