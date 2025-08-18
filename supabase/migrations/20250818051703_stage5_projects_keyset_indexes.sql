-- Stage 5: Projects keyset pagination covering index
-- Rationale: Implements keyset/seek pagination for multi-tenant listing by covering filter and order-by columns.
-- Intended query shape:
--   SELECT id, stage_application, stage_application_created
--   FROM public.projects
--   WHERE tenant_id = ?
--   ORDER BY stage_application ASC, stage_application_created DESC, id DESC
-- This complements existing Stage 2 indexes and does not drop any.

CREATE INDEX IF NOT EXISTS ix_projects_tenant_stageapp_created_id_desc
ON public.projects (tenant_id, stage_application, stage_application_created DESC, id DESC);