// /new starts on pi's default model, since settings.json is read-only. Carry the
// model and thinking level over from the session being left (the pi wrapper does
// the same at startup). Module state survives /new; the previous session file is
// the fallback.
import { existsSync, readFileSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type Level = Parameters<ExtensionAPI["setThinkingLevel"]>[0];
let last: { provider?: string; modelId?: string; thinking?: Level } = {};

function fromFile(file: string) {
	const found: typeof last = {};
	try {
		for (const line of readFileSync(file, "utf8").split("\n")) {
			if (!line.includes("_change")) continue;
			const e = JSON.parse(line);
			if (e.type === "model_change") [found.provider, found.modelId] = [e.provider, e.modelId];
			else if (e.type === "thinking_level_change") found.thinking = e.thinkingLevel;
		}
	} catch {}
	return found;
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (event, ctx) => {
		if (event.reason === "new") {
			const want =
				last.modelId || !event.previousSessionFile || !existsSync(event.previousSessionFile)
					? { ...last }
					: fromFile(event.previousSessionFile);
			if (want.provider && want.modelId && (ctx.model?.provider !== want.provider || ctx.model?.id !== want.modelId)) {
				const model = ctx.modelRegistry.find(want.provider, want.modelId);
				if (model) await pi.setModel(model);
			}
			if (want.thinking) pi.setThinkingLevel(want.thinking);
		}
		last = { provider: ctx.model?.provider, modelId: ctx.model?.id, thinking: pi.getThinkingLevel() };
	});
	pi.on("model_select", async (event) => {
		last.provider = event.model.provider;
		last.modelId = event.model.id;
		last.thinking = pi.getThinkingLevel();
	});
	pi.on("thinking_level_select", async (event) => {
		last.thinking = event.level;
	});
}
