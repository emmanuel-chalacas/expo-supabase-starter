import { supabase } from "@/config/supabase";

/**
 * Minimal storage helper for UploadAttachmentSheet.
 * Note: In production flows, uploads are typically authorized via an attachments_meta row (RLS).
 * This helper performs a direct Storage upload to the "attachments" bucket and returns a public URL.
 * If your Storage policies require metadata rows, this upload may fail until the data flow is updated.
 * TODO(Phase 7): unify with server-backed attachments pipeline and add telemetry.
 */

export type UploadAttachmentInput = {
  uri: string;
  name: string;
  type: string;
  size?: number;
};

export async function uploadAttachment(
  stage_application: string,
  file: UploadAttachmentInput,
): Promise<{ publicUrl?: string }> {
  // Sanitize name and build path: {stage_application}/{ts}-{name}
  const safeStage = encodeURIComponent(stage_application || "project");
  const safeName = String(file.name || "upload")
    .replace(/[^\w.\-]+/g, "_")
    .toLowerCase();
  const objectPath = `${safeStage}/${Date.now()}-${safeName}`;

  // Fetch blob from local URI
  const blob = await (await fetch(file.uri)).blob();

  // Upload to private bucket "attachments"
  const { error: upErr } = await supabase.storage
    .from("attachments")
    .upload(objectPath, blob, {
      contentType: file.type || "application/octet-stream",
      upsert: false,
    });

  if (upErr) {
    throw upErr;
  }

  // Public URL (if bucket has public access or signed transforms in place)
  const { data } = supabase.storage.from("attachments").getPublicUrl(objectPath);
  return { publicUrl: data?.publicUrl };
}