import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { DynamicBorder } from "@earendil-works/pi-coding-agent";
import type { Model } from "@earendil-works/pi-ai";
import {
	Container,
	fuzzyFilter,
	Input,
	Spacer,
	SelectList,
	type Component,
	type Focusable,
	type KeybindingsManager,
	type SelectItem,
	Text,
	visibleWidth,
} from "@earendil-works/pi-tui";

type PiModel = Model<any>;
type PickerTheme = ExtensionContext["ui"]["theme"];
type Keybindings = KeybindingsManager;

type ModelRow = {
	key: string;
	searchText: string;
	label: string;
	description: string;
};

const MAX_VISIBLE_ROWS = 10;

function trimDecimalZeros(value: string): string {
	return value.replace(/(\.\d*?[1-9])0+$/u, "$1").replace(/\.0+$/u, "");
}

function formatRate(rate: number): string {
	if (rate === 0) return "$0";
	if (rate < 0.01) return `$${trimDecimalZeros(rate.toFixed(4))}`;
	if (rate < 1) return `$${trimDecimalZeros(rate.toFixed(3))}`;
	return `$${trimDecimalZeros(rate.toFixed(2))}`;
}

function formatTokens(tokens: number): string {
	if (tokens >= 1_000_000) {
		const millions = tokens / 1_000_000;
		return `${Number.isInteger(millions) ? millions : millions.toFixed(1)}M`;
	}
	if (tokens >= 1_000) {
		const thousands = tokens / 1_000;
		return `${Number.isInteger(thousands) ? thousands : thousands.toFixed(1)}k`;
	}
	return String(tokens);
}

function formatRates(model: PiModel): string {
	const { input, output, cacheRead, cacheWrite, tiers } = model.cost;
	const base = `in ${formatRate(input)}/M · out ${formatRate(output)}/M · cr ${formatRate(cacheRead)}/M · cw ${formatRate(cacheWrite)}/M`;
	const tierText = (tiers ?? [])
		.slice()
		.sort((left, right) => left.inputTokensAbove - right.inputTokensAbove)
		.map(
			(tier) =>
				`>${formatTokens(tier.inputTokensAbove)} ${formatRate(tier.input)}/${formatRate(tier.output)}/${formatRate(tier.cacheRead)}/${formatRate(tier.cacheWrite)}`,
		)
		.join("; ");
	return tierText ? `${base} · tiers ${tierText}` : base;
}

function formatCompactRates(model: PiModel): string {
	const { input, output } = model.cost;
	return `in/out ${formatRate(input)}/${formatRate(output)}`;
}

function formatCompactCacheRates(model: PiModel): string {
	const { cacheRead, cacheWrite } = model.cost;
	return `cr/cw ${formatRate(cacheRead)}/${formatRate(cacheWrite)}`;
}

function formatCompactTiers(model: PiModel): string {
	return (model.cost.tiers ?? [])
		.slice()
		.sort((left, right) => left.inputTokensAbove - right.inputTokensAbove)
		.map(
			(tier) =>
				` · >${formatTokens(tier.inputTokensAbove)} ${formatRate(tier.input)}/${formatRate(tier.output)}/${formatRate(tier.cacheRead)}/${formatRate(tier.cacheWrite)}`,
		)
		.join("");
}

function createModelRows(models: readonly PiModel[], registry: ExtensionContext["modelRegistry"], current: PiModel | undefined): ModelRow[] {
	return models.map((model) => {
		const key = `${model.provider}/${model.id}`;
		const providerName = registry.getProviderDisplayName(model.provider);
		const currentMarker = current?.provider === model.provider && current.id === model.id ? " ✓" : "";
		return {
			key,
			searchText: `${key} ${model.name} ${providerName}`,
			label: `${model.id}${currentMarker}`,
			description: `${formatCompactRates(model)} · ctx ${formatTokens(model.contextWindow)} · ${formatCompactCacheRates(model)}${formatCompactTiers(model)} · ${providerName} · ${model.name} · max ${formatTokens(model.maxTokens)}`,
		};
	});
}

function availableModels(ctx: ExtensionContext, scoped: boolean): PiModel[] {
	const available = ctx.modelRegistry.getAvailable();
	if (!scoped || ctx.scopedModels.length === 0) return available;

	const availableByKey = new Map(available.map((model) => [`${model.provider}/${model.id}`, model]));
	return ctx.scopedModels
		.map((entry) => availableByKey.get(`${entry.model.provider}/${entry.model.id}`) ?? entry.model)
		.filter((model): model is PiModel => Boolean(model));
}

class ModelCostPicker implements Component, Focusable {
	private readonly tui: { requestRender(): void };
	private readonly theme: PickerTheme;
	private readonly keybindings: Keybindings;
	private readonly registry: ExtensionContext["modelRegistry"];
	private readonly current: PiModel | undefined;
	private readonly done: (result: string | null) => void;
	private readonly scopeLabel: string;
	private readonly container = new Container();
	private readonly listContainer = new Container();
	private readonly search = new Input();
	private readonly status = new Text("", 0, 0);
	private list: SelectList;
	private rows: ModelRow[];
	private _focused = false;
	private closed = false;

	constructor(options: {
		tui: { requestRender(): void };
		theme: PickerTheme;
		keybindings: Keybindings;
		registry: ExtensionContext["modelRegistry"];
		models: readonly PiModel[];
		current: PiModel | undefined;
		scopeLabel: string;
		done: (result: string | null) => void;
	}) {
		this.tui = options.tui;
		this.theme = options.theme;
		this.keybindings = options.keybindings;
		this.registry = options.registry;
		this.current = options.current;
		this.scopeLabel = options.scopeLabel;
		this.done = options.done;
		this.rows = createModelRows(options.models, this.registry, this.current);
		this.list = this.createList(this.rows);
		this.search.onSubmit = () => this.selectCurrent();
		this.buildContainer();
	}

	get focused(): boolean {
		return this._focused;
	}

	set focused(value: boolean) {
		this._focused = value;
		this.search.focused = value;
	}

	private createList(rows: readonly ModelRow[]): SelectList {
		const items: SelectItem[] = rows.map((row) => ({
			value: row.key,
			label: row.label,
			description: row.description,
		}));
		const primaryColumnWidth = Math.max(
			...items.map((item) => visibleWidth(item.label) + 2),
			1,
		);
		const list = new SelectList(
			items,
			MAX_VISIBLE_ROWS,
			{
				selectedPrefix: (text) => this.theme.fg("accent", text),
				selectedText: (text) => this.theme.fg("accent", text),
				description: (text) => this.theme.fg("muted", text),
				scrollInfo: (text) => this.theme.fg("dim", text),
				noMatch: (text) => this.theme.fg("warning", text),
			},
			{
				minPrimaryColumnWidth: primaryColumnWidth,
				maxPrimaryColumnWidth: primaryColumnWidth,
			},
		);
		list.onSelect = (item) => this.done(item.value);
		list.onCancel = () => this.cancel();
		const currentIndex = items.findIndex((item) => item.value === this.currentKey());
		if (currentIndex >= 0) list.setSelectedIndex(currentIndex);
		return list;
	}

	private currentKey(): string | undefined {
		return this.current ? `${this.current.provider}/${this.current.id}` : undefined;
	}

	private buildContainer(): void {
		this.container.clear();
		this.container.addChild(new DynamicBorder((text: string) => this.theme.fg("accent", text)));
		this.container.addChild(new Text(this.theme.fg("accent", this.theme.bold("Model costs")), 0, 0));
		this.container.addChild(new Text(this.theme.fg("muted", "Pi catalog · API-equivalent estimates · rates per million tokens"), 0, 0));
		this.container.addChild(new Text(this.theme.fg("dim", "in/out = input/output · cr/cw = cache read/write"), 0, 0));
		this.container.addChild(new Text(this.theme.fg("dim", "Subscription/OAuth billing may differ from these reference prices."), 0, 0));
		this.container.addChild(new Text(this.theme.fg("dim", `Scope: ${this.scopeLabel}`), 0, 0));
		this.container.addChild(new Spacer(1));
		this.container.addChild(this.search);
		this.container.addChild(new Spacer(1));
		this.listContainer.clear();
		this.listContainer.addChild(this.list);
		this.container.addChild(this.listContainer);
		this.container.addChild(this.status);
		this.container.addChild(new Spacer(1));
		this.container.addChild(new Text(this.theme.fg("dim", "↑↓ navigate · type to search · enter select · esc cancel"), 0, 0));
		this.container.addChild(new DynamicBorder((text: string) => this.theme.fg("accent", text)));
	}

	private selectCurrent(): void {
		const selected = this.list.getSelectedItem();
		if (selected) this.done(selected.value);
	}

	private cancel(): void {
		this.closed = true;
		this.done(null);
	}

	updateModels(models: readonly PiModel[], statusText = ""): void {
		if (this.closed) return;
		this.rows = createModelRows(models, this.registry, this.current);
		const query = this.search.getValue();
		const filtered = query
			? fuzzyFilter(this.rows, query, (row) => row.searchText)
			: this.rows;
		this.list = this.createList(filtered);
		this.listContainer.clear();
		this.listContainer.addChild(this.list);
		this.status.setText(statusText ? this.theme.fg("dim", statusText) : "");
		this.container.invalidate();
		this.tui.requestRender();
	}

	setStatus(statusText: string): void {
		if (this.closed) return;
		this.status.setText(statusText ? this.theme.fg("dim", statusText) : "");
		this.tui.requestRender();
	}

	handleInput(data: string): void {
		if (this.keybindings.matches(data, "tui.select.up") || this.keybindings.matches(data, "tui.select.down")) {
			this.list.handleInput(data);
			this.tui.requestRender();
			return;
		}
		if (this.keybindings.matches(data, "tui.select.confirm")) {
			this.selectCurrent();
			return;
		}
		if (this.keybindings.matches(data, "tui.select.cancel")) {
			this.cancel();
			return;
		}

		this.search.handleInput(data);
		const query = this.search.getValue();
		const filtered = query
			? fuzzyFilter(this.rows, query, (row) => row.searchText)
			: this.rows;
		this.list = this.createList(filtered);
		this.listContainer.clear();
		this.listContainer.addChild(this.list);
		this.tui.requestRender();
	}

	render(width: number): string[] {
		return this.container.render(width);
	}

	invalidate(): void {
		this.container.invalidate();
	}

	close(): void {
		this.closed = true;
	}
}

async function showModelCostPicker(pi: ExtensionAPI, ctx: ExtensionCommandContext, args: string): Promise<void> {
	const scoped = args.trim().toLowerCase() === "scoped";
	if (ctx.mode !== "tui") {
		ctx.ui.notify("/models-cost requires interactive mode.", "warning");
		return;
	}

	const models = availableModels(ctx, scoped);
	if (models.length === 0) {
		ctx.ui.notify("No authenticated models are available.", "warning");
		return;
	}

	const registry = ctx.modelRegistry;
	let picker: ModelCostPicker | undefined;
	const selectedKey = await ctx.ui.custom<string | null>((tui, theme, keybindings, done) => {
		picker = new ModelCostPicker({
			tui,
			theme,
			keybindings,
			registry,
			models,
			current: ctx.model,
			scopeLabel: scoped && ctx.scopedModels.length > 0 ? "enabled models" : "all authenticated models",
			done,
		});

		void registry.refresh()
			.then(() => {
				if (!picker) return;
				picker.updateModels(availableModels(ctx, scoped), "Pi model catalog refreshed.");
			})
			.catch(() => {
				picker?.setStatus("Using the current Pi model catalog; refresh failed.");
			});

		return picker;
	});
	picker?.close();

	if (!selectedKey) return;
	const selected = availableModels(ctx, scoped).find((model) => `${model.provider}/${model.id}` === selectedKey);
	if (!selected) {
		ctx.ui.notify("The selected model is no longer available.", "warning");
		return;
	}

	const changed = await pi.setModel(selected);
	if (!changed) {
		ctx.ui.notify(`Could not select ${selected.provider}/${selected.id}; authentication is unavailable.`, "error");
	}
}

export default function modelCostPicker(pi: ExtensionAPI): void {
	pi.registerCommand("models-cost", {
		description: "Pick from all authenticated models while viewing Pi catalog pricing",
		getArgumentCompletions: () => [{ value: "scoped", label: "scoped", description: "Show only enabledModels" }],
		handler: async (args, ctx) => {
			await showModelCostPicker(pi, ctx, args);
		},
	});
}

export { formatRate, formatTokens, formatRates, formatCompactRates, formatCompactCacheRates, formatCompactTiers, createModelRows };
