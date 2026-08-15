import {
	SEMANTIC_RRF_BOTH_BONUS,
	SEMANTIC_RRF_EXACT_LEXICAL_GUARD_BONUS,
	SEMANTIC_RRF_K,
	SEMANTIC_RRF_LEXICAL_WEIGHT,
	SEMANTIC_RRF_VECTOR_WEIGHT,
	SEMANTIC_RRF_VISUAL_BONUS,
	SEMANTIC_RRF_VISUAL_CONFIDENCE_MARGIN_CAP,
	SEMANTIC_RRF_VISUAL_CONFIDENCE_WEIGHT,
	SEMANTIC_RRF_VISUAL_WEIGHT,
	SEMANTIC_VISUAL_SEARCH_MIN_SIMILARITY
} from './semantic-config.ts';

export type HybridRankingSignal = Readonly<{
	lexicalRank: number | null;
	semanticRank: number | null;
	semanticSimilarity?: number | null;
}>;

export type MultimodalRankingSignal = HybridRankingSignal &
	Readonly<{
		visualRank: number | null;
		visualSimilarity?: number | null;
	}>;

export type MultimodalRankingOptions = Readonly<{
	visualChannelActive?: boolean;
}>;

type StableHybridRankingSignal = HybridRankingSignal & { stableKey: string };
type StableMultimodalRankingSignal = MultimodalRankingSignal & { stableKey: string };

function reciprocalRank(rank: number | null, weight: number) {
	if (rank === null || !Number.isFinite(rank) || rank < 1) return 0;
	return weight / (SEMANTIC_RRF_K + rank);
}

function boundedSimilarity(value: number | null | undefined) {
	return Math.max(0, Math.min(1, value ?? 0));
}

export function hybridReciprocalRankScore(signal: HybridRankingSignal) {
	const lexical = reciprocalRank(signal.lexicalRank, SEMANTIC_RRF_LEXICAL_WEIGHT);
	const semantic = reciprocalRank(signal.semanticRank, SEMANTIC_RRF_VECTOR_WEIGHT);
	const both =
		signal.lexicalRank !== null && signal.semanticRank !== null ? SEMANTIC_RRF_BOTH_BONUS : 0;
	const similarityTieBreak = boundedSimilarity(signal.semanticSimilarity) * 0.0001;
	return lexical + semantic + both + similarityTieBreak;
}

/**
 * Visual evidence complements the textual RRF without adding correlated OCR
 * and image scores twice. A text+visual candidate receives the stronger channel
 * plus a small corroboration bonus. Pure visual candidates retain their visual
 * score. Confidence is bounded to the measured staging calibration window.
 * Exact lexical rank one is guarded only while visual ranking is active, which
 * leaves the legacy two-channel score byte-for-byte equivalent in off/shadow.
 */
export function multimodalReciprocalRankScore(
	signal: MultimodalRankingSignal,
	options: MultimodalRankingOptions = {}
) {
	const base = hybridReciprocalRankScore(signal);
	const lexicalGuard =
		options.visualChannelActive === true && signal.lexicalRank === 1
			? SEMANTIC_RRF_EXACT_LEXICAL_GUARD_BONUS
			: 0;
	if (signal.visualRank === null) return base + lexicalGuard;

	const similarity = boundedSimilarity(signal.visualSimilarity);
	const confidenceMargin = Math.min(
		SEMANTIC_RRF_VISUAL_CONFIDENCE_MARGIN_CAP,
		Math.max(0, similarity - SEMANTIC_VISUAL_SEARCH_MIN_SIMILARITY)
	);
	const confidence = confidenceMargin * SEMANTIC_RRF_VISUAL_CONFIDENCE_WEIGHT;
	const visual =
		reciprocalRank(signal.visualRank, SEMANTIC_RRF_VISUAL_WEIGHT) +
		confidence +
		similarity * 0.00002;
	const hasTextSignal = signal.lexicalRank !== null || signal.semanticRank !== null;
	if (!hasTextSignal) return visual;
	return Math.max(base + lexicalGuard, visual) + SEMANTIC_RRF_VISUAL_BONUS;
}

export function compareHybridRanked(a: StableHybridRankingSignal, b: StableHybridRankingSignal) {
	const scoreDelta = hybridReciprocalRankScore(b) - hybridReciprocalRankScore(a);
	if (Math.abs(scoreDelta) > Number.EPSILON) return scoreDelta;
	return a.stableKey.localeCompare(b.stableKey);
}

export function compareMultimodalRanked(
	a: StableMultimodalRankingSignal,
	b: StableMultimodalRankingSignal,
	options: MultimodalRankingOptions = {}
) {
	const scoreDelta =
		multimodalReciprocalRankScore(b, options) - multimodalReciprocalRankScore(a, options);
	if (Math.abs(scoreDelta) > Number.EPSILON) return scoreDelta;
	return a.stableKey.localeCompare(b.stableKey);
}
