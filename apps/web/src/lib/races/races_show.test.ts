import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { ANY_TIME_LIMIT, anyTimeCourseLimit, parseRacesShow, racesShowSearch } from './races_show';

test('the three choices parse, and anything else is all', () => {
	assert.equal(parseRacesShow('races'), 'races');
	assert.equal(parseRacesShow('courses'), 'courses');
	assert.equal(parseRacesShow('all'), 'all');
	assert.equal(parseRacesShow(null), 'all');
	assert.equal(parseRacesShow(''), 'all');
	assert.equal(parseRacesShow('COURSES'), 'all');
	assert.equal(parseRacesShow('parks'), 'all');
	assert.equal(parseRacesShow(2), 'all');
});

test('setting the choice keeps the other query parameters, and all drops the parameter', () => {
	assert.equal(racesShowSearch('', 'courses'), '?show=courses');
	assert.equal(racesShowSearch('?show=courses', 'races'), '?show=races');
	assert.equal(racesShowSearch('?show=races', 'all'), '');
	assert.equal(racesShowSearch('?a=1&show=races', 'all'), '?a=1');
	assert.equal(racesShowSearch('?a=1', 'courses'), '?a=1&show=courses');
});

test('only the courses view lists every course', () => {
	assert.equal(anyTimeCourseLimit('all'), ANY_TIME_LIMIT);
	assert.equal(anyTimeCourseLimit('races'), ANY_TIME_LIMIT);
	assert.equal(anyTimeCourseLimit('courses'), null);
});
