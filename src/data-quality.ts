export type Freshness = "fresh" | "stale" | "old";

export function daysOld(capturedAt: string, now: Date = new Date()): number {
  const captured = new Date(capturedAt);
  return Math.max(
    0,
    Math.floor((now.getTime() - captured.getTime()) / 86_400_000),
  );
}

export function freshnessFor(
  capturedAt: string,
  now: Date = new Date(),
): Freshness {
  const age = daysOld(capturedAt, now);
  if (age < 7) return "fresh";
  if (age <= 21) return "stale";
  return "old";
}
