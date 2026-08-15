import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { decideVisualEmbedding } from '../../../supabase/functions/_shared/visual-embedding-routing';
import {
	compareMultimodalRanked,
	hybridReciprocalRankScore
} from '../../../supabase/functions/_shared/semantic-ranking';

type Candidate = Readonly<{
	id: string;
	lexicalRank: number | null;
	semanticRank: number | null;
	semanticSimilarity: number | null;
	visualRank: number | null;
	visualSimilarity: number | null;
}>;

type Fixture = Readonly<{
	version: string;
	routing: readonly Readonly<{
		id: string;
		contentClass:
			| 'book_clean'
			| 'scan_degraded'
			| 'handwriting'
			| 'mixed'
			| 'table_layout'
			| 'math'
			| 'sparse'
			| 'unknown';
		hasNativeText: boolean;
		warningCount: number;
		needsReview: boolean;
		effectiveTextLength: number;
		wordBoxCount: number;
		eligible: boolean;
	}>[];
	ranking: readonly Readonly<{
		id: string;
		queryKind: 'lexical' | 'conceptual' | 'visual' | 'negative';
		relevant: string;
		baselineTop: string;
		activeTop: string;
		candidates: readonly Candidate[];
	}>[];
}>;

const fixture = JSON.parse(
	readFileSync('tests/fixtures/search/visual-semantic-benchmark.json', 'utf8')
) as Fixture;

function top(candidates: readonly Candidate[], visual: boolean) {
	return [...candidates]
		.sort((left, right) => {
			if (visual) {
				return compareMultimodalRanked(
					{ ...left, stableKey: left.id },
					{ ...right, stableKey: right.id },
					{ visualChannelActive: true }
				);
			}
			const delta = hybridReciprocalRankScore(right) - hybridReciprocalRankScore(left);
			return Math.abs(delta) > Number.EPSILON ? delta : left.id.localeCompare(right.id);
		})
		.at(0)?.id;
}

describe(`adaptive visual benchmark ${fixture.version}`, () => {
	it('covers every routing class from the rollout plan with deterministic expectations', () => {
		for (const sample of fixture.routing) {
			expect(decideVisualEmbedding(sample), sample.id).toMatchObject({ eligible: sample.eligible });
		}
	});

	it('reproduces the two-channel baseline before evaluating the visual candidate', () => {
		for (const sample of fixture.ranking) {
			expect(top(sample.candidates, false), sample.id).toBe(sample.baselineTop);
		}
	});

	it('keeps lexical/negative safety cases stable and recovers the versioned visual targets', () => {
		for (const sample of fixture.ranking) {
			expect(top(sample.candidates, true), sample.id).toBe(sample.activeTop);
		}
	});

	it('contains lexical, conceptual, visual and negative query fixtures', () => {
		expect(new Set(fixture.ranking.map((sample) => sample.queryKind))).toEqual(
			new Set(['lexical', 'conceptual', 'visual', 'negative'])
		);
	});
});
