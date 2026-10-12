import { test } from "node:test";
import { strict as assert } from "node:assert";
import {
  formatClassStart,
  formatEarningsMonth,
  parseHostEarningsRow,
  rollupEarningsByMonth,
  type HostEarningsInstance,
} from "./host_earnings";

function row(over: Partial<HostEarningsInstance>): HostEarningsInstance {
  return {
    event_id: "e1",
    event_title: "Reformer",
    club_id: "c1",
    instance_start: "2026-10-10T17:00:00Z",
    local_month: "2026-10-01",
    timezone: "UTC",
    currency: "usd",
    registrations: 0,
    refunded_orders: 0,
    partially_refunded_orders: 0,
    partial_refunds_unrecorded: 0,
    refund_failed_orders: 0,
    gross_cents: 0,
    refunded_cents: 0,
    platform_fee_cents: 0,
    net_cents: 0,
    unsettled_cents: 0,
    ...over,
  };
}

test("parseHostEarningsRow keeps a well-formed row and lower-cases its currency", () => {
  const parsed = parseHostEarningsRow({
    event_id: "e1",
    event_title: "Reformer",
    club_id: "c1",
    instance_start: "2026-11-01T02:00:00+00:00",
    local_month: "2026-10-01",
    timezone: "America/Los_Angeles",
    currency: "USD",
    registrations: 3,
    gross_cents: "8000",
    refunded_cents: 2500,
    platform_fee_cents: 300,
    net_cents: 5200,
    unsettled_cents: 2000,
  });
  assert.ok(parsed);
  assert.equal(parsed.currency, "usd");
  assert.equal(
    parsed.gross_cents,
    8000,
    "a bigint serialised as a string still counts",
  );
  assert.equal(parsed.local_month, "2026-10-01");
  assert.equal(parsed.timezone, "America/Los_Angeles");
  assert.equal(parsed.refunded_orders, 0, "a missing count reads as zero");
});

test("parseHostEarningsRow drops a row it cannot file under a month", () => {
  assert.equal(parseHostEarningsRow(null), null);
  assert.equal(
    parseHostEarningsRow({
      event_id: "e1",
      instance_start: "x",
      currency: "usd",
    }),
    null,
  );
  assert.equal(
    parseHostEarningsRow({
      event_id: "e1",
      instance_start: "x",
      local_month: "October",
      currency: "usd",
    }),
    null,
  );
  assert.equal(
    parseHostEarningsRow({
      event_id: "e1",
      instance_start: "x",
      local_month: "2026-10-01",
      currency: "",
    }),
    null,
  );
});

test("rollupEarningsByMonth sums a month and never adds two currencies together", () => {
  const months = rollupEarningsByMonth([
    row({
      event_id: "a",
      registrations: 3,
      gross_cents: 6000,
      platform_fee_cents: 300,
      net_cents: 5700,
    }),
    row({
      event_id: "b",
      registrations: 1,
      gross_cents: 2000,
      refunded_cents: 500,
      platform_fee_cents: 100,
      net_cents: 1400,
      partial_refunds_unrecorded: 1,
    }),
    row({
      event_id: "c",
      currency: "eur",
      registrations: 2,
      gross_cents: 3000,
      platform_fee_cents: 150,
      net_cents: 2850,
    }),
  ]);
  assert.equal(months.length, 2);
  const [eur, usd] = months;
  assert.equal(
    eur.currency,
    "eur",
    "currencies within a month sort alphabetically",
  );
  assert.equal(eur.net_cents, 2850);
  assert.equal(usd.registrations, 4);
  assert.equal(usd.gross_cents, 8000);
  assert.equal(usd.refunded_cents, 500);
  assert.equal(usd.platform_fee_cents, 400);
  assert.equal(usd.net_cents, 7100);
  assert.equal(usd.partial_refunds_unrecorded, 1);
  assert.deepEqual(
    usd.instances.map((i) => i.event_id),
    ["a", "b"],
  );
});

test("rollupEarningsByMonth puts the newest month first and trusts the server month label", () => {
  const months = rollupEarningsByMonth([
    row({ local_month: "2026-09-01", net_cents: 1 }),
    // 02:00 UTC on 1 Nov, filed by the server under its Los Angeles October.
    row({
      instance_start: "2026-11-01T02:00:00Z",
      local_month: "2026-10-01",
      net_cents: 2,
    }),
    row({ local_month: "2026-12-01", net_cents: 3 }),
  ]);
  assert.deepEqual(
    months.map((m) => m.month),
    ["2026-12-01", "2026-10-01", "2026-09-01"],
  );
  assert.equal(
    months[1].net_cents,
    2,
    "the instance stays in the month the server filed it under",
  );
});

test("rollupEarningsByMonth of nothing is nothing", () => {
  assert.deepEqual(rollupEarningsByMonth([]), []);
});

test("formatEarningsMonth names the label month in the reader language", () => {
  assert.equal(formatEarningsMonth("2026-10-01", "en-US"), "October 2026");
  assert.equal(formatEarningsMonth("2026-01-01", "de-DE"), "Januar 2026");
  assert.equal(formatEarningsMonth("not-a-month", "en-US"), "not-a-month");
});

test("formatClassStart shows the class on its own wall clock", () => {
  const la = formatClassStart(
    "2026-11-01T02:00:00Z",
    "America/Los_Angeles",
    "en-US",
  );
  assert.match(la, /Oct/);
  assert.match(la, /31/);
  assert.match(la, /7:00/);
  const fallback = formatClassStart(
    "2026-11-01T02:00:00Z",
    "Not/AZone",
    "en-US",
  );
  assert.match(
    fallback,
    /Nov/,
    "an unknown zone falls back to UTC rather than throwing",
  );
});

const minimalRow = (over: Record<string, unknown>) => ({
  event_id: "e1",
  instance_start: "2026-10-10T17:00:00Z",
  local_month: "2026-10-01",
  currency: "usd",
  ...over,
});

test("parseHostEarningsRow refuses a month label that names no calendar month", () => {
  // The server files every row under a real first-of-month; a label outside
  // 01-12 would otherwise be summed under a month that does not exist and
  // printed as a neighbouring one ("2026-13" reads as January 2027).
  for (const local_month of ["2026-00-01", "2026-13-01", "2026-99-01"]) {
    assert.equal(
      parseHostEarningsRow(minimalRow({ local_month })),
      null,
      local_month,
    );
  }
  assert.equal(
    parseHostEarningsRow(minimalRow({ local_month: "2026-10-01T00:00:00Z" })),
    null,
    "a timestamp is not a month label",
  );
  assert.ok(parseHostEarningsRow(minimalRow({ local_month: "2026-12-01" })));
  assert.ok(parseHostEarningsRow(minimalRow({ local_month: "2026-01-01" })));
});

test("formatEarningsMonth never prints a different month than the label says", () => {
  assert.equal(formatEarningsMonth("2026-13-01", "en-US"), "2026-13-01");
  assert.equal(formatEarningsMonth("2026-00-01", "en-US"), "2026-00-01");
  assert.equal(formatEarningsMonth("2026-12-01", "en-US"), "December 2026");
});

test("parseHostEarningsRow reads an unusable amount as zero, never as NaN", () => {
  const parsed = parseHostEarningsRow(
    minimalRow({
      gross_cents: "abc",
      net_cents: Number.NaN,
      refunded_cents: Infinity,
      platform_fee_cents: null,
      unsettled_cents: { cents: 5 },
    }),
  );
  assert.ok(parsed);
  for (const k of [
    "gross_cents",
    "net_cents",
    "refunded_cents",
    "platform_fee_cents",
    "unsettled_cents",
  ] as const) {
    assert.equal(parsed[k], 0, k);
  }
  const totals = rollupEarningsByMonth([parsed, row({ net_cents: 700 })]);
  assert.equal(totals[0].net_cents, 700, "one bad row cannot NaN a month total");
});

test("parseHostEarningsRow defaults a missing title, club and zone", () => {
  const parsed = parseHostEarningsRow(minimalRow({ timezone: "" }));
  assert.ok(parsed);
  assert.equal(parsed.event_title, "");
  assert.equal(parsed.club_id, "");
  assert.equal(parsed.timezone, "UTC");
});

test("rollupEarningsByMonth folds currency case before grouping", () => {
  const rows = [
    parseHostEarningsRow(minimalRow({ currency: "USD", net_cents: 100 })),
    parseHostEarningsRow(minimalRow({ currency: "usd", net_cents: 50 })),
  ].filter((r): r is HostEarningsInstance => r !== null);
  const months = rollupEarningsByMonth(rows);
  assert.equal(months.length, 1, "USD and usd are one currency");
  assert.equal(months[0].net_cents, 150);
});

test("formatClassStart returns an unparseable start as given", () => {
  assert.equal(formatClassStart("not-a-date", "UTC", "en-US"), "not-a-date");
});
