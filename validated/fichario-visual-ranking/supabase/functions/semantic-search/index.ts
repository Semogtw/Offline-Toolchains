import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { RequestBodyTooLargeError, readBoundedJson } from '../_shared/bounded-json.ts';
import { corsHeaders, parseAppOrigin } from '../_shared/cors.ts';
import { GeminiEmbeddingHttpError } from '../_shared/gemini-embedding-client.ts';
import {
	SEMANTIC_EMBEDDING_MODEL,
	SEMANTIC_SEARCH_MIN_SIMILARITY,
	SEMANTIC_VISUAL_SEARCH_MIN_SIMILARITY
} from '../_shared/semantic-config.ts';
import { semanticIndexStats } from '../_shared/semantic-index-stats.ts';
import { getSemanticQueryEmbedding } from '../_shared/semantic-query-cache.ts';
import {
	compareMultimodalRanked,
	multimodalReciprocalRankScore
} from '../_shared/semantic-ranking.ts';
import { recordSemanticRetrievalEvent } from '../_shared/semantic-retrieval-telemetry.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_REQUEST_BODY_BYTES = 8 * 1024;
const MAX_QUERY_CHARS = 200;
const MAX_RESULT_LIMIT = 50;
const MAX_OFFSET = 10_000;
const MAX_HYBRID_WINDOW = 100;
const MIN_SEMANTIC_QUERY_CHARS = 3;

type VisualMode = 'off' | 'shadow' | 'active';
type MatchMode =
	| 'lexical'
	| 'semantic'
	| 'visual'
	| 'hybrid'
	| 'lexical_visual'
	| 'semantic_visual'
	| 'hybrid_visual';

type ParsedRequest = Readonly<{
	query: string;
	notebookId: string | null;
	limit: number;
	offset: number;
}>;

type LexicalRow = {
	page_id: string;
	document_id: string;
	document_title: string;
	notebook_id: string | null;
	notebook_name: string | null;
	page_number: number;
	excerpt: string;
	rank: number;
};

type SemanticRow = Omit<LexicalRow, 'rank'> & { semantic_similarity: number };

type VisualRow = Omit<LexicalRow, 'rank' | 'excerpt'> & { visual_similarity: number };

type SearchCandidate = {
	pageId: string;
	documentId: string;
	documentTitle: string;
	notebookId: string | null;
	notebookName: string | null;
	pageNumber: number;
	excerpt: string;
	lexicalRank: number;
	semanticSimilarity: number;
	visualSimilarity: number;
	lexicalPosition: number | null;
	semanticPosition: number | null;
	visualPosition: number | null;
	score: number;
	matchMode: MatchMode;
	stableKey: string;
};

type RpcResponse = Readonly<{ data: unknown; error: unknown }>;

function json(status: number, body: Record<string, unknown>, appOrigin: string | null) {
	return new Response(JSON.stringify(body), {
		status,
		headers: {
			...corsHeaders(appOrigin),
			'Content-Type': 'application/json',
			'Cache-Control': 'no-store'
		}
	});
}

function empty(status: number, appOrigin: string | null) {
	return new Response(null, {
		status,
		headers: { ...corsHeaders(appOrigin), 'Cache-Control': 'no-store' }
	});
}

function parseRequest(value: unknown): ParsedRequest | null {
	if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
	const record = value as Record<string, unknown>;
	const allowed = new Set(['query', 'notebookId', 'limit', 'offset']);
	if (Object.keys(record).some((key) => !allowed.has(key))) return null;
	if (typeof record.query !== 'string') return null;
	const query = record.query.trim();
	if (query.length < 1 || query.length > MAX_QUERY_CHARS) return null;
	const notebookId = record.notebookId ?? null;
	if (notebookId !== null && (typeof notebookId !== 'string' || !UUID.test(notebookId)))
		return null;
	const limit = record.limit ?? 30;
	const offset = record.offset ?? 0;
	if (!Number.isInteger(limit) || Number(limit) < 1 || Number(limit) > MAX_RESULT_LIMIT)
		return null;
	if (!Number.isInteger(offset) || Number(offset) < 0 || Number(offset) > MAX_OFFSET) return null;
	return {
		query,
		notebookId: notebookId as string | null,
		limit: Number(limit),
		offset: Number(offset)
	};
}

function envInteger(name: string, fallback: number, minimum: number, maximum: number) {
	const raw = Deno.env.get(name);
	const value = raw === undefined || raw === '' ? fallback : Number(raw);
	return Number.isInteger(value) && value >= minimum && value <= maximum ? value : fallback;
}

function visualSearchMode(): VisualMode {
	const visualMode = Deno.env.get('SEMANTIC_VISUAL_MODE') ?? 'shadow';
	if (visualMode === 'off' || visualMode === 'active') return visualMode;
	return 'shadow';
}

function validBaseRow(row: Record<string, unknown>) {
	return (
		typeof row.page_id === 'string' &&
		UUID.test(row.page_id) &&
		typeof row.document_id === 'string' &&
		UUID.test(row.document_id) &&
		typeof row.document_title === 'string' &&
		row.document_title.trim().length > 0 &&
		(row.notebook_id === null ||
			(typeof row.notebook_id === 'string' && UUID.test(row.notebook_id))) &&
		(row.notebook_name === null || typeof row.notebook_name === 'string') &&
		(row.notebook_id === null) === (row.notebook_name === null) &&
		Number.isInteger(row.page_number) &&
		Number(row.page_number) >= 1
	);
}

function validLexicalRow(value: unknown): value is LexicalRow {
	if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
	const row = value as Record<string, unknown>;
	return (
		validBaseRow(row) &&
		typeof row.excerpt === 'string' &&
		typeof row.rank === 'number' &&
		Number.isFinite(row.rank) &&
		row.rank >= 0
	);
}

function validSemanticRow(value: unknown): value is SemanticRow {
	if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
	const row = value as Record<string, unknown>;
	return (
		validBaseRow(row) &&
		typeof row.excerpt === 'string' &&
		typeof row.semantic_similarity === 'number' &&
		Number.isFinite(row.semantic_similarity) &&
		row.semantic_similarity >= 0 &&
		row.semantic_similarity <= 1
	);
}

function validVisualRow(value: unknown): value is VisualRow {
	if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
	const row = value as Record<string, unknown>;
	return (
		validBaseRow(row) &&
		typeof row.visual_similarity === 'number' &&
		Number.isFinite(row.visual_similarity) &&
		row.visual_similarity >= 0 &&
		row.visual_similarity <= 1
	);
}

async function lexicalRows(
	supabase: SupabaseClient,
	input: ParsedRequest,
	limit: number,
	offset: number
): Promise<LexicalRow[]> {
	const { data, error } = await supabase.rpc('search_pages', {
		search_query: input.query,
		notebook_filter: input.notebookId,
		result_limit: limit,
		result_offset: offset
	});
	if (error) throw error;
	return Array.isArray(data) ? data.filter(validLexicalRow) : [];
}

function candidateKey(input: { documentId: string; pageNumber: number }) {
	return `${input.documentId}:${String(input.pageNumber).padStart(8, '0')}`;
}

function matchMode(
	candidate: Pick<SearchCandidate, 'lexicalPosition' | 'semanticPosition' | 'visualPosition'>
): MatchMode {
	const lexical = candidate.lexicalPosition !== null;
	const semantic = candidate.semanticPosition !== null;
	const visual = candidate.visualPosition !== null;
	if (lexical && semantic && visual) return 'hybrid_visual';
	if (lexical && semantic) return 'hybrid';
	if (lexical && visual) return 'lexical_visual';
	if (semantic && visual) return 'semantic_visual';
	if (visual) return 'visual';
	if (semantic) return 'semantic';
	return 'lexical';
}

function scoreCandidate(candidate: SearchCandidate, visualChannelActive = false) {
	candidate.matchMode = matchMode(candidate);
	candidate.score = multimodalReciprocalRankScore(
		{
			lexicalRank: candidate.lexicalPosition,
			semanticRank: candidate.semanticPosition,
			semanticSimilarity: candidate.semanticSimilarity,
			visualRank: candidate.visualPosition,
			visualSimilarity: candidate.visualSimilarity
		},
		{ visualChannelActive }
	);
}

function publicCandidate(candidate: SearchCandidate) {
	return {
		pageId: candidate.pageId,
		documentId: candidate.documentId,
		documentTitle: candidate.documentTitle,
		notebookId: candidate.notebookId,
		notebookName: candidate.notebookName,
		pageNumber: candidate.pageNumber,
		excerpt: candidate.excerpt,
		rank: candidate.score,
		lexicalRank: candidate.lexicalRank,
		semanticSimilarity: candidate.semanticSimilarity,
		visualSimilarity: candidate.visualSimilarity,
		matchMode: candidate.matchMode
	};
}

function mergeCandidates(
	lexical: readonly LexicalRow[],
	semantic: readonly SemanticRow[],
	visual: readonly VisualRow[]
) {
	const merged = new Map<string, SearchCandidate>();
	lexical.forEach((row, index) => {
		const candidate: SearchCandidate = {
			pageId: row.page_id,
			documentId: row.document_id,
			documentTitle: row.document_title,
			notebookId: row.notebook_id,
			notebookName: row.notebook_name,
			pageNumber: row.page_number,
			excerpt: row.excerpt.slice(0, 2000),
			lexicalRank: row.rank,
			semanticSimilarity: 0,
			visualSimilarity: 0,
			lexicalPosition: index + 1,
			semanticPosition: null,
			visualPosition: null,
			score: 0,
			matchMode: 'lexical',
			stableKey: candidateKey({ documentId: row.document_id, pageNumber: row.page_number })
		};
		scoreCandidate(candidate);
		merged.set(row.page_id, candidate);
	});

	semantic.forEach((row, index) => {
		if (row.semantic_similarity < SEMANTIC_SEARCH_MIN_SIMILARITY) return;
		const current = merged.get(row.page_id);
		if (current) {
			current.semanticPosition = index + 1;
			current.semanticSimilarity = row.semantic_similarity;
			if (row.semantic_similarity >= 0.62 && row.excerpt.trim()) {
				current.excerpt = row.excerpt.slice(0, 2000);
			}
			scoreCandidate(current);
			return;
		}
		const candidate: SearchCandidate = {
			pageId: row.page_id,
			documentId: row.document_id,
			documentTitle: row.document_title,
			notebookId: row.notebook_id,
			notebookName: row.notebook_name,
			pageNumber: row.page_number,
			excerpt: row.excerpt.slice(0, 2000),
			lexicalRank: 0,
			semanticSimilarity: row.semantic_similarity,
			visualSimilarity: 0,
			lexicalPosition: null,
			semanticPosition: index + 1,
			visualPosition: null,
			score: 0,
			matchMode: 'semantic',
			stableKey: candidateKey({ documentId: row.document_id, pageNumber: row.page_number })
		};
		scoreCandidate(candidate);
		merged.set(row.page_id, candidate);
	});

	const visualChannelActive = visual.some(
		(row) => row.visual_similarity >= SEMANTIC_VISUAL_SEARCH_MIN_SIMILARITY
	);

	visual.forEach((row, index) => {
		if (row.visual_similarity < SEMANTIC_VISUAL_SEARCH_MIN_SIMILARITY) return;
		const current = merged.get(row.page_id);
		if (current) {
			current.visualPosition = index + 1;
			current.visualSimilarity = row.visual_similarity;
			scoreCandidate(current);
			return;
		}
		const candidate: SearchCandidate = {
			pageId: row.page_id,
			documentId: row.document_id,
			documentTitle: row.document_title,
			notebookId: row.notebook_id,
			notebookName: row.notebook_name,
			pageNumber: row.page_number,
			excerpt: '',
			lexicalRank: 0,
			semanticSimilarity: 0,
			visualSimilarity: row.visual_similarity,
			lexicalPosition: null,
			semanticPosition: null,
			visualPosition: index + 1,
			score: 0,
			matchMode: 'visual',
			stableKey: candidateKey({ documentId: row.document_id, pageNumber: row.page_number })
		};
		scoreCandidate(candidate);
		merged.set(row.page_id, candidate);
	});

	for (const candidate of merged.values()) scoreCandidate(candidate, visualChannelActive);

	return [...merged.values()].sort((left, right) =>
		compareMultimodalRanked(
			{
				lexicalRank: left.lexicalPosition,
				semanticRank: left.semanticPosition,
				semanticSimilarity: left.semanticSimilarity,
				visualRank: left.visualPosition,
				visualSimilarity: left.visualSimilarity,
				stableKey: left.stableKey
			},
			{
				lexicalRank: right.lexicalPosition,
				semanticRank: right.semanticPosition,
				semanticSimilarity: right.semanticSimilarity,
				visualRank: right.visualPosition,
				visualSimilarity: right.visualSimilarity,
				stableKey: right.stableKey
			},
			{ visualChannelActive }
		)
	);
}

async function recordVisualSearchEvent(input: {
	supabase: SupabaseClient;
	visualMode: Exclude<VisualMode, 'off'>;
	visual: readonly VisualRow[];
	textualPageIds: ReadonlySet<string>;
	visualRpcFailed: boolean;
	startedAt: number;
}) {
	const overlapCount = input.visual.filter((row) => input.textualPageIds.has(row.page_id)).length;
	try {
		await input.supabase.rpc('record_semantic_visual_event', {
			event_operation: input.visualMode === 'active' ? 'search_visible' : 'search_shadow',
			event_model: SEMANTIC_EMBEDDING_MODEL,
			event_item_count: input.visual.length,
			event_overlap_count: overlapCount,
			event_bytes_total: 0,
			event_duration_ms: Math.max(
				0,
				Math.min(300_000, Math.round(performance.now() - input.startedAt))
			),
			event_status: input.visualRpcFailed ? 'search_error' : 'success',
			event_routing_reason: null,
			event_routing_version: null
		});
	} catch {
		// Visual search telemetry is best effort and cannot alter visible search.
	}
}

async function fallbackResponse(input: {
	supabase: SupabaseClient;
	parsed: ParsedRequest;
	reason: string;
	startedAt: number;
	embeddingModel?: string | null;
	index?: Awaited<ReturnType<typeof semanticIndexStats>> | null;
}) {
	const rows = await lexicalRows(
		input.supabase,
		input.parsed,
		input.parsed.limit,
		input.parsed.offset
	);
	await recordSemanticRetrievalEvent(input.supabase, {
		surface: 'global_search',
		mode: 'fallback',
		model: input.embeddingModel ?? null,
		resultCount: rows.length,
		lexicalOnlyCount: rows.length,
		totalPages: input.index?.totalPages ?? null,
		indexedPages: input.index?.indexedPages ?? null,
		durationMs: performance.now() - input.startedAt,
		queryEmbeddingCacheHit: null,
		fallbackReason: input.reason
	});
	return {
		mode: 'lexical',
		reason: input.reason,
		embeddingModel: input.embeddingModel ?? null,
		index: input.index ?? null,
		hasMore: rows.length === input.parsed.limit,
		results: rows.map((row, position) => {
			const candidate: SearchCandidate = {
				pageId: row.page_id,
				documentId: row.document_id,
				documentTitle: row.document_title,
				notebookId: row.notebook_id,
				notebookName: row.notebook_name,
				pageNumber: row.page_number,
				excerpt: row.excerpt.slice(0, 2000),
				lexicalRank: row.rank,
				semanticSimilarity: 0,
				visualSimilarity: 0,
				lexicalPosition: position + 1,
				semanticPosition: null,
				visualPosition: null,
				score: 0,
				matchMode: 'lexical',
				stableKey: candidateKey({ documentId: row.document_id, pageNumber: row.page_number })
			};
			scoreCandidate(candidate);
			return publicCandidate(candidate);
		})
	};
}

Deno.serve(async (request) => {
	const appOrigin = parseAppOrigin(
		Deno.env.get('APP_ORIGIN_ALLOWLIST') ?? Deno.env.get('APP_ORIGIN'),
		request.headers.get('Origin')
	);
	const respond = (status: number, body: Record<string, unknown>) => json(status, body, appOrigin);
	if (!appOrigin) return respond(503, { code: 'search_not_configured' });
	if (request.method === 'OPTIONS') return empty(204, appOrigin);
	if (request.method !== 'POST') return respond(405, { code: 'method_not_allowed' });

	const authorization = request.headers.get('Authorization');
	if (!authorization?.startsWith('Bearer ')) {
		return respond(401, { code: 'authentication_required' });
	}

	let raw: unknown;
	try {
		raw = await readBoundedJson(request, MAX_REQUEST_BODY_BYTES);
	} catch (error) {
		return error instanceof RequestBodyTooLargeError
			? respond(413, { code: 'search_request_too_large' })
			: respond(400, { code: 'invalid_json' });
	}
	const parsed = parseRequest(raw);
	if (!parsed) return respond(400, { code: 'invalid_search_request' });

	const supabaseUrl = Deno.env.get('SUPABASE_URL');
	const publishableKey = Deno.env.get('SUPABASE_ANON_KEY');
	if (!supabaseUrl || !publishableKey) return respond(503, { code: 'search_not_configured' });
	const supabase = createClient(supabaseUrl, publishableKey, {
		global: { headers: { Authorization: authorization } },
		auth: { persistSession: false, autoRefreshToken: false }
	});
	const {
		data: { user },
		error: userError
	} = await supabase.auth.getUser();
	if (userError || !user) return respond(401, { code: 'authentication_required' });

	const startedAt = performance.now();
	const abort = new AbortController();
	const timeout = setTimeout(
		() => abort.abort(),
		envInteger('SEMANTIC_SEARCH_TIMEOUT_MS', 30_000, 5_000, 90_000)
	);

	try {
		const apiKey = Deno.env.get('GEMINI_API_KEY');
		const semanticAllowed =
			parsed.query.length >= MIN_SEMANTIC_QUERY_CHARS &&
			Boolean(apiKey) &&
			parsed.offset + parsed.limit <= MAX_HYBRID_WINDOW;

		if (!semanticAllowed) {
			let reason = 'semantic_not_configured';
			if (parsed.query.length < MIN_SEMANTIC_QUERY_CHARS) reason = 'query_too_short';
			else if (parsed.offset + parsed.limit > MAX_HYBRID_WINDOW) {
				reason = 'semantic_window_exhausted';
			}
			return respond(200, await fallbackResponse({ supabase, parsed, reason, startedAt }));
		}

		let queryEmbedding: Awaited<ReturnType<typeof getSemanticQueryEmbedding>>;
		try {
			queryEmbedding = await getSemanticQueryEmbedding({
				supabase,
				apiKey: apiKey!,
				query: parsed.query,
				surface: 'search',
				signal: abort.signal
			});
		} catch (error) {
			if (error instanceof DOMException && error.name === 'AbortError') throw error;
			const index = await semanticIndexStats(supabase, parsed.notebookId).catch(() => null);
			return respond(
				200,
				await fallbackResponse({
					supabase,
					parsed,
					reason:
						error instanceof GeminiEmbeddingHttpError && error.status === 429
							? 'semantic_quota_or_rate_limit'
							: 'semantic_provider_unavailable',
					startedAt,
					embeddingModel: SEMANTIC_EMBEDDING_MODEL,
					index
				})
			);
		}

		const candidateLimit = Math.min(
			MAX_HYBRID_WINDOW,
			Math.max(parsed.offset + parsed.limit + 20, parsed.limit * 2)
		);
		const visualMode = visualSearchMode();
		const visualRequest =
			visualMode === 'off'
				? Promise.resolve<RpcResponse>({ data: [], error: null })
				: supabase.rpc('search_pages_visual_semantic', {
						query_embedding: queryEmbedding.vectorText,
						target_model: SEMANTIC_EMBEDDING_MODEL,
						notebook_filter: parsed.notebookId,
						result_limit: Math.min(50, candidateLimit)
					});
		const [lexical, semanticResponse, visualResponse] = await Promise.all([
			lexicalRows(supabase, parsed, candidateLimit, 0),
			supabase.rpc('search_pages_semantic', {
				query_embedding: queryEmbedding.vectorText,
				target_model: SEMANTIC_EMBEDDING_MODEL,
				notebook_filter: parsed.notebookId,
				result_limit: Math.min(50, candidateLimit)
			}),
			visualRequest
		]);
		if (semanticResponse.error) {
			const index = await semanticIndexStats(supabase, parsed.notebookId).catch(() => null);
			return respond(
				200,
				await fallbackResponse({
					supabase,
					parsed,
					reason: 'semantic_rpc_unavailable',
					startedAt,
					embeddingModel: SEMANTIC_EMBEDDING_MODEL,
					index
				})
			);
		}

		const semantic = Array.isArray(semanticResponse.data)
			? semanticResponse.data.filter(validSemanticRow)
			: [];
		const visual =
			!visualResponse.error && Array.isArray(visualResponse.data)
				? visualResponse.data.filter(validVisualRow)
				: [];
		const textualRanked = mergeCandidates(lexical, semantic, []);
		if (visualMode !== 'off') {
			await recordVisualSearchEvent({
				supabase,
				visualMode,
				visual,
				textualPageIds: new Set(textualRanked.map((candidate) => candidate.pageId)),
				visualRpcFailed: Boolean(visualResponse.error),
				startedAt
			});
		}

		// Shadow is the production default: visual candidates are measured but
		// cannot alter user-visible ordering until benchmark calibration promotes
		// the mode explicitly to active.
		const ranked = mergeCandidates(lexical, semantic, visualMode === 'active' ? visual : []);
		const end = parsed.offset + parsed.limit;
		const results = ranked.slice(parsed.offset, end).map(publicCandidate);
		const index = await semanticIndexStats(supabase, parsed.notebookId).catch(() => null);
		const lexicalOnlyCount = ranked.filter((item) => item.matchMode === 'lexical').length;
		const semanticOnlyCount = ranked.filter((item) => item.matchMode === 'semantic').length;
		const hybridCount = ranked.length - lexicalOnlyCount - semanticOnlyCount;
		await recordSemanticRetrievalEvent(supabase, {
			surface: 'global_search',
			mode: semanticOnlyCount > 0 || hybridCount > 0 ? 'hybrid' : 'lexical',
			model: SEMANTIC_EMBEDDING_MODEL,
			resultCount: results.length,
			lexicalOnlyCount,
			semanticOnlyCount,
			hybridCount,
			totalPages: index?.totalPages ?? null,
			indexedPages: index?.indexedPages ?? null,
			durationMs: performance.now() - startedAt,
			queryEmbeddingCacheHit: queryEmbedding.cacheHit
		});

		return respond(200, {
			mode: visualMode === 'active' ? 'multimodal' : 'hybrid',
			reason: null,
			embeddingModel: SEMANTIC_EMBEDDING_MODEL,
			index,
			queryEmbeddingCacheHit: queryEmbedding.cacheHit,
			hasMore: ranked.length > end || lexical.length === candidateLimit,
			results
		});
	} catch (error) {
		if (error instanceof DOMException && error.name === 'AbortError') {
			return respond(504, { code: 'search_timeout' });
		}
		return respond(503, { code: 'search_unavailable' });
	} finally {
		clearTimeout(timeout);
	}
});
