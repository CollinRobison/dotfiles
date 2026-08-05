import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const ACTIVE_AGENT_ENTRY = "active_agent";
const AGENT_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;

type AgentDefinition = {
  name: string;
  description: string;
  instructions: string;
};

type ActiveAgentData = {
  name?: unknown;
};

function getAgentsDirectory(): string {
  return join(getAgentDir(), "agents");
}

function parseAgentFile(name: string, content: string): AgentDefinition {
  const frontmatterMatch = content.match(/^---\s*\n([\s\S]*?)\n---\s*\n?/);
  const frontmatter = frontmatterMatch?.[1] ?? "";
  const description = frontmatter.match(/^description:\s*(.*)$/m)?.[1]?.trim() ?? "";
  const instructions = frontmatterMatch
    ? content.slice(frontmatterMatch[0].length).trim()
    : content.trim();

  return { name, description, instructions };
}

function loadAgentDefinitions(): AgentDefinition[] {
  const directory = getAgentsDirectory();
  if (!existsSync(directory)) {
    return [];
  }

  return readdirSync(directory)
    .filter((entry) => entry.endsWith(".md"))
    .map((entry) => entry.slice(0, -3))
    .filter((name) => AGENT_NAME_PATTERN.test(name))
    .map((name) => {
      const path = resolve(directory, `${name}.md`);
      try {
        return parseAgentFile(name, readFileSync(path, "utf8"));
      } catch {
        return null;
      }
    })
    .filter((agent): agent is AgentDefinition => agent !== null)
    .sort((left, right) => left.name.localeCompare(right.name));
}

function getActiveAgentFromSession(ctx: ExtensionContext): string | null {
  const entries = ctx.sessionManager.getBranch();
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const entry = entries[index] as {
      type?: string;
      customType?: string;
      data?: ActiveAgentData;
    };
    if (entry.type !== "custom" || entry.customType !== ACTIVE_AGENT_ENTRY) {
      continue;
    }

    if (entry.data?.name === null) {
      return null;
    }
    if (typeof entry.data?.name === "string" && AGENT_NAME_PATTERN.test(entry.data.name)) {
      return entry.data.name;
    }
  }

  return null;
}

function updateStatus(ctx: ExtensionContext, agentName: string | null): void {
  if (ctx.hasUI) {
    ctx.ui.setStatus("agent-selector", agentName ? `agent: ${agentName}` : "agent: normal");
  }
}

function notify(ctx: ExtensionContext, message: string, level: "info" | "warning" | "error" = "info"): void {
  if (ctx.hasUI) {
    ctx.ui.notify(message, level);
  }
}

async function chooseAgent(ctx: ExtensionContext, agents: AgentDefinition[]): Promise<string | null | undefined> {
  if (!ctx.hasUI) {
    notify(ctx, "Use /agent normal, /agent cautious, or /agent reviewer in non-interactive mode.", "warning");
    return null;
  }

  const choices = [
    "normal — use Pi's normal behavior",
    ...agents.map((agent) => `${agent.name} — ${agent.description || "custom agent"}`),
  ];
  const selected = await ctx.ui.select("Select agent", choices);
  if (!selected) {
    return undefined;
  }
  return selected.split(" — ", 1)[0] === "normal" ? null : selected.split(" — ", 1)[0];
}

export default function agentSelector(pi: ExtensionAPI): void {
  pi.on("session_start", async (_event, ctx) => {
    const activeAgent = getActiveAgentFromSession(ctx);
    updateStatus(ctx, activeAgent);
  });

  pi.on("before_agent_start", async (_event, ctx) => {
    const activeAgent = getActiveAgentFromSession(ctx);
    updateStatus(ctx, activeAgent);
    if (!activeAgent) {
      return;
    }

    const agent = loadAgentDefinitions().find((candidate) => candidate.name === activeAgent);
    if (!agent) {
      notify(ctx, `Agent '${activeAgent}' is unavailable; using normal behavior.`, "warning");
      return;
    }

    return {
      systemPrompt: `${_event.systemPrompt}\n\n<active_agent name="${agent.name}">\nYou are operating as the '${agent.name}' agent.\n\n${agent.instructions}\n</active_agent>`,
    };
  });

  pi.registerCommand("agent", {
    description: "Select a global Pi agent (normal, cautious, or reviewer)",
    handler: async (args, ctx) => {
      const agents = loadAgentDefinitions();
      const requested = args.trim();
      let selected: string | null | undefined;
      if (requested) {
        selected = requested === "normal" ? null : agents.find((agent) => agent.name === requested)?.name;
      } else {
        selected = await chooseAgent(ctx, agents);
        if (selected === undefined) {
          return;
        }
      }

      if (selected === undefined) {
        notify(ctx, `Unknown agent '${requested}'. Available: normal, ${agents.map((agent) => agent.name).join(", ")}.`, "error");
        return;
      }

      pi.appendEntry(ACTIVE_AGENT_ENTRY, { name: selected });
      updateStatus(ctx, selected);
      notify(ctx, selected ? `Selected '${selected}' for the next turn.` : "Selected normal Pi behavior for the next turn.");
    },
  });

  pi.registerShortcut("ctrl+shift+a", {
    description: "Open the global Pi agent selector",
    handler: async (ctx) => {
      const selected = await chooseAgent(ctx, loadAgentDefinitions());
      if (selected === undefined) {
        return;
      }

      pi.appendEntry(ACTIVE_AGENT_ENTRY, { name: selected });
      updateStatus(ctx, selected);
      notify(ctx, selected ? `Selected '${selected}' for the next turn.` : "Selected normal Pi behavior for the next turn.");
    },
  });

  pi.registerCommand("agents", {
    description: "List available global Pi agents",
    handler: async (_args, ctx) => {
      const agents = loadAgentDefinitions();
      notify(ctx, [
        "Available agents:",
        "- normal — Pi's normal behavior",
        ...agents.map((agent) => `- ${agent.name} — ${agent.description || "custom agent"}`),
        "Use /agent [name] to select one.",
      ].join("\n"));
    },
  });
}
