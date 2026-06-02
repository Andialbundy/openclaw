import path from "node:path";

const OSV_ENDPOINT = "https://api.osv.dev/v1/query";
const OSV_TIMEOUT_MS = 10_000;

type OsvVuln = { id: string; summary?: string };

function inferEcosystem(command: string): "npm" | "PyPI" | null {
  const base = path
    .basename(command)
    .toLowerCase()
    .replace(/\.cmd$/, "");
  if (base === "npx") return "npm";
  if (base === "uvx" || base === "pipx") return "PyPI";
  return null;
}

function parseNpmPackage(token: string): { name: string; version?: string } {
  if (token.startsWith("@")) {
    const m = /^(@[^/]+\/[^@]+)(?:@(.+))?$/.exec(token);
    return m ? { name: m[1]!, version: m[2] ?? undefined } : { name: token };
  }
  const at = token.lastIndexOf("@");
  if (at > 0) {
    const ver = token.slice(at + 1);
    return { name: token.slice(0, at), version: ver === "latest" ? undefined : ver };
  }
  return { name: token };
}

function parsePypiPackage(token: string): { name: string; version?: string } {
  const m = /^([a-zA-Z0-9._-]+)(?:\[[^\]]*\])?(?:==(.+))?$/.exec(token);
  return m ? { name: m[1]!, version: m[2] ?? undefined } : { name: token };
}

function parsePackage(
  args: readonly string[],
  ecosystem: "npm" | "PyPI",
): { name: string; version?: string } | null {
  const token = args.find((a) => typeof a === "string" && !a.startsWith("-"));
  if (!token) return null;
  return ecosystem === "npm" ? parseNpmPackage(token) : parsePypiPackage(token);
}

async function queryOsv(
  name: string,
  ecosystem: "npm" | "PyPI",
  version?: string,
): Promise<OsvVuln[]> {
  const payload: Record<string, unknown> = { package: { name, ecosystem } };
  if (version) payload.version = version;

  const resp = await fetch(OSV_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json", "User-Agent": "openclaw-osv-check/1.0" },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(OSV_TIMEOUT_MS),
  });

  if (!resp.ok) throw new Error(`OSV API ${resp.status}`);
  const data = (await resp.json()) as { vulns?: OsvVuln[] };
  return (data.vulns ?? []).filter((v) => v.id.startsWith("MAL-"));
}

/**
 * Checks an MCP server's npx/uvx command against the OSV malware database.
 * Throws if confirmed malware is found. Silently allows on network errors (fail-open).
 */
export async function checkMcpCommandForMalware(
  command: string,
  args: readonly string[],
): Promise<void> {
  const ecosystem = inferEcosystem(command);
  if (!ecosystem) return;

  const pkg = parsePackage(args, ecosystem);
  if (!pkg) return;

  let malware: OsvVuln[];
  try {
    malware = await queryOsv(pkg.name, ecosystem, pkg.version);
  } catch {
    // Fail-open: network errors, timeouts → allow
    return;
  }

  if (malware.length > 0) {
    const ids = malware
      .slice(0, 3)
      .map((v) => v.id)
      .join(", ");
    const summaries = malware
      .slice(0, 3)
      .map((v) => v.summary?.slice(0, 100) ?? v.id)
      .join("; ");
    throw new Error(
      `MCP server '${pkg.name}' (${ecosystem}) blocked — known malware: ${ids}. ${summaries}`,
    );
  }
}
