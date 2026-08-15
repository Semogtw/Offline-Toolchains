#!/usr/bin/env node

import { createHash, randomUUID } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { deflateSync } from 'node:zlib';
import { createClient } from '@supabase/supabase-js';
import { createOcrProbePng } from './ocr-staging-contract.mjs';

const MODEL = 'gemini-embedding-2';
const BUCKET = 'documents';
const RETRY_MS = [0, 5_000, 20_000, 60_000];
const WAIT_MS = 12 * 60_000;
const POLL_MS = 4_000;
const JPEG_BYTES = Uint8Array.from(
	Buffer.from(
		'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',
		'base64'
	)
);
const PNG_SIG = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10]);
const SEMANTIC_CONFIG_SOURCE = await readFile(
	new URL('../../supabase/functions/_shared/semantic-config.ts', import.meta.url),
	'utf8'
);
const VISUAL_THRESHOLD_MATCH = SEMANTIC_CONFIG_SOURCE.match(
	/SEMANTIC_VISUAL_SEARCH_MIN_SIMILARITY\s*=\s*([0-9.]+)/u
);
if (!VISUAL_THRESHOLD_MATCH) throw new Error('Could not resolve visual similarity threshold');
const VISUAL_THRESHOLD = Number(VISUAL_THRESHOLD_MATCH[1]);
if (!Number.isFinite(VISUAL_THRESHOLD)) throw new Error('Invalid visual similarity threshold');

function env(name) {
	const value = process.env[name]?.trim();
	if (!value) throw new Error(`Missing ${name}`);
	return value;
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');

function client() {
	return createClient(env('STAGING_SUPABASE_URL'), env('STAGING_SUPABASE_PUBLISHABLE_KEY'), {
		auth: { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false }
	});
}

async function login(db) {
	const result = await db.auth.signInWithPassword({
		email: env('STAGING_AUTHORIZED_EMAIL'),
		password: env('STAGING_AUTHORIZED_PASSWORD')
	});
	if (result.error || !result.data.user)
		throw new Error(`Sign-in failed: ${result.error?.message ?? 'no user'}`);
	const allowed = await db.rpc('is_authorized_user');
	if (allowed.error || allowed.data !== true) throw new Error('Staging user is not authorized');
	return result.data.user;
}

function functionErrorStatus(error) {
	const context = error && typeof error === 'object' ? error.context : null;
	return context instanceof Response ? context.status : null;
}

async function recoverAuthentication(db, error) {
	if (functionErrorStatus(error) !== 401) return false;
	await login(db);
	return true;
}

function crc32(bytes) {
	let crc = 0xffffffff;
	for (const byte of bytes) {
		crc ^= byte;
		for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
	}
	return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
	const out = Buffer.alloc(12 + data.length);
	out.writeUInt32BE(data.length, 0);
	Buffer.from(type, 'ascii').copy(out, 4);
	Buffer.from(data).copy(out, 8);
	out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
	return out;
}
function patternPng(kind, runNonce) {
	const w = 640,
		h = 420,
		pixels = Buffer.alloc(w * h, 255);
	const dot = (x, y, value = 0) => {
		if (x >= 0 && y >= 0 && x < w && y < h) pixels[y * w + x] = value;
	};
	const line = (x0, y0, x1, y1, t = 3) => {
		const steps = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0));
		for (let i = 0; i <= steps; i += 1) {
			const x = Math.round(x0 + ((x1 - x0) * i) / Math.max(1, steps)),
				y = Math.round(y0 + ((y1 - y0) * i) / Math.max(1, steps));
			for (let dx = -t; dx <= t; dx += 1) for (let dy = -t; dy <= t; dy += 1) dot(x + dx, y + dy);
		}
	};
	const rect = (x, y, rw, rh, t = 3) => {
		line(x, y, x + rw, y, t);
		line(x + rw, y, x + rw, y + rh, t);
		line(x + rw, y + rh, x, y + rh, t);
		line(x, y + rh, x, y, t);
	};
	const fillRect = (x, y, rw, rh, value = 0) => {
		for (let py = y; py <= y + rh; py += 1)
			for (let px = x; px <= x + rw; px += 1) dot(px, py, value);
	};
	const circle = (cx, cy, radius, t = 3) => {
		for (let degree = 0; degree < 360; degree += 1) {
			const angle = (degree * Math.PI) / 180;
			const x = Math.round(cx + Math.cos(angle) * radius),
				y = Math.round(cy + Math.sin(angle) * radius);
			for (let dx = -t; dx <= t; dx += 1) for (let dy = -t; dy <= t; dy += 1) dot(x + dx, y + dy);
		}
	};
	const arrow = (x0, y0, x1, y1) => {
		line(x0, y0, x1, y1, 3);
		const angle = Math.atan2(y1 - y0, x1 - x0),
			length = 18;
		line(
			x1,
			y1,
			Math.round(x1 - Math.cos(angle - 0.55) * length),
			Math.round(y1 - Math.sin(angle - 0.55) * length),
			3
		);
		line(
			x1,
			y1,
			Math.round(x1 - Math.cos(angle + 0.55) * length),
			Math.round(y1 - Math.sin(angle + 0.55) * length),
			3
		);
	};

	if (kind === 'table') {
		rect(70, 55, 500, 310);
		for (const x of [195, 320, 445]) line(x, 55, x, 365, 2);
		for (const y of [132, 210, 287]) line(70, y, 570, y, 2);
	} else if (kind === 'flow') {
		rect(45, 160, 140, 90);
		rect(250, 65, 140, 90);
		rect(455, 160, 140, 90);
		arrow(185, 205, 250, 110);
		arrow(390, 110, 455, 205);
		arrow(455, 245, 185, 245);
	} else if (kind === 'bar') {
		line(90, 340, 560, 340, 3);
		line(90, 340, 90, 70, 3);
		for (const [x, height] of [
			[135, 90],
			[225, 170],
			[315, 120],
			[405, 240],
			[495, 195]
		])
			fillRect(x, 340 - height, 45, height);
	} else if (kind === 'line') {
		line(90, 340, 560, 340, 3);
		line(90, 340, 90, 70, 3);
		const points = [
			[110, 290],
			[200, 220],
			[290, 250],
			[380, 135],
			[470, 180],
			[545, 95]
		];
		for (let i = 1; i < points.length; i += 1)
			line(points[i - 1][0], points[i - 1][1], points[i][0], points[i][1], 3);
		for (const [x, y] of points) circle(x, y, 7, 2);
	} else if (kind === 'pie') {
		circle(320, 210, 145, 4);
		for (const degree of [0, 80, 205]) {
			const angle = (degree * Math.PI) / 180;
			line(
				320,
				210,
				Math.round(320 + Math.cos(angle) * 145),
				Math.round(210 + Math.sin(angle) * 145),
				3
			);
		}
	} else if (kind === 'checklist') {
		for (let row = 0; row < 5; row += 1) {
			const y = 75 + row * 65;
			rect(80, y, 34, 34, 2);
			if (row % 2 === 0) {
				line(86, y + 18, 96, y + 29, 2);
				line(96, y + 29, 111, y + 6, 2);
			}
			line(145, y + 17, 540, y + 17, 2);
		}
	} else if (kind === 'calendar') {
		rect(80, 55, 480, 315, 3);
		line(80, 115, 560, 115, 3);
		for (let col = 1; col < 7; col += 1)
			line(80 + col * (480 / 7), 115, 80 + col * (480 / 7), 370, 1);
		for (let row = 1; row < 5; row += 1) line(80, 115 + row * 51, 560, 115 + row * 51, 1);
		fillRect(82, 57, 476, 55, 210);
	} else if (kind === 'form') {
		rect(105, 45, 430, 330, 3);
		for (const y of [100, 160, 220, 280]) {
			line(140, y - 16, 265, y - 16, 2);
			rect(285, y - 35, 205, 42, 2);
		}
		rect(285, 325, 95, 30, 2);
	} else if (kind === 'mindmap') {
		circle(320, 210, 55, 4);
		for (const [x, y] of [
			[105, 90],
			[535, 90],
			[90, 315],
			[550, 315]
		]) {
			rect(x - 55, y - 28, 110, 56, 2);
			line(
				320 + Math.sign(x - 320) * 45,
				210 + Math.sign(y - 210) * 35,
				x - Math.sign(x - 320) * 55,
				y,
				2
			);
		}
	} else if (kind === 'timeline') {
		line(75, 215, 565, 215, 4);
		for (const [x, up] of [
			[120, true],
			[230, false],
			[340, true],
			[450, false],
			[540, true]
		]) {
			circle(x, 215, 9, 2);
			line(x, 215, x, up ? 105 : 325, 2);
			rect(x - 45, up ? 60 : 325, 90, 48, 2);
		}
	} else if (kind === 'venn') {
		circle(275, 210, 115, 4);
		circle(365, 210, 115, 4);
	} else if (kind === 'hierarchy') {
		rect(255, 45, 130, 55, 2);
		for (const x of [110, 255, 400]) {
			rect(x, 180, 130, 55, 2);
			line(320, 100, 320, 145, 2);
			line(175, 145, 465, 145, 2);
			line(x + 65, 145, x + 65, 180, 2);
		}
		for (const x of [75, 220, 365, 510]) {
			rect(x - 45, 315, 90, 45, 2);
			line(x, 235, x, 315, 1);
		}
	} else if (kind === 'kanban') {
		for (let col = 0; col < 3; col += 1) {
			const x = 55 + col * 195;
			rect(x, 45, 165, 330, 3);
			fillRect(x + 3, 48, 159, 38, 220);
			for (let card = 0; card < 3; card += 1) rect(x + 20, 110 + card * 80, 125, 50, 2);
		}
	} else if (kind === 'route') {
		const points = [
			[80, 310],
			[155, 240],
			[245, 285],
			[330, 175],
			[430, 210],
			[555, 95]
		];
		for (let i = 1; i < points.length; i += 1)
			line(points[i - 1][0], points[i - 1][1], points[i][0], points[i][1], 6);
		for (const [x, y] of points) {
			circle(x, y, 13, 3);
			fillRect(x - 4, y - 4, 8, 8);
		}
	} else throw new Error(`Unknown pattern ${kind}`);

	const scan = Buffer.alloc((w + 1) * h, 255);
	for (let y = 0; y < h; y += 1) {
		scan[y * (w + 1)] = 0;
		pixels.copy(scan, y * (w + 1) + 1, y * w, (y + 1) * w);
	}
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0);
	ihdr.writeUInt32BE(h, 4);
	ihdr[8] = 8;
	ihdr[9] = 0;
	const benchmarkMetadata = Buffer.from(`benchmark-run\0${runNonce}`, 'utf8');
	return Uint8Array.from(
		Buffer.concat([
			Buffer.from(PNG_SIG),
			chunk('IHDR', ihdr),
			chunk('tEXt', benchmarkMetadata),
			chunk('IDAT', deflateSync(scan)),
			chunk('IEND', Buffer.alloc(0))
		])
	);
}

function retryLater(data, pageId) {
	return (
		data?.state === 'partial' &&
		Array.isArray(data.pendingPageIds) &&
		data.pendingPageIds.length === 1 &&
		data.pendingPageIds[0] === pageId &&
		Array.isArray(data.failedPageIds) &&
		data.failedPageIds.length === 0
	);
}
async function runOcr(db, pageId) {
	let result;
	for (const delay of RETRY_MS) {
		if (delay) await sleep(delay);
		result = await db.functions.invoke('process-ocr', { body: { pageIds: [pageId] } });
		if (result.error || !retryLater(result.data, pageId)) break;
	}
	if (result?.error) throw new Error(`OCR failed: ${result.error.message}`);
}

async function makeProbe(db, userId, notebookId, id, bytes, mimeType) {
	const documentId = randomUUID(),
		pageId = randomUUID(),
		jobId = randomUUID();
	const path = `${userId}/staging-probes/${documentId}.png`;
	const upload = await db.storage
		.from(BUCKET)
		.upload(path, bytes, { cacheControl: '0', contentType: mimeType, upsert: false });
	if (upload.error) throw new Error(`${id} upload failed: ${upload.error.message}`);
	const meta = await db.rpc('create_ocr_staging_probe', {
		target_document_id: documentId,
		target_page_id: pageId,
		target_job_id: jobId,
		image_storage_path: path,
		prepared_sha256: hash(bytes),
		prompt_version: 1
	});
	if (meta.error) throw new Error(`${id} metadata failed: ${meta.error.message}`);
	if (notebookId) {
		const update = await db
			.from('documents')
			.update({ notebook_id: notebookId, title: `__visual_${id}__` })
			.eq('id', documentId);
		if (update.error) throw new Error(`${id} notebook assignment failed: ${update.error.message}`);
	}
	await runOcr(db, pageId);
	const page = await db.from('pages').select('status').eq('id', pageId).single();
	if (page.error || !['ready', 'needs_review'].includes(page.data?.status))
		throw new Error(`${id} OCR did not finish successfully`);
	return { id, documentId, pageId, path, mimeType, sha256: hash(bytes) };
}

async function queue(db, probe) {
	const startedAt = Date.now();
	const result = await db.rpc('queue_page_visual_embedding_job', {
		target_page_id: probe.pageId,
		target_model: MODEL,
		target_media_path: probe.path,
		target_mime_type: probe.mimeType,
		target_routing_reason: 'staging_benchmark',
		target_routing_version: 'visual-v1'
	});
	if (result.error || result.data?.queued !== true)
		throw new Error(`${probe.id} visual queue failed: ${result.error?.message ?? 'not queued'}`);
	return startedAt;
}

async function waitVisual(db, probes, queuedAt) {
	const deadline = Date.now() + WAIT_MS;
	while (Date.now() < deadline) {
		const result = await db
			.from('page_visual_embeddings')
			.select('page_id,source_hash,model')
			.in(
				'page_id',
				probes.map((p) => p.pageId)
			);
		if (result.error) throw new Error(`Visual verification failed: ${result.error.message}`);
		if (result.data?.length === probes.length) {
			return probes.map((probe) => {
				const row = result.data.find((item) => item.page_id === probe.pageId);
				if (row?.source_hash !== probe.sha256 || row?.model !== MODEL)
					throw new Error(`${probe.id} hash/model mismatch`);
				return {
					id: probe.id,
					mimeType: probe.mimeType,
					hashMatched: true,
					latencyMs: Date.now() - queuedAt.get(probe.pageId)
				};
			});
		}
		await sleep(POLL_MS);
	}
	const stats = await db.rpc('visual_embedding_stats', { target_model: MODEL });
	const row = Array.isArray(stats.data) ? stats.data[0] : stats.data;
	throw new Error(
		`Visual timeout pending=${row?.pending_jobs ?? '?'} failed=${row?.failed_jobs ?? '?'}`
	);
}

async function waitText(db, notebookId) {
	const deadline = Date.now() + WAIT_MS;
	let last = {};
	while (Date.now() < deadline) {
		const result = await db.rpc('semantic_index_stats', {
			target_model: MODEL,
			notebook_filter: notebookId
		});
		if (result.error) throw new Error(`Text index stats failed: ${result.error.message}`);
		last = Array.isArray(result.data) ? result.data[0] : result.data;
		const totalPages = Number(last?.total_pages ?? 0);
		const indexedPages = Number(last?.indexed_pages ?? 0);
		if (totalPages >= 1 && indexedPages === totalPages) return { totalPages, indexedPages };
		await sleep(POLL_MS);
	}
	throw new Error(`Text index timeout ${last?.indexed_pages ?? 0}/${last?.total_pages ?? 0}`);
}

const QUERIES = [
	{ id: 'lexical', expected: 'lexical', kind: 'lexical', query: 'FICHARIO OCR 2718' },
	{
		id: 'table',
		expected: 'table',
		kind: 'visual',
		query: 'uma grade com células organizadas em linhas e colunas'
	},
	{
		id: 'flow',
		expected: 'flow',
		kind: 'visual',
		query: 'um fluxograma com caixas conectadas por setas'
	},
	{
		id: 'bar',
		expected: 'bar',
		kind: 'visual',
		query: 'um gráfico de barras verticais com alturas diferentes'
	},
	{
		id: 'line',
		expected: 'line',
		kind: 'visual',
		query: 'um gráfico de linha com pontos conectados mostrando uma tendência'
	},
	{ id: 'pie', expected: 'pie', kind: 'visual', query: 'um gráfico circular dividido em fatias' },
	{
		id: 'checklist',
		expected: 'checklist',
		kind: 'visual',
		query: 'uma lista de tarefas com caixas de seleção'
	},
	{
		id: 'calendar',
		expected: 'calendar',
		kind: 'visual',
		query: 'um calendário mensal organizado em uma grade de dias'
	},
	{
		id: 'form',
		expected: 'form',
		kind: 'visual',
		query: 'um formulário com vários campos retangulares para preencher'
	},
	{
		id: 'mindmap',
		expected: 'mindmap',
		kind: 'visual',
		query: 'um mapa mental com um tópico central e quatro ramificações'
	},
	{
		id: 'timeline',
		expected: 'timeline',
		kind: 'visual',
		query: 'uma linha do tempo horizontal com vários marcos'
	},
	{
		id: 'venn',
		expected: 'venn',
		kind: 'visual',
		query: 'um diagrama de venn com dois círculos sobrepostos'
	},
	{
		id: 'hierarchy',
		expected: 'hierarchy',
		kind: 'visual',
		query: 'um organograma hierárquico com caixas conectadas em níveis'
	},
	{
		id: 'kanban',
		expected: 'kanban',
		kind: 'visual',
		query: 'um quadro kanban com três colunas e cartões de tarefas'
	},
	{
		id: 'route',
		expected: 'route',
		kind: 'visual',
		query: 'um mapa esquemático de rota com um caminho ligando vários pontos'
	},
	{
		id: 'negative-dog',
		expected: null,
		kind: 'negative',
		query: 'uma fotografia de cachorro correndo na praia'
	},
	{
		id: 'negative-portrait',
		expected: null,
		kind: 'negative',
		query: 'um retrato fotográfico de uma pessoa sorrindo'
	},
	{
		id: 'negative-landscape',
		expected: null,
		kind: 'negative',
		query: 'uma fotografia colorida de montanhas e céu azul'
	}
];

function normalizeBenchmarkQuery(value) {
	return value
		.normalize('NFKC')
		.replace(/[\u00ad\u200b-\u200d\u2060\ufeff]/gu, '')
		.replace(/\r\n?/g, '\n')
		.replace(/\s+/gu, ' ')
		.trim()
		.toLocaleLowerCase('pt-BR');
}

async function rawVisualSearch(db, query, notebookId, labels) {
	const normalized = normalizeBenchmarkQuery(query);
	const queryHash = createHash('sha256').update(`${MODEL}\nv2\n${normalized}`).digest('hex');
	const cached = await db.rpc('get_cached_semantic_query_embedding', {
		target_model: MODEL,
		target_query_hash: queryHash
	});
	if (cached.error || typeof cached.data !== 'string') {
		return { error: cached.error?.message ?? 'query_embedding_cache_miss', candidates: [] };
	}
	const visual = await db.rpc('search_pages_visual_semantic', {
		query_embedding: cached.data,
		target_model: MODEL,
		notebook_filter: notebookId,
		result_limit: 15
	});
	if (visual.error || !Array.isArray(visual.data)) {
		return { error: visual.error?.message ?? 'invalid_visual_rpc_response', candidates: [] };
	}
	return {
		error: null,
		candidates: visual.data.map((row) => ({
			label: labels.get(row.document_id) ?? null,
			similarity: Number(row.visual_similarity)
		}))
	};
}

async function searches(db, state, expectedMode) {
	const labels = new Map(state.probes.map((p) => [p.documentId, p.id]));
	const rows = [];
	// Staging checks share one account. Renew immediately before the long search
	// phase so another smoke cannot leave this runner with a revoked session.
	await login(db);
	for (const spec of QUERIES) {
		const start = performance.now();
		let result = null;
		let retryCount = 0;
		for (const delay of [0, 2_000, 5_000, 15_000]) {
			if (delay) {
				retryCount += 1;
				await sleep(delay);
			}
			result = await db.functions.invoke('semantic-search', {
				body: { query: spec.query, notebookId: state.notebookId, limit: 15, offset: 0 }
			});
			if (!result.error && Array.isArray(result.data?.results)) break;
			if (result.error) await recoverAuthentication(db, result.error);
		}
		if (!result || result.error || !Array.isArray(result.data?.results))
			throw new Error(
				`${spec.id} search failed after retries: ${result?.error?.message ?? 'invalid response'}`
			);
		if (result.data.mode !== expectedMode)
			throw new Error(`${spec.id} expected ${expectedMode}, got ${result.data.mode}`);
		const rawVisual = await rawVisualSearch(db, spec.query, state.notebookId, labels);
		const expectedRawIndex = spec.expected
			? rawVisual.candidates.findIndex((candidate) => candidate.label === spec.expected)
			: -1;
		rows.push({
			id: spec.id,
			kind: spec.kind,
			expected: spec.expected,
			latencyMs: Math.round(performance.now() - start),
			retryCount,
			resultLabels: result.data.results.map((r) => labels.get(r.documentId)).filter(Boolean),
			resultDetails: result.data.results
				.map((r) => ({
					label: labels.get(r.documentId) ?? null,
					matchMode: r.matchMode ?? null,
					semanticSimilarity: Number(r.semanticSimilarity ?? 0),
					visualSimilarity: Number(r.visualSimilarity ?? 0),
					rank: Number(r.rank ?? 0)
				}))
				.filter((r) => r.label),
			rawVisualError: rawVisual.error,
			rawVisualCandidates: rawVisual.candidates,
			rawVisualExpectedRank: expectedRawIndex < 0 ? null : expectedRawIndex + 1,
			rawVisualExpectedSimilarity:
				expectedRawIndex < 0 ? null : (rawVisual.candidates[expectedRawIndex]?.similarity ?? null),
			reason: result.data.reason ?? null
		});
	}
	return rows;
}
function metric(rows) {
	const positives = rows.filter((r) => r.expected),
		visual = positives.filter((r) => r.kind === 'visual'),
		negatives = rows.filter((r) => r.kind === 'negative');
	const rank = (r) => {
		const i = r.resultLabels.indexOf(r.expected);
		return i < 0 ? null : i + 1;
	};
	const rawRank = (r) => r.rawVisualExpectedRank ?? null;
	const recall = (list, k, ranker = rank) =>
		list.length === 0 ? 0 : list.filter((r) => (ranker(r) ?? 999) <= k).length / list.length;
	const mrr = (list, ranker = rank) =>
		list.length === 0
			? 0
			: list.reduce((sum, r) => sum + (ranker(r) ? 1 / ranker(r) : 0), 0) / list.length;
	const times = rows.map((r) => r.latencyMs).sort((a, b) => a - b);
	const expectedSimilarities = visual
		.map((r) => r.rawVisualExpectedSimilarity)
		.filter((value) => typeof value === 'number' && Number.isFinite(value))
		.sort((a, b) => a - b);
	return {
		recallAt1: recall(positives, 1),
		recallAt3: recall(positives, 3),
		recallAt5: recall(positives, 5),
		mrr: mrr(positives),
		visualRecallAt1: recall(visual, 1),
		visualRecallAt3: recall(visual, 3),
		visualRecallAt5: recall(visual, 5),
		visualMrr: mrr(visual),
		rawVisualRecallAt1: recall(visual, 1, rawRank),
		rawVisualRecallAt3: recall(visual, 3, rawRank),
		rawVisualRecallAt5: recall(visual, 5, rawRank),
		rawVisualMrr: mrr(visual, rawRank),
		rawVisualExpectedSimilarityMedian:
			expectedSimilarities[Math.floor(expectedSimilarities.length / 2)] ?? null,
		visualSimilarityThreshold: VISUAL_THRESHOLD,
		rawVisualExpectedAboveCurrentThreshold: visual.filter(
			(r) =>
				typeof r.rawVisualExpectedSimilarity === 'number' &&
				r.rawVisualExpectedSimilarity >= VISUAL_THRESHOLD
		).length,
		rawVisualNegativeAboveThresholdCount: negatives.reduce(
			(sum, row) =>
				sum +
				row.rawVisualCandidates.filter(
					(candidate) =>
						typeof candidate.similarity === 'number' && candidate.similarity >= VISUAL_THRESHOLD
				).length,
			0
		),
		rawVisualRpcErrors: rows.filter((r) => r.rawVisualError).length,
		lexicalTop: rank(rows.find((r) => r.kind === 'lexical')) === 1,
		negativeCount: negatives.reduce((sum, row) => sum + row.resultLabels.length, 0),
		searchRetries: rows.reduce((sum, row) => sum + (row.retryCount ?? 0), 0),
		latencyMedianMs: times[Math.floor(times.length / 2)] ?? 0,
		latencyP95Ms: times[Math.min(times.length - 1, Math.floor(times.length * 0.95))] ?? 0
	};
}

async function setup(db, user, statePath, reportPath) {
	const notebookId = randomUUID();
	const notebook = await db.from('notebooks').insert({
		id: notebookId,
		user_id: user.id,
		name: `__visual_benchmark_${notebookId.slice(0, 8)}`
	});
	if (notebook.error) throw new Error(`Notebook failed: ${notebook.error.message}`);
	const runNonce = randomUUID();
	const state = { notebookId, runNonce, probes: [], jpegSmoke: null };
	await writeFile(statePath, JSON.stringify(state));
	for (const [id, bytes] of [
		['lexical', createOcrProbePng(`visual-${runNonce}-${randomUUID()}`)],
		['table', patternPng('table', runNonce)],
		['flow', patternPng('flow', runNonce)],
		['bar', patternPng('bar', runNonce)],
		['line', patternPng('line', runNonce)],
		['pie', patternPng('pie', runNonce)],
		['checklist', patternPng('checklist', runNonce)],
		['calendar', patternPng('calendar', runNonce)],
		['form', patternPng('form', runNonce)],
		['mindmap', patternPng('mindmap', runNonce)],
		['timeline', patternPng('timeline', runNonce)],
		['venn', patternPng('venn', runNonce)],
		['hierarchy', patternPng('hierarchy', runNonce)],
		['kanban', patternPng('kanban', runNonce)],
		['route', patternPng('route', runNonce)]
	]) {
		const probe = await makeProbe(db, user.id, notebookId, id, bytes, 'image/png');
		state.probes.push(probe);
		await writeFile(statePath, JSON.stringify(state));
		await sleep(2_000);
	}
	const jpegSeed = await makeProbe(
		db,
		user.id,
		null,
		'jpeg-smoke',
		createOcrProbePng(`jpeg-${randomUUID()}`),
		'image/png'
	);
	const replaced = await db.storage.from(BUCKET).update(jpegSeed.path, JPEG_BYTES, {
		contentType: 'image/jpeg',
		cacheControl: '0',
		upsert: true
	});
	if (replaced.error) throw new Error(`JPEG replacement failed: ${replaced.error.message}`);
	const jpeg = { ...jpegSeed, mimeType: 'image/jpeg', sha256: hash(JPEG_BYTES) };
	state.jpegSmoke = jpeg;
	await writeFile(statePath, JSON.stringify(state));
	const all = [...state.probes, jpeg],
		queuedAt = new Map();
	for (const probe of all) queuedAt.set(probe.pageId, await queue(db, probe));
	const visual = await waitVisual(db, all, queuedAt);
	const textIndex = await waitText(db, notebookId);
	const observations = await searches(db, state, 'hybrid');
	const report = {
		phase: 'shadow',
		status: 'pass',
		visual,
		textIndex,
		observations,
		metrics: metric(observations),
		visualSimilarityThreshold: VISUAL_THRESHOLD,
		quotaSignalObserved: observations.some((r) => r.reason === 'semantic_quota_or_rate_limit'),
		pricing: {
			asOf: '2026-08-14',
			imageInputs: all.length,
			freeTierEstimatedUsd: 0,
			paidStandardEstimatedUsd: Number((all.length * 0.00012).toFixed(6)),
			billingTierKnown: false
		}
	};
	await writeFile(reportPath, JSON.stringify(report, null, 2));
	console.log(`PASS shadow corpus + PNG/JPEG visual smoke: ${all.length} images`);
}

async function measure(db, statePath, reportPath) {
	const state = JSON.parse(await readFile(statePath, 'utf8'));
	const observations = await searches(db, state, 'multimodal');
	const report = {
		phase: 'active',
		status: 'pass',
		observations,
		metrics: metric(observations),
		visualSimilarityThreshold: VISUAL_THRESHOLD,
		quotaSignalObserved: observations.some((r) => r.reason === 'semantic_quota_or_rate_limit')
	};
	await writeFile(reportPath, JSON.stringify(report, null, 2));
	console.log('PASS active multimodal search measured');
}

async function compare(shadowPath, activePath, reportPath) {
	const shadow = JSON.parse(await readFile(shadowPath, 'utf8')),
		active = JSON.parse(await readFile(activePath, 'utf8'));
	const gates = {
		noQuotaSignal: !shadow.quotaSignalObserved && !active.quotaSignalObserved,
		noSearchRetries: shadow.metrics.searchRetries === 0 && active.metrics.searchRetries === 0,
		noVisualRpcErrors:
			shadow.metrics.rawVisualRpcErrors === 0 && active.metrics.rawVisualRpcErrors === 0,
		noRecallRegression: active.metrics.recallAt3 >= shadow.metrics.recallAt3,
		visualImproved: active.metrics.visualMrr >= shadow.metrics.visualMrr + 0.05,
		visualTop1Quality: active.metrics.visualRecallAt1 >= 0.8,
		visualMrrQuality: active.metrics.visualMrr >= 0.8,
		lexicalPreserved: active.metrics.lexicalTop,
		noNegativeVisualThresholdHits: active.metrics.rawVisualNegativeAboveThresholdCount === 0,
		negativeNotWorse: active.metrics.negativeCount <= shadow.metrics.negativeCount,
		latencyAcceptable:
			active.metrics.latencyP95Ms <=
			Math.max(shadow.metrics.latencyP95Ms * 1.8, shadow.metrics.latencyP95Ms + 1500)
	};
	const recommendation = Object.values(gates).every(Boolean) ? 'promote_active' : 'keep_shadow';
	const report = {
		status: 'pass',
		recommendation,
		gates,
		shadow: shadow.metrics,
		active: active.metrics,
		delta: {
			visualMrr: active.metrics.visualMrr - shadow.metrics.visualMrr,
			recallAt3: active.metrics.recallAt3 - shadow.metrics.recallAt3,
			latencyP95Ms: active.metrics.latencyP95Ms - shadow.metrics.latencyP95Ms
		},
		pricing: shadow.pricing
	};
	await writeFile(reportPath, JSON.stringify(report, null, 2));
	console.log(`PASS comparison: ${recommendation}`);
}

async function cleanup(db, statePath, reportPath) {
	const state = JSON.parse(await readFile(statePath, 'utf8'));
	const probes = [...(state.probes ?? []), ...(state.jpegSmoke ? [state.jpegSmoke] : [])];
	const failures = [];
	let count = 0;

	await login(db);
	for (const probe of probes) {
		let deleted = false;
		let lastError = null;
		for (const delay of [0, 500, 1_500, 4_000]) {
			if (delay) await sleep(delay);
			const result = await db.functions.invoke('delete-document', {
				body: { documentId: probe.documentId }
			});
			if (!result.error) {
				deleted = true;
				count += 1;
				break;
			}
			lastError = result.error;
			await recoverAuthentication(db, result.error);
		}
		if (!deleted) {
			failures.push({
				id: probe.id,
				documentId: probe.documentId,
				status: functionErrorStatus(lastError),
				message: lastError?.message ?? 'unknown cleanup error'
			});
		}
	}

	let notebookDeleted = false;
	if (failures.length === 0 && state.notebookId) {
		const notebook = await db.from('notebooks').delete().eq('id', state.notebookId);
		if (notebook.error) failures.push({ id: 'notebook', message: notebook.error.message });
		else notebookDeleted = true;
	}

	const report = {
		status: failures.length === 0 ? 'pass' : 'partial',
		documentsDeleted: count,
		documentsAttempted: probes.length,
		notebookDeleted,
		failures
	};
	await writeFile(reportPath, JSON.stringify(report, null, 2));
	if (failures.length > 0)
		throw new Error(`Cleanup incomplete: ${failures.map((failure) => failure.id).join(', ')}`);
	console.log(`PASS cleanup ${count} documents`);
}

async function main() {
	const phase = env('VISUAL_BENCHMARK_PHASE');
	if (phase === 'compare')
		return compare(
			env('VISUAL_SHADOW_REPORT_PATH'),
			env('VISUAL_ACTIVE_REPORT_PATH'),
			env('VISUAL_COMPARISON_REPORT_PATH')
		);
	const db = client();
	let loggedIn = false;
	try {
		const user = await login(db);
		loggedIn = true;
		if (phase === 'setup-shadow')
			await setup(db, user, env('VISUAL_BENCHMARK_STATE_PATH'), env('VISUAL_SHADOW_REPORT_PATH'));
		else if (phase === 'measure-active')
			await measure(db, env('VISUAL_BENCHMARK_STATE_PATH'), env('VISUAL_ACTIVE_REPORT_PATH'));
		else if (phase === 'cleanup')
			await cleanup(db, env('VISUAL_BENCHMARK_STATE_PATH'), env('VISUAL_CLEANUP_REPORT_PATH'));
		else throw new Error(`Unknown phase ${phase}`);
	} finally {
		if (loggedIn) await db.auth.signOut({ scope: 'local' }).catch(() => undefined);
	}
}
main().catch((error) => {
	console.error(`FAIL ${error instanceof Error ? error.message : String(error)}`);
	process.exitCode = 1;
});
