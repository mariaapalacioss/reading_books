import { useMemo } from "react";
import { markdownToSafeHtml } from "../domain/markdown";

type Props = {
  source: string;
  className?: string;
  streaming?: boolean;
};

export function MarkdownContent({ source, className = "md-body", streaming }: Props) {
  const html = useMemo(() => markdownToSafeHtml(source), [source]);
  return (
    <div
      className={`${className}${streaming ? " streaming" : ""}`}
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}
