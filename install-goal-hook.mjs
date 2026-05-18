#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const hooksPath = path.join(os.homedir(), ".codex", "hooks.json");
const runtimeRoot = process.env.GOAL_HOME ?? path.join(os.homedir(), ".codex", "goal");
const skillsRoot = path.join(os.homedir(), ".codex", "skills");
const hookCommand = `"${path.join(runtimeRoot, "goal-hook")}" --from-hook`;
const entry = {
  hooks: [
    {
      type: "command",
      command: hookCommand,
      timeout: 86400,
      statusMessage: "Goal loop checking active project goal"
    }
  ]
};

let data = { hooks: {} };
if (fs.existsSync(hooksPath)) {
  data = JSON.parse(fs.readFileSync(hooksPath, "utf8"));
}

for (const skillName of ["grill-me", "grill-with-docs", "goal", "codex-goal"]) {
  const bundledSkill = path.join(runtimeRoot, "skills", skillName);
  const targetSkill = path.join(skillsRoot, skillName);

  if (!fs.existsSync(bundledSkill)) {
    console.warn(`Bundled skill missing, skipping: ${bundledSkill}`);
    continue;
  }

  fs.mkdirSync(skillsRoot, { recursive: true });
  fs.rmSync(targetSkill, { recursive: true, force: true });
  fs.cpSync(bundledSkill, targetSkill, { recursive: true });
  console.log(`Installed skill: ${skillName}`);
}

data.hooks ??= {};
data.hooks.Stop ??= [];

data.hooks.Stop = data.hooks.Stop.filter((item) => {
  const commands = item?.hooks?.map((hook) => hook?.command).filter(Boolean) ?? [];
  return !commands.some((command) => command.includes("goal-hook"));
});

data.hooks.Stop.push(entry);

const backupPath = `${hooksPath}.bak-${new Date().toISOString().replace(/[:.]/g, "-")}`;
if (fs.existsSync(hooksPath)) {
  fs.copyFileSync(hooksPath, backupPath);
}

fs.writeFileSync(hooksPath, `${JSON.stringify(data, null, 2)}\n`);

console.log("Installed global Goal Stop hook");
if (fs.existsSync(backupPath)) {
  console.log(`Backup: ${backupPath}`);
}
