import { getLocalPdfBlob, isLocalPdfPath, localPdfKeyFromPath } from "./pdfLocal";
import { requireSupabase } from "./supabase";

/** Copia en memoria del PDF; cada consumidor debe usar su propia copia (PDF.js puede invalidar el buffer). */
const masterCache = new Map<string, Promise<ArrayBuffer>>();

export function clearPdfBytesCache(storagePath?: string) {
  if (storagePath) masterCache.delete(storagePath);
  else masterCache.clear();
}

export function clonePdfBytes(data: ArrayBuffer) {
  return data.slice(0);
}

async function fetchMasterBytes(storagePath: string): Promise<ArrayBuffer> {
  if (isLocalPdfPath(storagePath)) {
    const blob = await getLocalPdfBlob(localPdfKeyFromPath(storagePath));
    if (!blob) {
      throw new Error(
        "El PDF solo estaba en este navegador y ya no está disponible. Vuelve a subirlo desde la biblioteca.",
      );
    }
    return blob.arrayBuffer();
  }
  const supabase = requireSupabase();
  const { data, error } = await supabase.storage.from("books").createSignedUrl(storagePath, 60 * 60);
  if (error || !data?.signedUrl) throw error ?? new Error("No se pudo abrir el PDF.");
  const response = await fetch(data.signedUrl);
  if (!response.ok) throw new Error("No se pudo descargar el PDF.");
  return response.arrayBuffer();
}

export async function loadPdfBytes(storagePath: string): Promise<ArrayBuffer> {
  let pending = masterCache.get(storagePath);
  if (!pending) {
    pending = fetchMasterBytes(storagePath);
    masterCache.set(storagePath, pending);
    pending.catch(() => masterCache.delete(storagePath));
  }
  const master = await pending;
  return clonePdfBytes(master);
}
