#!/usr/bin/env node
import { chromium } from "playwright";
import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";

const args = process.argv.slice(2);
const command = args.shift();
const headed = args.includes("--headed");
const timeout = numberOption("--timeout", 20000);
const waitMs = numberOption("--wait-ms", 500);
const maxChars = numberOption("--max-chars", 20000);

function option(name) {
  const index = args.indexOf(name);
  if (index === -1) return undefined;
  const value = args[index + 1];
  args.splice(index, value?.startsWith("--") ? 1 : 2);
  return value;
}

function numberOption(name, fallback) {
  const value = option(name);
  if (value === undefined) return fallback;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) throw new Error(`${name} must be a non-negative number`);
  return parsed;
}

function requireArg(name) {
  const value = args.shift();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function cap(text) {
  const value = String(text ?? "");
  return value.length <= maxChars ? value : `${value.slice(0, maxChars)}\n[truncated at ${maxChars} characters]`;
}

function validateUrl(url) {
  const parsed = new URL(url);
  if (!['http:', 'https:'].includes(parsed.protocol)) throw new Error("Only http(s) URLs are allowed");
  return parsed.href;
}

async function withPage(url, callback) {
  const browser = await chromium.launch({ headless: !headed });
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(validateUrl(url), { waitUntil: "domcontentloaded", timeout });
    if (waitMs > 0) await page.waitForTimeout(waitMs);
    return await callback(page);
  } finally {
    await browser.close();
  }
}

async function search(query) {
  const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
  return withPage(url, async (page) => {
    const results = await page.locator(".result").evaluateAll((items) => items.map((item) => ({
      title: item.querySelector(".result__a")?.textContent?.trim() ?? "",
      url: item.querySelector(".result__a")?.href ?? "",
      snippet: item.querySelector(".result__snippet")?.textContent?.trim() ?? "",
    })).filter((item) => item.title && item.url));
    const bodyText = await page.locator("body").innerText();
    if (results.length === 0 && /captcha|bots use duckduckgo|drag the slider/i.test(bodyText)) {
      throw new Error("DuckDuckGo presented an anti-bot challenge; use a dedicated web-search extension/API or a visible browser session.");
    }
    console.log(JSON.stringify({ query, results }, null, 2));
  });
}

async function fetchPage(url) {
  return withPage(url, async (page) => {
    console.log(JSON.stringify({
      url: page.url(),
      title: await page.title(),
      text: cap(await page.locator("body").innerText()),
    }, null, 2));
  });
}

async function inspect(url) {
  return withPage(url, async (page) => {
    const elements = await page.locator("a, button, input, textarea, select, [role='button'], [role='link']").evaluateAll((items) => items.slice(0, 200).map((item) => ({
      tag: item.tagName.toLowerCase(),
      text: (item.textContent ?? "").trim().replace(/\s+/g, " ").slice(0, 200),
      role: item.getAttribute("role"),
      ariaLabel: item.getAttribute("aria-label"),
      name: item.getAttribute("name"),
      type: item.getAttribute("type"),
      href: item instanceof HTMLAnchorElement ? item.href : undefined,
    })));
    console.log(JSON.stringify({ url: page.url(), title: await page.title(), elements }, null, 2));
  });
}

async function screenshot(url, output) {
  await mkdir(dirname(output), { recursive: true });
  return withPage(url, async (page) => {
    await page.screenshot({ path: output, fullPage: true });
    console.log(JSON.stringify({ url: page.url(), title: await page.title(), screenshot: output }, null, 2));
  });
}

try {
  if (command === "search") await search(requireArg("query"));
  else if (command === "fetch") await fetchPage(requireArg("URL"));
  else if (command === "inspect") await inspect(requireArg("URL"));
  else if (command === "screenshot") await screenshot(requireArg("URL"), requireArg("output path"));
  else throw new Error("Usage: browser.mjs <search|fetch|inspect|screenshot> ... [--headed] [--wait-ms N] [--timeout N] [--max-chars N]");
} catch (error) {
  console.error(`Playwright browser skill failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
}
