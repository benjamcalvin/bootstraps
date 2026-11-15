import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Plugin, Skill } from "@opencode/plugin";

const BLOCK_SCALARS = new Set([">", ">-", ">+", "|", "|-", "|+"]);

function unquote(value) {
  const trimmed = value.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, "\\");
  }
  if (trimmed.length >= 2 && trimmed.startsWith("'") && trimmed.endsWith("'")) {
    return trimmed.slice(1, -1).replace(/''/g, "'");
  }
  return trimmed;
}

function formatBlock(lines, indicator) {
  const nonEmpty = lines.filter((line) => line.trim().length > 0);
  const minIndent = nonEmpty.reduce(
    (min, line) => Math.min(min, line.match(/^ */)[0].length),
    Number.POSITIVE_INFINITY,
  );
  const dedented = lines.map((line) =>
    line.trim().length === 0 ? "" : line.slice(minIndent),
  );
  if (indicator.startsWith("|")) {
    return dedented.join("\n").trimEnd();
  }
  const paragraphs = [];
  let current = [];
  for (const line of dedented) {
    if (line === "") {
      if (current.length > 0) {
        paragraphs.push(current.join(" "));
        current = [];
      }
    } else {
      current.push(line.trim());
    }
  }
  if (current.length > 0) {
    paragraphs.push(current.join(" "));
  }
  return paragraphs.join("\n\n").trimEnd();
}

function parseSkillMarkdown(raw, fallbackId) {
  const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!match) {
    return {
      name: fallbackId,
      description: undefined,
      autoinvoke: true,
      content: raw.trimStart(),
    };
  }
  const frontmatter = match[1];
  const content = match[2].replace(/^(?:\r?\n)+/, "");
  const lines = frontmatter.split(/\r?\n/);

  let name = fallbackId;
  let description;
  let autoinvoke = true;

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (/^\s*(?:"?opencode\/autoinvoke"?\s*:\s*false|disable-model-invocation\s*:\s*true)\s*$/.test(line)) {
      autoinvoke = false;
      continue;
    }
    if (/^\s/.test(line) || line.trim() === "" || line.trim().startsWith("#")) {
      continue;
    }
    const kv = line.match(/^([A-Za-z0-9_.-]+):(.*)$/);
    if (!kv) {
      continue;
    }
    const key = kv[1];
    const rest = kv[2].trim();
    if (key === "name" && rest) {
      name = unquote(rest);
      continue;
    }
    if (key === "description") {
      if (BLOCK_SCALARS.has(rest)) {
        const blockLines = [];
        while (i + 1 < lines.length && (/^\s+/.test(lines[i + 1]) || lines[i + 1].trim() === "")) {
          i += 1;
          blockLines.push(lines[i]);
        }
        description = formatBlock(blockLines, rest);
      } else if (rest) {
        description = unquote(rest);
      }
    }
  }

  return { name, description, autoinvoke, content };
}

async function loadPluginSkills(pluginRoot) {
  const skillsDir = path.join(pluginRoot, "skills");
  const entries = await readdir(skillsDir, { withFileTypes: true });
  const ids = entries.filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort();
  const skills = [];
  for (const id of ids) {
    const filePath = path.join(skillsDir, id, "SKILL.md");
    let raw;
    try {
      raw = await readFile(filePath, "utf8");
    } catch {
      continue;
    }
    const parsed = parseSkillMarkdown(raw, id);
    skills.push({ id, filePath, ...parsed });
  }
  return skills;
}

const pluginRoot = path.dirname(fileURLToPath(import.meta.url));

export default Plugin.define({
  id: "bootstraps.bootstrap-docs",
  async setup(ctx) {
    const skills = await loadPluginSkills(pluginRoot);

    await ctx.skill.transform((editor) => {
      for (const skill of skills) {
        editor.add({
          id: Skill.ID.make(skill.id),
          name: Skill.Name.make(skill.name),
          ...(skill.description ? { description: skill.description } : {}),
          autoinvoke: skill.autoinvoke,
          path: Skill.Info.fields.path.make(skill.filePath),
          content: skill.content,
        });
      }
    });

    await ctx.command.transform((editor) => {
      for (const skill of skills.filter((item) => item.autoinvoke !== false)) {
        editor.add({
          name: skill.id,
          ...(skill.description ? { description: skill.description } : {}),
          execute: async ({ sessionID, prompt, delivery }) => {
            const args = prompt.text.trim();
            const skillId = Skill.ID.make(skill.id);
            const existingSkills = prompt.skills ?? [];
            const hasSkill = existingSkills.some((entry) => entry.id === skillId);
            await ctx.session.prompt({
              ...prompt,
              sessionID,
              skills: hasSkill ? existingSkills : [...existingSkills, { id: skillId }],
              text: args ? `Use the ${skill.id} skill for:\n\n${args}` : `Use the ${skill.id} skill.`,
              delivery,
            });
          },
        });
      }
    });
  },
});
