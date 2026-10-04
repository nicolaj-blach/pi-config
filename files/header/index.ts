// Startup header: logo (kitty graphics) with model, folder and git branch, plus the
// tips, loaded resources and recent sessions from pi-powerline-footer's welcome box.
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Image, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const LOGO = readFileSync(join(import.meta.dirname, "logo.png")).toString("base64");
const LOGO_WIDTH = 14;
const LOGO_HEIGHT = 6;
const MARGIN = 2;
const home = homedir();
const tilde = (p: string) => (p === home || p.startsWith(home + "/") ? "~" + p.slice(home.length) : p);

function gitBranch(cwd: string): string {
	try {
		return execFileSync("git", ["branch", "--show-current"], { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
	} catch {
		return "";
	}
}

function ago(ms: number): string {
	const s = Math.max(0, (Date.now() - ms) / 1000);
	if (s < 3600) return `${Math.max(1, Math.round(s / 60))}m ago`;
	if (s < 86400) return `${Math.round(s / 3600)}h ago`;
	return `${Math.round(s / 86400)}d ago`;
}

// Newest session per project folder
function recentSessions(count: number): string[] {
	const root = join(home, ".pi/agent/sessions");
	const files: { file: string; mtime: number }[] = [];
	for (const dir of existsSync(root) ? readdirSync(root) : []) {
		const d = join(root, dir);
		try {
			for (const f of readdirSync(d)) if (f.endsWith(".jsonl")) files.push({ file: join(d, f), mtime: statSync(join(d, f)).mtimeMs });
		} catch {}
	}
	files.sort((a, b) => b.mtime - a.mtime);
	const seen = new Set<string>();
	const out: string[] = [];
	for (const { file, mtime } of files) {
		let cwd = "";
		try {
			cwd = JSON.parse(readFileSync(file, "utf8").split("\n", 1)[0]).cwd ?? "";
		} catch {}
		const name = basename(cwd) || "?";
		if (seen.has(name)) continue;
		seen.add(name);
		out.push(`${name} (${ago(mtime)})`);
		if (out.length === count) break;
	}
	return out;
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (event, ctx) => {
		if (!ctx.hasUI || (event.reason !== "startup" && event.reason !== "new")) return;

		const model = ctx.model ? `${ctx.model.name ?? ctx.model.id} · ${ctx.model.provider}` : "No model";
		const branch = gitBranch(ctx.cwd);
		const commands = pi.getCommands();
		const contextFiles = [join(home, ".pi/agent/AGENTS.md"), join(ctx.cwd, "AGENTS.md"), join(ctx.cwd, ".pi/AGENTS.md")].filter(existsSync).length;
		const loaded = [
			plural(contextFiles, "context file"),
			plural(commands.filter((c) => c.source === "skill").length, "skill"),
			plural(commands.filter((c) => c.source === "prompt").length, "prompt template"),
			`≈ ${(ctx.getSystemPrompt().length / 4000).toFixed(1)}k prompt tokens`,
		];
		const recent = recentSessions(3);

		ctx.ui.setHeader((_tui, theme) => {
			const logo = new Image(LOGO, "image/png", { fallbackColor: (s) => theme.fg("accent", s) }, { maxWidthCells: LOGO_WIDTH, maxHeightCells: LOGO_HEIGHT });
			const label = (s: string) => theme.bold(theme.fg("accent", s.padEnd(17)));
			const sep = theme.fg("dim", " · ");
			const text = [
				theme.fg("accent", model),
				theme.fg("muted", tilde(ctx.cwd)) + (branch ? theme.fg("dim", "  ") + theme.fg("success", branch) : ""),
				"",
				label("Tips") + ["/ commands", "! bash", "Shift+Tab plan mode", "Alt+T thinking"].join(sep),
				label("Loaded") + loaded.join(sep),
				label("Recent sessions") + (recent.length ? recent.join(sep) : theme.fg("dim", "none")),
			];

			return {
				invalidate() {
					logo.invalidate();
				},
				render(width: number): string[] {
					const image = logo.render(LOGO_WIDTH + 2);
					const fallback = image.length === 1 && visibleWidth(image[0]) > 0;
					// The image is one escape sequence (cursor stays put) plus blank rows;
					// text starts in the column to its right on every row
					const rows = fallback ? [theme.fg("accent", "⬡")] : image;
					const left = " ".repeat(MARGIN);
					const textCol = MARGIN + (fallback ? 1 : LOGO_WIDTH) + 3;
					const lines: string[] = [];
					for (let i = 0; i < Math.max(rows.length, text.length); i++) {
						const logoRow = rows[i] ?? "";
						const offset = fallback ? textCol - MARGIN - visibleWidth(logoRow) : textCol - MARGIN;
						const move = fallback || !logoRow ? " ".repeat(Math.max(0, offset)) : `\x1b[${offset}C`;
						lines.push(truncateToWidth(left + logoRow + move + (text[i] ?? ""), width));
					}
					return ["", ...lines, ""];
				},
			};
		});
	});
}
