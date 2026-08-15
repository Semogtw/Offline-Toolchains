import { existsSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const script = readFileSync('tools/checks/check-visual-semantic-staging.mjs', 'utf8');
const workflow = readFileSync('.github/workflows/verify-adaptive-visual-staging.yml', 'utf8');

describe('visual staging benchmark contract', () => {
	it('keeps one canonical post-deploy visual benchmark workflow', () => {
		expect(workflow).toContain('workflows: [Deploy Supabase staging]');
		expect(workflow).toContain('check-visual-semantic-staging.mjs');
		expect(workflow).toContain('SEMANTIC_VISUAL_MODE=shadow');
		for (const obsolete of [
			'.github/workflows/run-visual-staging-now.yml',
			'.github/workflows/diagnose-visual15-shadow-now.yml',
			'.github/workflows/cleanup-visual15-residue-now.yml',
			'.github/workflows/check-visual-rrf-calibration.yml'
		])
			expect(existsSync(obsolete), obsolete).toBe(false);
	});

	it('makes synthetic PNG identities unique without changing their visual geometry', () => {
		expect(script).toContain('function patternPng(kind, runNonce)');
		expect(script).toContain("chunk('tEXt', benchmarkMetadata)");
		expect(script).toContain('const runNonce = randomUUID()');
	});

	it('uses the production threshold and enforces top-one and negative safety', () => {
		expect(script).toContain('SEMANTIC_VISUAL_SEARCH_MIN_SIMILARITY');
		expect(script).toContain('r.rawVisualExpectedSimilarity >= VISUAL_THRESHOLD');
		expect(script).toContain('visualTop1Quality: active.metrics.visualRecallAt1 >= 0.8');
		expect(script).toContain('visualMrrQuality: active.metrics.visualMrr >= 0.8');
		expect(script).toContain('noNegativeVisualThresholdHits');
	});
});
