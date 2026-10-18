import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	DEFAULT_RUNS_VIEW,
	parseRunsView,
	resolveRunsView,
	runsListGroupsByDay,
	runsViewSearch,
} from './runs_view';

test('only the two layouts parse', () => {
	assert.equal(parseRunsView('list'), 'list');
	assert.equal(parseRunsView('grid'), 'grid');
	assert.equal(parseRunsView('LIST'), null);
	assert.equal(parseRunsView(''), null);
	assert.equal(parseRunsView(null), null);
	assert.equal(parseRunsView(1), null);
});

test('the URL wins over the remembered choice', () => {
	assert.equal(resolveRunsView('grid', 'list'), 'grid');
	assert.equal(resolveRunsView('list', 'grid'), 'list');
});

test('a missing or bogus URL value falls back to the remembered choice, then the grid', () => {
	assert.equal(resolveRunsView(null, 'list'), 'list');
	assert.equal(resolveRunsView('tiles', 'list'), 'list');
	assert.equal(resolveRunsView(null, undefined), DEFAULT_RUNS_VIEW);
	assert.equal(resolveRunsView('tiles', 'cards'), 'grid');
});

test('setting the view keeps the other query parameters', () => {
	assert.equal(runsViewSearch('', 'list'), '?view=list');
	assert.equal(runsViewSearch('?view=list', 'grid'), '?view=grid');
	assert.equal(runsViewSearch('?a=1&view=grid', 'list'), '?a=1&view=list');
});

test('day headings only under a chronological sort', () => {
	assert.equal(runsListGroupsByDay('newest'), true);
	assert.equal(runsListGroupsByDay('oldest'), true);
	assert.equal(runsListGroupsByDay('longest'), false);
	assert.equal(runsListGroupsByDay('fastest'), false);
});
