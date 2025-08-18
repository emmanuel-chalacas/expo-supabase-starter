-- Stage 6: Keyset pagination verification (read-only)
-- Purpose:
--   Verify presence of the covering composite index for projects keyset ordering and
--   confirm the planner chooses an Index Scan for the representative list query.
-- Checks:
--   1) Presence check in pg_indexes (public.projects, ix_projects_tenant_stageapp_created_id_desc)
--   2) Plan check via EXPLAIN (FORMAT JSON) confirming an Index Scan is used and, when present,
--      the Index Name equals ix_projects_tenant_stageapp_created_id_desc for the query shape:
--        SELECT id, stage_application, stage_application_created
--        FROM public.projects
--        WHERE tenant_id = '00000000-0000-0000-0000-00000000t001'
--        ORDER BY stage_application ASC, stage_application_created DESC, id DESC
--        LIMIT 50;

WITH
idx AS (
  SELECT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'projects'
      AND indexname = 'ix_projects_tenant_stageapp_created_id_desc'
  ) AS index_exists
),
q AS (
  SELECT
    json_plan
  FROM (
    SELECT (EXPLAIN (FORMAT JSON)
      SELECT id, stage_application, stage_application_created
      FROM public.projects
      WHERE tenant_id = '00000000-0000-0000-0000-00000000t001'
      ORDER BY stage_application ASC, stage_application_created DESC, id DESC
      LIMIT 50
    ) AS json_plan
  ) s
),
root AS (
  SELECT (json_plan->0->'Plan') AS plan
  FROM q
),
scan_paths AS (
  SELECT
    plan->>'Node Type' AS root_node_type,
    plan->>'Index Name' AS root_index_name,
    (plan->'Plans'->0->>'Node Type') AS child0_node_type,
    (plan->'Plans'->0->>'Index Name') AS child0_index_name
  FROM root
),
plan_check AS (
  SELECT
    CASE
      WHEN lower(root_node_type) IN ('index scan','index only scan') THEN
        (root_index_name IS NULL OR root_index_name = 'ix_projects_tenant_stageapp_created_id_desc')
      WHEN lower(child0_node_type) IN ('index scan','index only scan') THEN
        (child0_index_name IS NULL OR child0_index_name = 'ix_projects_tenant_stageapp_created_id_desc')
      ELSE FALSE
    END AS plan_uses_index
  FROM scan_paths
)
SELECT
  idx.index_exists,
  pc.plan_uses_index,
  (idx.index_exists AND pc.plan_uses_index) AS ok
FROM idx
CROSS JOIN plan_check pc;