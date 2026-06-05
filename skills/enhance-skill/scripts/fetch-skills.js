#!/usr/bin/env node

/**
 * Fetches skill content from skills.sh and agentskills.guide.
 * Zero dependencies — uses only Node.js built-ins.
 *
 * Commands:
 *   node fetch-skills.js search <query>          Search both directories (10 results each)
 *   node fetch-skills.js fetch <id-or-url>       Fetch SKILL.md content
 *
 * Search output: JSON array of { name, description, source, fetchId }
 * Fetch output: JSON { content } (raw SKILL.md markdown)
 *
 * Fetch accepts:
 *   - skills.sh ID: "owner/repo/skillId" (resolves via GitHub Trees API)
 *   - agentskills.guide slug: "owner-repo-skill" (resolves via landing page → GitHub raw)
 *   - Raw URL: any https:// URL (fetched directly)
 */

const https = require("https");

// --- HTTP ---

function get(url, { maxRedirects = 5 } = {}) {
  return new Promise((resolve, reject) => {
    const proto = url.startsWith("https") ? https : require("http");
    proto
      .get(url, { headers: { "User-Agent": "fetch-skills/1.0" } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          if (maxRedirects <= 0) return reject(new Error("Too many redirects"));
          return resolve(get(new URL(res.headers.location, url).href, { maxRedirects: maxRedirects - 1 }));
        }
        if (res.statusCode !== 200) {
          res.resume();
          return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        }
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => resolve(Buffer.concat(chunks).toString("utf-8")));
        res.on("error", reject);
      })
      .on("error", reject);
  });
}

function stripTags(html) {
  return html.replace(/<[^>]+>/g, "");
}

// --- skills.sh ---

async function searchSkillsSh(query) {
  const url = `https://skills.sh/api/search?q=${encodeURIComponent(query)}&limit=10`;
  const json = JSON.parse(await get(url));
  return json.skills.map((s) => ({
    name: s.skillId,
    description: null,
    source: `skills.sh — ${s.source}`,
    fetchId: s.id, // "owner/repo/skillId"
  }));
}

async function fetchSkillsSh(id) {
  // id = "owner/repo/skillId"
  const parts = id.split("/");
  if (parts.length < 3) {
    throw new Error("Invalid ID format. Expected: owner/repo/skill");
  }
  const owner = parts[0];
  const repo = parts[1];
  const skillId = parts.slice(2).join("/");

  // Use GitHub Trees API to find the SKILL.md path
  const treeUrl = `https://api.github.com/repos/${owner}/${repo}/git/trees/main?recursive=1`;
  const tree = JSON.parse(await get(treeUrl));
  const skillMdPaths = tree.tree
    .filter((t) => t.type === "blob" && t.path.endsWith("/SKILL.md"))
    .map((t) => t.path);

  if (skillMdPaths.length === 0) {
    throw new Error(`No SKILL.md files found in ${owner}/${repo}`);
  }

  // Try matching by directory name (dir name ≈ skillId or skillId ends with dir name)
  const dirMatch = skillMdPaths.find((p) => {
    const dir = p.split("/").slice(-2, -1)[0];
    return dir === skillId || skillId.endsWith(dir);
  });

  if (dirMatch) {
    const content = await get(
      `https://raw.githubusercontent.com/${owner}/${repo}/main/${dirMatch}`
    );
    return { content: content.trim() };
  }

  // Fallback: check frontmatter name field in all SKILL.md files
  const results = await Promise.all(
    skillMdPaths.map(async (p) => {
      try {
        const content = await get(
          `https://raw.githubusercontent.com/${owner}/${repo}/main/${p}`
        );
        const fmMatch = content.match(/^---\s*\n([\s\S]*?)\n---/);
        const nameMatch = fmMatch?.[1].match(/^name:\s*(.+)$/m);
        const name = nameMatch?.[1].trim().replace(/^["']|["']$/g, "");
        return { path: p, name, content };
      } catch {
        return { path: p, name: null, content: null };
      }
    })
  );

  const match = results.find((r) => r.name === skillId);
  if (match) return { content: match.content.trim() };

  throw new Error(
    `Skill "${skillId}" not found in ${owner}/${repo}. Available: ${results.map((r) => r.name).filter(Boolean).join(", ")}`
  );
}

// --- agentskills.guide ---

async function searchAgentSkills(query) {
  const url = `https://agentskills.guide/search?q=${encodeURIComponent(query)}&sort=stars-desc`;
  const html = await get(url);

  const skills = [];
  const seen = new Set();
  const linkRegex = /<a[^>]*href="\/skills\/([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  let match;

  while ((match = linkRegex.exec(html)) !== null) {
    const slug = match[1];
    if (seen.has(slug)) continue;
    seen.add(slug);

    const cardHtml = match[2];
    const titleMatch = cardHtml.match(/<h3[^>]*>([\s\S]*?)<\/h3>/i);
    const title = titleMatch ? stripTags(titleMatch[1]).trim() : slug;
    const allP = [...cardHtml.matchAll(/<p[^>]*>([\s\S]*?)<\/p>/gi)];
    const desc = allP.length > 1 ? stripTags(allP[1][1]).trim() : "";

    skills.push({
      name: title,
      description: desc || null,
      source: "agentskills.guide",
      fetchId: `agentskills:${slug}`,
    });

    if (skills.length >= 10) break;
  }

  return skills;
}

async function fetchAgentSkill(slug) {
  const pageUrl = `https://agentskills.guide/skills/${slug}`;
  const html = await get(pageUrl);

  const treeMatch = html.match(
    /github\.com\/([^/"]+)\/([^/"]+)\/tree\/([^/"]+)\/([^"<\s]+)/
  );
  if (!treeMatch) {
    throw new Error("Could not find GitHub tree path on agentskills.guide page");
  }

  const [, owner, repo, hash, path] = treeMatch;
  const rawUrl = `https://raw.githubusercontent.com/${owner}/${repo}/${hash}/${path}/SKILL.md`;
  const content = await get(rawUrl);
  return { content: content.trim() };
}

// --- Fetch router ---

async function fetchContent(idOrUrl) {
  // agentskills: prefix
  if (idOrUrl.startsWith("agentskills:")) {
    return fetchAgentSkill(idOrUrl.slice("agentskills:".length));
  }

  // Raw URL
  if (idOrUrl.startsWith("https://")) {
    const content = await get(idOrUrl);
    return { content: content.trim() };
  }

  // skills.sh ID: "owner/repo/skillId"
  return fetchSkillsSh(idOrUrl);
}

// --- CLI ---

async function main() {
  const [action, ...rest] = process.argv.slice(2);

  if (!action) {
    console.error(`Usage:
  node fetch-skills.js search <query>
  node fetch-skills.js fetch <id-or-url>`);
    process.exit(1);
  }

  try {
    if (action === "search") {
      const query = rest.join(" ");
      if (!query) {
        console.error("Usage: fetch-skills.js search <query>");
        process.exit(1);
      }

      const [skillsSh, agentSkills] = await Promise.all([
        searchSkillsSh(query).catch((err) => {
          console.error(`skills.sh search failed: ${err.message}`);
          return [];
        }),
        searchAgentSkills(query).catch((err) => {
          console.error(`agentskills.guide search failed: ${err.message}`);
          return [];
        }),
      ]);

      console.log(JSON.stringify([...skillsSh, ...agentSkills], null, 2));
    } else if (action === "fetch") {
      const idOrUrl = rest[0];
      if (!idOrUrl) {
        console.error("Usage: fetch-skills.js fetch <id-or-url>");
        process.exit(1);
      }
      const result = await fetchContent(idOrUrl);
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.error(`Unknown action: ${action}. Use "search" or "fetch"`);
      process.exit(1);
    }
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  }
}

main();
