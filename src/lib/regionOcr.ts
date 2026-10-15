/** OCR puntual de un recorte (página escaneada). */
export async function recognizeCropDataUrl(dataUrl: string): Promise<string> {
  const { createWorker } = await import("tesseract.js");
  const worker = await createWorker("spa+eng");
  try {
    const { data } = await worker.recognize(dataUrl);
    return (data.text ?? "").replace(/\s+/g, " ").trim();
  } finally {
    await worker.terminate();
  }
}
