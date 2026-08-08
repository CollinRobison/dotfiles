import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Editor, type EditorTheme, Key, matchesKey, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import { Type } from "typebox";

type RawQuestionOption = string | { value?: string; label: string; description?: string };
type RawQuestion = {
	id: string;
	label?: string;
	prompt: string;
	options: RawQuestionOption[];
	multiSelect?: boolean;
	allowOther?: boolean;
};
type QuestionOption = { value: string; label: string; description?: string };
type Question = {
	id: string;
	label: string;
	prompt: string;
	options: QuestionOption[];
	multiSelect: boolean;
	allowOther: boolean;
};
type AnswerValue = string | string[];
type QuestionnaireResult = { answers: Record<string, AnswerValue>; cancelled: boolean };

const QuestionOptionSchema = Type.Union([
	Type.String({ description: "Option label and value" }),
	Type.Object({
		value: Type.Optional(Type.String({ description: "Returned value; defaults to label" })),
		label: Type.String({ description: "Displayed option label" }),
		description: Type.Optional(Type.String({ description: "Optional option description" })),
	}),
]);

const QuestionFields = {
	prompt: Type.String({ description: "Question text" }),
	options: Type.Array(QuestionOptionSchema, { description: "Available choices" }),
	multiSelect: Type.Optional(Type.Boolean({ description: "Allow multiple choices; explicit opt-in" })),
	allowOther: Type.Optional(Type.Boolean({ description: "Add an Other / write your own choice (default true)" })),
};

function normalizeQuestion(raw: RawQuestion, index: number): Question {
	return {
		id: raw.id,
		label: raw.label ?? `Q${index + 1}`,
		prompt: raw.prompt,
		multiSelect: raw.multiSelect === true,
		allowOther: raw.allowOther !== false,
		options: raw.options.map((option) => typeof option === "string"
			? { value: option, label: option }
			: { value: option.value ?? option.label, label: option.label, description: option.description }),
	};
}

function normalizeQuestions(raw: RawQuestion[]): Question[] {
	return raw.map(normalizeQuestion);
}

async function collectQuestionnaire(ctx: ExtensionContext, questions: Question[]): Promise<QuestionnaireResult> {
	return (await ctx.ui.custom<QuestionnaireResult>((tui, theme, _keybindings, done) => {
		let currentTab = 0;
		let inputMode = false;
		let inputQuestionId: string | undefined;
		let cachedLines: string[] | undefined;
		const optionIndexes = new Map<string, number>();
		const selectedIndexes = new Map<string, Set<number>>();
		const customAnswers = new Map<string, string>();
		const isMultiQuestion = questions.length > 1 || questions.some((question) => question.multiSelect);
		const submitTab = questions.length;
		const totalTabs = questions.length + 1;

		const editorTheme: EditorTheme = {
			borderColor: (text) => theme.fg("accent", text),
			selectList: {
				selectedPrefix: (text) => theme.fg("accent", text),
				selectedText: (text) => theme.fg("accent", text),
				description: (text) => theme.fg("muted", text),
				scrollInfo: (text) => theme.fg("dim", text),
				noMatch: (text) => theme.fg("warning", text),
			},
		};
		const editor = new Editor(tui, editorTheme);

		const refresh = () => {
			cachedLines = undefined;
			tui.requestRender();
		};
		const currentQuestion = () => questions[currentTab];
		const optionsFor = (question: Question) => question.options.length + (question.allowOther ? 1 : 0);
		const otherIndex = (question: Question) => question.options.length;
		const selectedFor = (question: Question) => {
			let selected = selectedIndexes.get(question.id);
			if (!selected) {
				selected = new Set<number>();
				selectedIndexes.set(question.id, selected);
			}
			return selected;
		};
		const optionIndexFor = (question: Question) => optionIndexes.get(question.id) ?? 0;
		const customFor = (question: Question) => customAnswers.get(question.id)?.trim() ?? "";

		function buildAnswers(): Record<string, AnswerValue> {
			const result: Record<string, AnswerValue> = {};
			for (const question of questions) {
				const selected = selectedFor(question);
				const values = question.options
					.filter((_option, index) => selected.has(index))
					.map((option) => option.value);
				const custom = customFor(question);
				if (custom) values.push(custom);
				result[question.id] = question.multiSelect ? values : (values[0] ?? "");
			}
			return result;
		}

		function hasResponse(question: Question): boolean {
			return selectedFor(question).size > 0 || Boolean(customFor(question));
		}

		function allRequiredAnswered(): boolean {
			return questions.every((question) => hasResponse(question));
		}

		function submit(cancelled: boolean): void {
			done({ answers: buildAnswers(), cancelled });
		}

		function advance(): void {
			const question = currentQuestion();
			if (question && !hasResponse(question)) {
				refresh();
				return;
			}
			if (!isMultiQuestion) {
				submit(false);
				return;
			}
			currentTab = currentTab < questions.length - 1 ? currentTab + 1 : submitTab;
			refresh();
		}

		function beginOtherInput(question: Question): void {
			inputMode = true;
			inputQuestionId = question.id;
			editor.setText(customFor(question));
			refresh();
		}

		function toggleOption(question: Question, index: number): void {
			const selected = selectedFor(question);
			if (question.multiSelect) {
				if (selected.has(index)) selected.delete(index);
				else selected.add(index);
			} else {
				selected.clear();
				selected.add(index);
			}
		}

		editor.onSubmit = (value) => {
			if (!inputQuestionId) return;
			const question = questions.find((candidate) => candidate.id === inputQuestionId);
			if (!question) return;
			const text = value.trim();
			if (text) {
				customAnswers.set(question.id, text);
				selectedFor(question).add(otherIndex(question));
			} else {
				customAnswers.delete(question.id);
				selectedFor(question).delete(otherIndex(question));
			}
			inputMode = false;
			inputQuestionId = undefined;
			editor.setText("");
			if (!question.multiSelect && text) advance();
			else refresh();
		};

		function handleInput(data: string): void {
			if (inputMode) {
				if (matchesKey(data, Key.escape)) {
					inputMode = false;
					inputQuestionId = undefined;
					editor.setText("");
					refresh();
					return;
				}
				editor.handleInput(data);
				refresh();
				return;
			}

			if (isMultiQuestion && (matchesKey(data, Key.tab) || matchesKey(data, Key.right))) {
				currentTab = (currentTab + 1) % totalTabs;
				refresh();
				return;
			}
			if (isMultiQuestion && (matchesKey(data, Key.shift("tab")) || matchesKey(data, Key.left))) {
				currentTab = (currentTab - 1 + totalTabs) % totalTabs;
				refresh();
				return;
			}

			if (currentTab === submitTab) {
				if (matchesKey(data, Key.enter) && allRequiredAnswered()) submit(false);
				else if (matchesKey(data, Key.escape)) submit(true);
				return;
			}

			const question = currentQuestion();
			if (!question) return;
			const count = optionsFor(question);
			const index = optionIndexFor(question);
			if (matchesKey(data, Key.up)) {
				optionIndexes.set(question.id, Math.max(0, index - 1));
				refresh();
				return;
			}
			if (matchesKey(data, Key.down)) {
				optionIndexes.set(question.id, Math.min(count - 1, index + 1));
				refresh();
				return;
			}
			if (matchesKey(data, Key.space) && question.multiSelect && index < question.options.length) {
				toggleOption(question, index);
				refresh();
				return;
			}
			if (matchesKey(data, Key.enter)) {
				if (question.allowOther && index === otherIndex(question)) {
					beginOtherInput(question);
					return;
				}
				if (!question.multiSelect) toggleOption(question, index);
				else if (!selectedFor(question).has(index)) toggleOption(question, index);
				advance();
				return;
			}
			if (matchesKey(data, Key.escape)) submit(true);
		}

		function addWrappedWithPrefix(lines: string[], width: number, prefix: string, text: string): void {
			const prefixWidth = visibleWidth(prefix);
			const wrapped = wrapTextWithAnsi(text, Math.max(1, width - prefixWidth));
			const continuation = " ".repeat(prefixWidth);
			for (let index = 0; index < wrapped.length; index++) {
				lines.push(`${index === 0 ? prefix : continuation}${wrapped[index]}`);
			}
		}

		function render(width: number): string[] {
			if (cachedLines) return cachedLines;
			const renderWidth = Math.max(1, width);
			const lines: string[] = [theme.fg("accent", "─".repeat(renderWidth))];
			const question = currentQuestion();

			if (isMultiQuestion) {
				const tabs = ["← "];
				for (const candidate of questions) {
					const active = candidate.id === question?.id;
					const marker = hasResponse(candidate) ? "■" : "□";
					const text = ` ${marker} ${candidate.label} `;
					tabs.push(`${active ? theme.bg("selectedBg", theme.fg("text", text)) : theme.fg(hasResponse(candidate) ? "success" : "muted", text)} `);
				}
				const submitText = " ✓ Submit ";
				tabs.push(`${currentTab === submitTab ? theme.bg("selectedBg", theme.fg("text", submitText)) : theme.fg(allRequiredAnswered() ? "success" : "dim", submitText)} →`);
				addWrappedWithPrefix(lines, renderWidth, " ", tabs.join(""));
				lines.push("");
			}

			if (inputMode && question) {
				addWrappedWithPrefix(lines, renderWidth, " ", theme.fg("text", question.prompt));
				lines.push("");
				addWrappedWithPrefix(lines, renderWidth, " ", theme.fg("muted", "Your answer:"));
				for (const line of editor.render(Math.max(1, renderWidth - 2))) lines.push(` ${line}`);
			} else if (currentTab === submitTab) {
				addWrappedWithPrefix(lines, renderWidth, " ", theme.fg("accent", theme.bold("Review answers")));
				lines.push("");
				for (const candidate of questions) {
					const answer = buildAnswers()[candidate.id];
					const display = Array.isArray(answer) ? (answer.length ? answer.join(", ") : "(none)") : (answer || "(unanswered)");
					addWrappedWithPrefix(lines, renderWidth, " ", `${theme.fg("muted", `${candidate.label}: `)}${theme.fg("text", display)}`);
				}
				lines.push("");
				addWrappedWithPrefix(lines, renderWidth, " ", theme.fg(allRequiredAnswered() ? "success" : "warning", allRequiredAnswered() ? "Enter to submit" : "Answer every question before submitting"));
			} else if (question) {
				addWrappedWithPrefix(lines, renderWidth, " ", theme.fg("text", question.prompt));
				lines.push("");
				const selected = selectedFor(question);
				for (let index = 0; index < question.options.length + (question.allowOther ? 1 : 0); index++) {
					const other = question.allowOther && index === otherIndex(question);
					const highlighted = index === optionIndexFor(question);
					const checked = selected.has(index) || (other && Boolean(customFor(question)));
					const marker = question.multiSelect ? (checked ? "[x]" : "[ ]") : (checked ? "(*)" : "( )");
					const option = question.options[index];
					const label = other ? "Other / write your own" : option?.label ?? "";
					const prefix = highlighted ? theme.fg("accent", "> ") : "  ";
					addWrappedWithPrefix(lines, renderWidth, prefix, theme.fg(highlighted ? "accent" : "text", `${marker} ${label}${other && inputMode ? " ✎" : ""}`));
					if (!other && option?.description) addWrappedWithPrefix(lines, renderWidth, "     ", theme.fg("muted", option.description));
				}
			}

			lines.push("");
			const help = inputMode
				? "Enter submit · Esc back"
				: isMultiQuestion ? "Tab/←→ questions · ↑↓ choices · Space toggle · Enter next · Esc cancel" : "↑↓ choices · Space toggle · Enter select · Esc cancel";
			addWrappedWithPrefix(lines, renderWidth, " ", theme.fg("dim", help));
			lines.push(theme.fg("accent", "─".repeat(renderWidth)));
			cachedLines = lines;
			return lines;
		}

		return { render, invalidate: () => { cachedLines = undefined; }, handleInput };
	}) as QuestionnaireResult);
}

const QuestionOptionFields = {
	question: Type.String({ description: "The question to ask" }),
	options: Type.Array(Type.Object({
		label: Type.String({ description: "Option label" }),
		value: Type.Optional(Type.String({ description: "Returned value; defaults to label" })),
		description: Type.Optional(Type.String({ description: "Optional option description" })),
	})),
	multiSelect: Type.Optional(Type.Boolean({ description: "Allow multiple choices; explicit opt-in" })),
	allowOther: Type.Optional(Type.Boolean({ description: "Add an Other / write your own choice (default true)" })),
};

export default function piQuestionnaire(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "question",
		label: "Question",
		description: "Ask the user to choose one option or write another answer.",
		executionMode: "sequential",
		parameters: Type.Object(QuestionOptionFields),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			if (ctx.mode !== "tui") return { content: [{ type: "text", text: "Question unavailable outside interactive mode." }], details: { answer: null, cancelled: true } };
			const question = normalizeQuestion({ id: "question", prompt: params.question, options: params.options, multiSelect: params.multiSelect, allowOther: params.allowOther }, 0);
			const result = await collectQuestionnaire(ctx, [question]);
			const answer = result.cancelled ? null : result.answers.question ?? (question.multiSelect ? [] : "");
			return {
				content: [{ type: "text", text: result.cancelled ? "User cancelled the question." : `User answer: ${JSON.stringify(answer)}` }],
				details: { answer, question: params.question, cancelled: result.cancelled },
			};
		},
	});

	pi.registerTool({
		name: "questionnaire",
		label: "Questionnaire",
		description: "Ask one or more questions with revisitable tabs, single-select or explicit multi-select choices, and an Other / write your own option.",
		executionMode: "sequential",
		parameters: Type.Object({
			questions: Type.Array(Type.Object({
				id: Type.String({ description: "Question identifier" }),
				label: Type.Optional(Type.String({ description: "Short tab label" })),
				...QuestionFields,
			})),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			if (ctx.mode !== "tui") return { content: [{ type: "text", text: "Questionnaire unavailable outside interactive mode." }], details: { answers: {}, cancelled: true } };
			if (params.questions.length === 0) return { content: [{ type: "text", text: "Questionnaire has no questions." }], details: { answers: {}, cancelled: true } };
			const result = await collectQuestionnaire(ctx, normalizeQuestions(params.questions));
			return { content: [{ type: "text", text: JSON.stringify(result.answers) }], details: result };
		},
	});
}
