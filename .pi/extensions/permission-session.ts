import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";

type PermissionSystemRuntime = {
  setYoloMode(enabled: boolean, options?: { persist?: boolean; source?: string }): {
    error?: string;
    yoloMode: boolean;
  };
};

type GlobalWithPermissionSystem = typeof globalThis & {
  __piPermissionSystem?: PermissionSystemRuntime;
};

function getPermissionSystem(): PermissionSystemRuntime | undefined {
  return (globalThis as GlobalWithPermissionSystem).__piPermissionSystem;
}

function setSessionYoloMode(ctx: ExtensionCommandContext, enabled: boolean): void {
  const permissionSystem = getPermissionSystem();
  if (!permissionSystem) {
    ctx.ui.notify("pi-permission-system is not loaded.", "error");
    return;
  }

  const result = permissionSystem.setYoloMode(enabled, {
    persist: false,
    source: enabled ? "/allow-all" : "/ask-all",
  });
  if (result.error) {
    ctx.ui.notify(result.error, "error");
    return;
  }

  ctx.ui.notify(
    enabled
      ? "Session permission approvals enabled. /ask-all restores confirmation prompts."
      : "Session permission approvals disabled; confirmation prompts are active again.",
    enabled ? "warning" : "info",
  );
}

export default function permissionSessionCommands(pi: ExtensionAPI): void {
  pi.registerCommand("allow-all", {
    description: "Temporarily auto-approve ask permissions for this session",
    handler: async (_args, ctx) => {
      setSessionYoloMode(ctx, true);
    },
  });

  pi.registerCommand("ask-all", {
    description: "Restore permission confirmations for this session",
    handler: async (_args, ctx) => {
      setSessionYoloMode(ctx, false);
    },
  });
}
