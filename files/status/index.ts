// Terminal title shows pi's state (ghostel uses it as the buffer name), and a
// desktop notification fires after long runs and whenever pi waits on you.
// Clicking the notification focuses this pi (kitty window or ghostel buffer).
// Unnamed sessions get a short generated name after the first reply (shown in
// the title and in /resume); /name overrides it.
import { spawn } from "node:child_process";
import { basename } from "node:path";
import { uuidv7 } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const NOTIFY_SEND = "@notifySend@";
const FOCUS = "@focus@";
const LONG_RUN_MS = 30_000;
const QUESTION_TOOLS = new Set(["ask_user_question", "plan_mode_question"]);
const ICON = { idle: "○", working: "●", asking: "?" } as const;
const NAME_PROMPT =
	"Name this coding session in 2-5 words, sentence case, no quotes or trailing period. Reply with the name only.";

type State = keyof typeof ICON;

export default function (pi: ExtensionAPI) {
	if (process.env.PI_SUBAGENT_CHILD) return;

	let ctx: ExtensionContext | undefined;
	let state: State = "idle";
	let running = false;
	let startedAt = 0;
	let lastAsk = 0;
	let naming = false;
	let generation = 0;

	const project = () => basename(ctx?.cwd ?? process.cwd());

	function set(next: State) {
		state = next;
		if (ctx?.mode !== "tui") return;
		const name = pi.getSessionName();
		ctx.ui.setTitle(`π ${ICON[state]} ${project()}${name ? ` · ${name}` : ""}`);
	}

	function firstUserText(c: ExtensionContext): string | undefined {
		for (const entry of c.sessionManager.getBranch()) {
			if (entry.type !== "message" || entry.message.role !== "user") continue;
			const content = entry.message.content;
			const text =
				typeof content === "string"
					? content
					: content.flatMap((p: any) => (p.type === "text" ? [p.text] : [])).join("\n");
			if (text.trim()) return text.slice(0, 2000);
		}
	}

	async function autoName(c: ExtensionContext) {
		if (naming || pi.getSessionName() || !c.model || c.mode !== "tui") return;
		const text = firstUserText(c);
		if (!text) return;
		naming = true;
		const gen = generation;
		try {
			const res = await c.modelRegistry.complete(
				c.model,
				{ systemPrompt: NAME_PROMPT, messages: [{ role: "user", content: [{ type: "text", text }], timestamp: Date.now() }] },
				{ cacheRetention: "none", sessionId: uuidv7() },
			);
			const name = res.content
				.flatMap((p: any) => (p.type === "text" ? [p.text] : []))
				.join(" ")
				.replace(/["'`*.]/g, "")
				.replace(/\s+/g, " ")
				.trim()
				.slice(0, 40);
			if (gen !== generation) return;
			if (name && !pi.getSessionName()) {
				pi.setSessionName(name);
				set(state);
			}
		} catch (err) {
			if (gen === generation)
				c.ui.notify(`Session auto-name failed: ${err instanceof Error ? err.message : err}`, "warning");
		} finally {
			naming = false;
		}
	}

	function notify(body: string) {
		if (ctx?.mode !== "tui") return;
		const child = spawn(NOTIFY_SEND, ["-a", "pi", "-A", "default=Open", "--wait", `pi · ${project()}`, body], {
			stdio: ["ignore", "pipe", "ignore"],
		});
		let out = "";
		child.stdout.on("data", (d) => (out += d));
		child.on("error", () => {});
		child.on("close", () => {
			if (out.trim() === "default") spawn(FOCUS, [String(process.pid)], { stdio: "ignore", detached: true }).unref();
		});
	}

	function ask(body: string) {
		lastAsk = Date.now();
		set("asking");
		notify(body);
	}

	pi.on("session_start", async (_e, c) => {
		generation++;
		ctx = c;
		running = false;
		set("idle");
	});

	pi.on("agent_start", async (_e, c) => {
		ctx = c;
		running = true;
		startedAt = Date.now();
		set("working");
	});

	pi.on("agent_settled", async (_e, c) => {
		ctx = c;
		running = false;
		set("idle");
		if (Date.now() - startedAt >= LONG_RUN_MS) notify("Finished");
		void autoName(c);
	});

	// Pick up /name right away
	pi.on("input", async (e) => {
		if (/^\/name\b/.test(e.text)) setTimeout(() => set(state), 100);
		return { action: "continue" as const };
	});

	pi.on("tool_execution_start", async (e) => {
		if (!QUESTION_TOOLS.has(e.toolName)) return;
		ask(e.args?.questions?.[0]?.question ?? "Has a question");
	});

	pi.events.on("permissions:ui_prompt", (data: any) => {
		if (data?.forwarding) return;
		const what = [data?.surface, data?.value].filter(Boolean).join(": ");
		ask(what ? `Allow ${what}?` : "Needs permission");
	});

	// Any other blocking prompt; skipped when one of the above just notified
	pi.on("ui_prompt_start", async (e) => {
		if (Date.now() - lastAsk < 2000) return set("asking");
		ask(e.title ?? "Waiting for input");
	});

	pi.on("ui_prompt_end", async () => {
		set(running ? "working" : "idle");
	});

	pi.on("session_shutdown", async () => {
		generation++;
	});

	pi.on("tool_execution_end", async (e) => {
		if (QUESTION_TOOLS.has(e.toolName) && state === "asking") set(running ? "working" : "idle");
	});
}
