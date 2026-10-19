const DB_NAME = "margen-pdf-local";
const STORE = "pdfs";
const VERSION = 1;

export const LOCAL_PDF_PREFIX = "local/";

export function isLocalPdfPath(path: string) {
  return path.startsWith(LOCAL_PDF_PREFIX);
}

export function localPdfKeyFromPath(path: string) {
  if (!isLocalPdfPath(path)) throw new Error("Ruta de PDF local inválida.");
  return path.slice(LOCAL_PDF_PREFIX.length);
}

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, VERSION);
    request.onerror = () => reject(request.error ?? new Error("No se pudo abrir el almacén local."));
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE);
    };
  });
}

export async function putLocalPdf(key: string, body: Blob | ArrayBuffer | File) {
  const db = await openDb();
  const blob = body instanceof Blob ? body : new Blob([body], { type: "application/pdf" });
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.oncomplete = () => {
      db.close();
      resolve();
    };
    tx.onerror = () => {
      db.close();
      reject(tx.error ?? new Error("No se pudo guardar el PDF en este navegador."));
    };
    tx.objectStore(STORE).put(blob, key);
  });
}

export async function getLocalPdfBlob(key: string) {
  const db = await openDb();
  return new Promise<Blob | null>((resolve, reject) => {
    const tx = db.transaction(STORE, "readonly");
    const request = tx.objectStore(STORE).get(key);
    request.onerror = () => {
      db.close();
      reject(request.error ?? new Error("No se pudo leer el PDF local."));
    };
    request.onsuccess = () => {
      db.close();
      const value = request.result;
      resolve(value instanceof Blob ? value : null);
    };
  });
}

export async function deleteLocalPdf(key: string) {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.oncomplete = () => {
      db.close();
      resolve();
    };
    tx.onerror = () => {
      db.close();
      reject(tx.error ?? new Error("No se pudo borrar el PDF local."));
    };
    tx.objectStore(STORE).delete(key);
  });
}

export async function localPdfObjectUrl(storagePath: string) {
  const blob = await getLocalPdfBlob(localPdfKeyFromPath(storagePath));
  if (!blob) {
    throw new Error(
      "El PDF solo estaba en este navegador y ya no está disponible. Vuelve a subirlo desde la biblioteca.",
    );
  }
  return URL.createObjectURL(blob);
}

export function formatFileSize(bytes: number) {
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function maxCloudPdfBytes() {
  const mb = Number(import.meta.env.VITE_MAX_PDF_CLOUD_MB);
  const limit = Number.isFinite(mb) && mb > 0 ? mb : 500;
  return limit * 1024 * 1024;
}

export function isStorageSizeError(error: { message?: string; statusCode?: string | number }) {
  const code = String(error.statusCode ?? "");
  const message = error.message ?? "";
  return code === "413" || /maximum allowed size|payload too large/i.test(message);
}
