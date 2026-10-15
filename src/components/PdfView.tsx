import { useCallback, useEffect, useRef, useState, type MouseEvent, type PointerEvent as ReactPointerEvent } from "react";
import { locateQuote } from "../domain/quotes";
import { cropCanvasToDataUrl, normRectFromPoints } from "../domain/regionSelect";
import { groupItemsIntoLineSpans } from "../domain/textLayerLines";
import { rectsForRange, scaleRect, type NormRect } from "../domain/rects";
import { CATEGORY_LABELS } from "../domain/intensity";
import { recognizeCropDataUrl } from "../lib/regionOcr";
import { openPdfBytes } from "../lib/pdf";
import { loadPdfBytes } from "../lib/pdfLoad";
import type { Highlight, PageRow } from "../lib/types";

type Drawn = { highlight: Highlight; rects: NormRect[] };

type Props = {
  storagePath: string;
  pageNumber: number;
  zoom: number;
  page: PageRow | null;
  highlights: Highlight[];
  showAi: boolean;
  activeId?: string;
  selectionMode?: "text" | "capture";
  /** Solo recorte + OCR (páginas escaneadas). */
  captureOnly?: boolean;
  selectionRects?: NormRect[];
  selectionActive?: boolean;
  onSelect: (selection: { quote: string; rects: NormRect[]; x: number; y: number; previewUrl?: string } | null) => void;
  onHighlight: (highlight: Highlight, anchor: { x: number; y: number }) => void;
  onRegionBusy?: (busy: boolean) => void;
  /** Si se define, la página no superará este ancho (p. ej. ancho del stage en móvil). */
  fitMaxWidth?: number;
};

export function PdfView({
  storagePath,
  pageNumber,
  zoom,
  page,
  highlights,
  showAi,
  activeId,
  selectionMode = "capture",
  captureOnly = false,
  selectionRects,
  selectionActive,
  onSelect,
  onHighlight,
  onRegionBusy,
  fitMaxWidth,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const textRef = useRef<HTMLDivElement>(null);
  const sheetRef = useRef<HTMLDivElement>(null);
  const documentRef = useRef<{ key: string; pdf: ReturnType<typeof openPdfBytes> } | null>(null);
  const [renderError, setRenderError] = useState("");
  const [pdfReady, setPdfReady] = useState(false);
  const [marquee, setMarquee] = useState<NormRect | null>(null);
  const dragRef = useRef<{ x: number; y: number; active: boolean } | null>(null);
  const lastTextQuoteRef = useRef("");

  useEffect(() => {
    let active = true;
    setPdfReady(false);
    documentRef.current?.pdf.then((pdf) => pdf.destroy()).catch(() => undefined);
    documentRef.current = null;
    void loadPdfBytes(storagePath)
      .then((bytes) => {
        if (!active) return;
        documentRef.current = { key: storagePath, pdf: openPdfBytes(bytes) };
        setPdfReady(true);
      })
      .catch((reason) => {
        if (!active) return;
        setRenderError(reason instanceof Error ? reason.message : "No se pudo abrir el PDF.");
      });
    return () => { active = false; };
  }, [storagePath]);

  useEffect(() => {
    const canvas = canvasRef.current;
    const textLayer = textRef.current;
    if (!canvas || !textLayer || !pdfReady || !documentRef.current) return;
    let cancelled = false;
    const task = { current: null as { cancel: () => void } | null };
    const context = canvas.getContext("2d");
    if (!context) return;
    setRenderError("");

    const pdfPromise = documentRef.current.pdf;

    pdfPromise.then(async (pdf) => {
      if (cancelled) return;
      const pdfPage = await pdf.getPage(pageNumber);
      if (cancelled) return;
      const baseViewport = pdfPage.getViewport({ scale: 1 });
      const widthCap = fitMaxWidth && fitMaxWidth > 0
        ? Math.min(zoom, fitMaxWidth / baseViewport.width)
        : zoom;
      const viewport = pdfPage.getViewport({ scale: widthCap });
      const ratio = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.floor(viewport.width * ratio);
      canvas.height = Math.floor(viewport.height * ratio);
      canvas.style.width = `${viewport.width}px`;
      canvas.style.height = `${viewport.height}px`;
      const renderTask = pdfPage.render({
        canvasContext: context,
        viewport,
        transform: ratio === 1 ? undefined : [ratio, 0, 0, ratio, 0, 0],
      });
      task.current = renderTask;
      await renderTask.promise;
      if (cancelled) return;
      textLayer.replaceChildren();
      textLayer.style.width = `${viewport.width}px`;
      textLayer.style.height = `${viewport.height}px`;
      textLayer.style.pointerEvents = "none";
      const allowTextSelect = selectionMode === "text" && !captureOnly;
      const content = await pdfPage.getTextContent();
      let textSpans = 0;
      for (const item of content.items) {
        if (!item || typeof item !== "object" || !("str" in item) || !item.str) continue;
        const span = document.createElement("span");
        span.textContent = String(item.str);
        const transform = item.transform as number[];
        const tx = transformViewport(viewport.transform, transform);
        const height = Math.max(Math.hypot(tx[2], tx[3]), 1);
        span.style.left = `${tx[4]}px`;
        span.style.top = `${tx[5] - height}px`;
        span.style.fontSize = `${height}px`;
        span.style.pointerEvents = allowTextSelect ? "auto" : "none";
        textLayer.append(span);
        textSpans += 1;
      }
      if (textSpans === 0 && page?.items?.length) {
        if (allowTextSelect) {
          const lines = groupItemsIntoLineSpans(page.items);
          for (const line of lines) {
            const span = document.createElement("span");
            span.textContent = line.text;
            span.style.left = `${line.x * viewport.width}px`;
            span.style.top = `${line.y * viewport.height}px`;
            span.style.width = `${line.w * viewport.width}px`;
            span.style.height = `${line.h * viewport.height}px`;
            span.style.fontSize = `${Math.max(line.h * viewport.height, 11)}px`;
            span.style.lineHeight = "1.15";
            span.style.pointerEvents = "auto";
            textLayer.append(span);
            textSpans += 1;
          }
        }
      }
      if (captureOnly || selectionMode === "capture") {
        textLayer.style.pointerEvents = "none";
      } else if (textSpans > 0 && allowTextSelect) {
        textLayer.style.pointerEvents = "auto";
      }
    }).catch((reason) => {
      if (!cancelled) {
        textLayer.replaceChildren();
        setRenderError(reason instanceof Error ? reason.message : "No se pudo dibujar esta página.");
      }
    });

    return () => {
      cancelled = true;
      task.current?.cancel();
    };
  }, [pdfReady, storagePath, pageNumber, zoom, fitMaxWidth, page?.page_number, page?.items, selectionMode, captureOnly]);

  const commitTextSelection = useCallback(() => {
    if (selectionMode !== "text" || captureOnly) return;
    const sheet = sheetRef.current;
    const selection = window.getSelection();
    if (!sheet || !selection || selection.isCollapsed || !selection.anchorNode || !sheet.contains(selection.anchorNode)) {
      return;
    }
    const quote = selection.toString().replace(/\s+/g, " ").trim();
    if (quote.length < 12) {
      lastTextQuoteRef.current = "";
      return;
    }
    if (quote === lastTextQuoteRef.current) return;
    lastTextQuoteRef.current = quote;
    const hit = page?.text ? locateQuote(page.text, quote) : null;
    if (page?.text && !hit) return;
    const range = selection.getRangeAt(0);
    const box = sheet.getBoundingClientRect();
    let rects = [...range.getClientRects()].map((rect) => ({
      x: (rect.left - box.left) / box.width,
      y: (rect.top - box.top) / box.height,
      w: rect.width / box.width,
      h: rect.height / box.height,
    })).filter((rect) => rect.w > 0.002 && rect.h > 0.002);
    if (!rects.length && hit && page?.items?.length) {
      rects = rectsForRange(page.items, hit.start, hit.end);
    }
    const anchor = range.getBoundingClientRect();
    onSelect({ quote, rects, x: anchor.left, y: anchor.bottom + 8 });
  }, [captureOnly, onSelect, page, selectionMode]);

  useEffect(() => {
    if (selectionMode !== "text" || captureOnly) return;
    let timer = 0;
    const onSelectionChange = () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(() => commitTextSelection(), 350);
    };
    document.addEventListener("selectionchange", onSelectionChange);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener("selectionchange", onSelectionChange);
    };
  }, [captureOnly, commitTextSelection, selectionMode]);

  useEffect(() => {
    lastTextQuoteRef.current = "";
  }, [pageNumber, selectionMode, captureOnly]);

  useEffect(() => () => {
    documentRef.current?.pdf.then((pdf) => pdf.destroy()).catch(() => undefined);
  }, []);

  const drawn = drawHighlights(page, highlights, showAi);

  const clientToNorm = (clientX: number, clientY: number) => {
    const sheet = sheetRef.current;
    if (!sheet) return null;
    const box = sheet.getBoundingClientRect();
    return {
      x: (clientX - box.left) / box.width,
      y: (clientY - box.top) / box.height,
      box,
    };
  };

  const onPointerDown = (event: ReactPointerEvent) => {
    if (selectionMode !== "capture") return;
    if (event.button !== 0) return;
    const point = clientToNorm(event.clientX, event.clientY);
    if (!point) return;
    dragRef.current = { x: point.x, y: point.y, active: true };
    setMarquee(normRectFromPoints(point.x, point.y, point.x, point.y));
    sheetRef.current?.setPointerCapture(event.pointerId);
    event.preventDefault();
  };

  const onPointerMove = (event: ReactPointerEvent) => {
    if (!dragRef.current?.active) return;
    const point = clientToNorm(event.clientX, event.clientY);
    if (!point) return;
    setMarquee(normRectFromPoints(dragRef.current.x, dragRef.current.y, point.x, point.y));
  };

  const finishRegion = async (region: NormRect, anchorX: number, anchorY: number) => {
    const canvas = canvasRef.current;
    const previewUrl = canvas ? cropCanvasToDataUrl(canvas, region) ?? undefined : undefined;
    if (!previewUrl) {
      onSelect(null);
      return;
    }

    onRegionBusy?.(true);
    let quote = "";
    try {
      quote = await recognizeCropDataUrl(previewUrl);
    } catch {
      quote = "";
    } finally {
      onRegionBusy?.(false);
    }

    if (quote.replace(/\s+/g, " ").trim().length < 8) {
      onSelect(null);
      return;
    }

    onSelect({
      quote: quote.replace(/\s+/g, " ").trim(),
      rects: [region],
      x: anchorX,
      y: anchorY,
      previewUrl,
    });
  };

  const onPointerUp = (event: ReactPointerEvent) => {
    if (selectionMode === "capture" && dragRef.current?.active) {
      dragRef.current.active = false;
      const point = clientToNorm(event.clientX, event.clientY);
      const region = marquee;
      setMarquee(null);
      if (region && region.w > 0.01 && region.h > 0.01 && point) {
        void finishRegion(region, event.clientX, event.clientY);
      }
      return;
    }

    if (selectionMode === "text" && !captureOnly) {
      commitTextSelection();
    }
  };

  const onClick = (event: MouseEvent) => {
    if (selectionMode === "capture") return;
    const selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    const sheet = sheetRef.current;
    if (!sheet) return;
    const box = sheet.getBoundingClientRect();
    const x = (event.clientX - box.left) / box.width;
    const y = (event.clientY - box.top) / box.height;
    const hit = drawn.find((item) => item.rects.some((rect) => x >= rect.x && x <= rect.x + rect.w && y >= rect.y && y <= rect.y + rect.h));
    if (hit) onHighlight(hit.highlight, { x: event.clientX, y: event.clientY });
  };

  if (!pdfReady && !renderError) {
    return <p className="callout">Cargando vista del PDF…</p>;
  }

  return (
    <div
      className={`sheet${selectionMode === "capture" ? " capture-mode" : ""}`}
      ref={sheetRef}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={() => { dragRef.current = null; setMarquee(null); }}
      onClick={onClick}
    >
      {renderError ? <p className="callout bad">{renderError}</p> : null}
      {selectionMode === "capture" ? (
        <p className="region-hint muted">Modo captura: arrastra un rectángulo. Solo se lee lo que queda dentro — no el texto de al lado.</p>
      ) : null}
      <canvas ref={canvasRef} />
      <div className="marks" aria-hidden="true">
        {marquee ? (
          <span
            className="marquee-box"
            style={{
              left: `${marquee.x * 100}%`,
              top: `${marquee.y * 100}%`,
              width: `${marquee.w * 100}%`,
              height: `${marquee.h * 100}%`,
            }}
          />
        ) : null}
        {(selectionRects ?? []).map((rect, index) => (
          <span
            key={`sel-${index}`}
            className={`selection-mark${selectionActive ? " active" : ""}`}
            style={{
              left: `${rect.x * 100}%`,
              top: `${rect.y * 100}%`,
              width: `${rect.w * 100}%`,
              height: `${rect.h * 100}%`,
            }}
          />
        ))}
        {drawn.flatMap((item) => item.rects.map((rect, index) => {
          const box = scaleRect(rect, 100, 100);
          return (
            <span
              key={`${item.highlight.id}-${index}`}
              className={`mark${item.highlight.reviewed ? " reviewed" : ""}${item.highlight.id === activeId ? " active" : ""}`}
              style={{
                left: `${box.left}%`,
                top: `${box.top}%`,
                width: `${box.width}%`,
                height: `${box.height}%`,
                ["--hl" as string]: `var(--hl-${item.highlight.category})`,
              }}
              title={CATEGORY_LABELS[item.highlight.category]}
            />
          );
        }))}
      </div>
      <div ref={textRef} className="text-layer" />
    </div>
  );
}

function drawHighlights(page: PageRow | null, highlights: Highlight[], showAi: boolean): Drawn[] {
  return highlights.flatMap((highlight) => {
    if (highlight.dismissed) return [];
    if (highlight.origin === "ai" && !showAi) return [];
    if (!page || highlight.page_number !== page.page_number) return [];
    if (highlight.origin === "user" && highlight.rects?.length) {
      return [{ highlight, rects: highlight.rects }];
    }
    const hit = locateQuote(page.text, highlight.quote);
    if (!hit) return [];
    const rects = rectsForRange(page.items ?? [], hit.start, hit.end);
    if (!rects.length) return [];
    return [{ highlight, rects }];
  });
}

function transformViewport(viewportTransform: number[], itemTransform: number[]) {
  const [a1, b1, c1, d1, e1, f1] = viewportTransform;
  const [a2, b2, c2, d2, e2, f2] = itemTransform;
  return [
    a1 * a2 + c1 * b2,
    b1 * a2 + d1 * b2,
    a1 * c2 + c1 * d2,
    b1 * c2 + d1 * d2,
    a1 * e2 + c1 * f2 + e1,
    b1 * e2 + d1 * f2 + f1,
  ];
}
