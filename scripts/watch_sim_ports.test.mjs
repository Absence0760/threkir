import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const EPHEMERAL_FLOOR = 32768;
const script = readFileSync(new URL('../bin/watch-sim.sh', import.meta.url), 'utf8');

test('the Renode monitor port is drawn below the ephemeral range', () => {
  const draw = script.match(/CANDIDATE=\$\(\( (\d+) \+ RANDOM % (\d+) \)\)/);
  assert.ok(draw, 'watch-sim.sh no longer draws the monitor port as $(( base + RANDOM % span ))');
  const [base, span] = [Number(draw[1]), Number(draw[2])];
  assert.ok(base + span - 1 < EPHEMERAL_FLOOR, `monitor port draw reaches ${base + span - 1}, inside the ${EPHEMERAL_FLOOR}+ ephemeral range`);
  assert.ok(script.includes(`from ${base}-${base + span - 1}`), 'the exhaustion message no longer states the range actually drawn');
});

test('the monitor port probe counts sockets in every state, not only LISTEN', () => {
  const probe = script.match(/ss -(\w+) "sport = :\$CANDIDATE"/);
  assert.ok(probe, 'watch-sim.sh no longer probes the monitor candidate with ss');
  assert.ok(!probe[1].includes('l'), `the probe uses ss -${probe[1]}, which sees only listening sockets`);
  assert.ok(probe[1].includes('a'), `the probe uses ss -${probe[1]} without -a`);
});
