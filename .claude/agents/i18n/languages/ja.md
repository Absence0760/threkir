# Japanese (ja)

`app_ja.arb` (mobile) and `locales/ja.ts` (web).

Everything below is derived from the shipped catalogues (measured
2026-10-04 at `28e1267ef`). Counts read "mobile / web" in strings.

## Register — です・ます, no pronoun

Sentences end in **です・ます** (polite, 364 / 605 sentence-final
hits); plain-form endings are rare — the marketing headline (`landing.heroHeadline`
「ルートを引く。ランを記録する。すべてを分析する。」), a tooltip fragment
(`fitnessStatTsbTooltip`), a toggle label (`prefs.telemetryConsent`) and
coach advice in 〜よう (`workoutDetail.adviceMarathonPace`). The reader is rarely named;
where the English says "you", drop it or use あなた only where the sentence
needs an owner ("あなたのラン"). Labels, buttons and stat names are nouns
or noun phrases (体言止め), no です: "保存", "参加", "再開", "ペース".

- `clubInviteEnterCodeError` (mobile): 「リンクの招待コードを入力してください。」
- `discardChangesBody` (mobile): 「保存されていない変更があります。保存せずに終了しますか？」 /
  `common.unsavedBody` (web): 「保存していない変更があります。保存せずに移動しますか？」
- `rateLimit.generic` (web): 「操作が速すぎます。{wait}待ってから、もう一度お試しください。」

Requests use 〜してください; error statements 〜できませんでした;
confirmations 〜しますか？

**TTS cues (finding).** The spoken cues mix registers: alerts are polite
(`ttsPaceAlertSlow` 「ペースを落としましょう」, `ttsPaceAlertSlowDownByKm`
「…ペースを落としてください」), but the race-phase cues are casual て-form
commands (`ttsPhaseEven` 「一定のペースを保って。」, `ttsPhaseHoldBack`
「抑えて。コントロールを保って。」, `ttsPhaseRace` 「ここから勝負。残りの力を出し切って。」).
New TTS strings: polite 〜ましょう / 〜してください, short.

## Style authority

Japanese government and newspaper usage (文化庁「公用文作成の要領」,
共同通信『記者ハンドブック』) for kana/kanji choice; loanwords in katakana
with the long-vowel mark (リカバリー, ウォームアップ). Brand and product
names stay in Latin script.

## Typography

- Full stop 「。」, comma 「、」; question 「？」 and exclamation 「！」 full-width
  (6 / 10 `！`; ASCII `!` is a slip).
- Quotes **「…」**, always, with no space between 」 and the particle after it, e.g.
  `routePickerEmptyNoMatch` 「「{query}」に一致するルートはありません」; 『』 only
  inside 「」. A straight `"` in a message fails CI (`messages_parity.test.ts` on web, `architecture_guards_test.dart` on mobile — ARBs and the `gen/` getters); the last 2 mobile straight-quoted strings
  (`addRunPickerNoMatch`, `runDetailRouteSaved`) moved to 「…」 2026-10-14.
- Parentheses full-width **（…）** after Japanese text, everywhere: catalogues, ARB and help guides ("受取額（純額）", "理由（任意）"). Only a statute citation keeps ASCII paragraph marks ("GDPR 第9条(2)(a)"). `ja_fullwidth_parens.test.ts` fails a half-width one; settled 2026-11-13 (#1374 round 3.8).
- Ellipsis **…**.
- Colon: the catalogues mostly use ASCII `: ` after kana/kanji (136 / 176)
  with full-width 「：」 in 60 / 32 — inconsistent; follow the neighbouring
  keys.
- Spacing between Latin/digits and Japanese is mixed (unspaced 498 / 536
  vs spaced 280 / 384 strings). Prefer **no space** ("Stravaを開く",
  "{count}件"), except keep the space the English puts before a unit
  symbol in a literal sample ("1000 km").
- Numbers in literal samples keep the decimal point ("5.0 km · 5:00 /km").

## Plurals

Japanese has **only `other`**. Write `{count, plural, other{{count}件の…}}`
(ARB) / `{n, plural, other {#件…}}` (web) — drop `one`. Use a counter
(件, 回, 日, 本, 人) rather than a pluralised noun.

## Running glossary (what the catalogues already use)

| English | Japanese | Evidence / note |
|---|---|---|
| run (noun) | ラン | dominant (469 / 664); ランニング for the activity in general |
| pace | ペース | |
| split | スプリット | web `landing.previewSplits` 「ラップ」 is the odd one |
| lap | ラップ | |
| personal record / PR | 自己ベスト; badge **PR** | |
| tempo run | テンポ | |
| interval | インターバル | |
| long run | ロング走 | |
| easy run | イージー | |
| elevation gain | 獲得標高 | `routeDetail.statElevationGain`, `runStatElevation` |
| heart rate / HR | 心拍数 / 心拍 | |
| heart rate zone | 心拍ゾーン | |
| cadence (steps/min) | ケイデンス | `runStatCadence`; 「頻度」 in `discover.cadenceLabel` means *recurrence* |
| training plan | トレーニングプラン; short プラン | |
| race | レース; 勝負 for the race phase intent | |
| counting cues | 「# 件のキュー」 | settled 2026-11-13 (#1374 round 3.5), both surfaces; never 「#個のキュー」 |
| mapped run (personal heatmap) | 「地図に#件のラン」「地図に表示できるランはまだありません」 | settled 2026-11-13 (#1374 round 3.5), both surfaces; never 「マップ化されたラン」 |
| AI disclosure | **AIに関する説明** | settled 2026-11-13 (#1374 round 3.5), both surfaces; never 「AIの説明」, which collides with 「AIによる説明」 (an AI description) |
| waitlist | **キャンセル待ち** everywhere — status 「キャンセル待ち」, 「満員 · キャンセル待ち{n}人」 | settled 2026-11-13 (#1374 round 3.5), both surfaces; never 補欠 |
| safety contact | **緊急連絡先** everywhere, including 「緊急連絡先のみ」 on the live view | settled 2026-11-13 (#1374 round 3.5), both surfaces; never 安全連絡先 |
| payouts (a host or fundraiser receiving money: the Payouts page and tab, "Set up payouts", the payout account) | **受け取り** — 「受け取り」, 「受け取りを設定」, 「受け取りの設定を完了する」, 「受け取りアカウント」 | settled 2026-11-13 (#1374 round 3.7), web (mobile has no payouts surface); never 支払い for this, which reads as money paid out by the reader. 支払い / お支払い stays for a reader paying (「お支払いで確定します」, 支払い方法) and 決済 for payment processing (「まだ決済が設定されていません」) |
| form (TSB), fitness and form | **調子** — 「TSB（調子）」「フィットネス、疲労、調子」「体力と調子」 | settled 2026-11-13 (#1374 round 3.5), both surfaces; コンディション stays for route conditions and Readiness, so it is never form |
| finish | ゴール (finish line), フィニッシュ (roadbook), 完走 (finished a race), 終了 (ended), 完了 (completed) | mixed — inconsistency 3 |
| DNF | DNF | web `liveEvent.statusDnf` 「途中棄権」 |
| route | ルート; コース for a race course | |
| segment | セグメント | |
| club | クラブ | |
| event | イベント | |
| gym | ジム; 筋トレ for strength training | |
| nutrition | 栄養 | |
| log (verb) | 記録 | `navLog` |
| streak | 連続記録 | |
| goal | 目標 | |
| coach | コーチ; AI Coach = **AI コーチ** (`nav.coach`) | "AIコーチ" unspaced in 2 / 9 strings |
| auto-pause | — | no catalogue string yet; build from 一時停止 (「ランを一時停止しました」) → 自動一時停止, and flag it as a new term |
| kudos | **称賛** (`kudosGiveLabel` 「称賛する」, `profile.giveKudos`) | four renderings ship — inconsistency 1 |
| workout | ワークアウト; training トレーニング | |
| `hike` activity type | **トレイルラン** (`activityTypeHike` / `activityType.hike`) | deliberate, not a mistranslation: the stored token is `hike` but the product shows it as "Trail run" in every locale since decisions § 547 / § 1155. Don't flag it or change it to ハイキング |
| warm-up / cool-down / recovery | ウォームアップ / クールダウン / リカバリー | 回復 once on mobile |
| save / settings / feed / followers | 保存 / 設定 / フィード / フォロワー | |
| sign in | サインイン | ログイン in 4 / 21 strings — inconsistency 4 |
| device / phone | **デバイス** for *device* (「このデバイス」「他のデバイス」「サインイン中のデバイス」「すべてのデバイスからサインアウト」); **スマートフォン** where the English says *phone* (「このスマートフォンに保存」) | settled 2026-11-12: 31 mobile / 13 web strings and 3 help guides moved off 「端末」. Never 端末, and スマホ is not the short form: "phone" is スマートフォン in full |
| watch (the device) | **ウォッチ** (「スマートフォンやウォッチ」「ウォッチに送信」「Wear OS ウォッチ」) | settled 2026-11-13; never 時計 for the device. 時計 stays for a *clock* (「レースの時計」「サーバーの時計」「デバイスの時計」) and in 時計回り |
| browser | **ブラウザ** | settled 2026-11-13; never ブラウザー |
| run (the activity) | **ラン**, also where the English says "a run" in a sentence about saving or syncing it (「ランを保存すると解除されます。圏外で終えたランは…」) | settled 2026-11-13; アクティビティ is for *activity* in the English |
| arm / armed (race control) | **準備する** / **準備完了** — 「レースを準備」「このまま準備する」「早めに準備」「レース準備完了」 | settled 2026-11-10; never 「準備完了にする」 for the action |
| set up (a race created automatically before its start) | **設定される** (「レースはスタートの前日に設定されます」) | settled 2026-11-10; never 準備, which is *arm* |
| self-timed (race) | **セルフタイム**; a self-timed race is 「セルフタイム方式のレース」, the window 「セルフタイム期間」 | settled 2026-11-10; never 「セルフ計測」 |
| GO (the start signal) | **GO** — the host's button on the web and in the phone app, 「主催者のGO」「予約GO」; prose 「GOを出す」「GO待ち」「GOから」「GOの時点で」 | settled 2026-11-10; never スタート for the host's button or the signal. スタート stays for a runner's own record Start button and the time fields (「スタート時刻」「スタート：{when}」) |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. **kudos** has four renderings: "Kudos" (mobile `feedKudosUpdateFailed`,
   `profileNotifKudos`), 「称賛」 (`kudosGiveLabel`, `profile.rescindKudos`),
   「応援」 (web `login.bullet3`, `runSocial.signInToGiveKudos`), 「クドス」
   (web `onboarding.step6Hint`).
2. **TTS register** — see Register.
3. **finish**: 完走 / 終了 / 完了 / ゴール / フィニッシュ across both surfaces.
4. **sign in**: サインイン vs ログイン.
5. **VO₂ max**: 「VO₂max」 (`metric.vo2max.label`) vs 「VO2 Max」
   (`watchMetricVo2Max`).
6. **split** rendered 「ラップ」 once on web.
7. **typography**: mixed colon width and Latin–kana spacing.

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Apple Watch, Wear OS,
HealthKit (the framework), GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP, DNF,
VO₂max. The health platforms take their vendors' Japanese names
(`healthPlatformNameIos` / `healthPlatformNameAndroid`): **ヘルスケア** and
**ヘルスコネクト**, in katakana, never the English names. A generic
"health app" is 「健康管理アプリ」, not 「ヘルスケアアプリ」, which is Apple's.
Person-named formulas are transliterated: Riegel → リーゲル
(`metricRiegelLabel` 「リーゲルの式」). Identifiers, route paths, ICU keywords,
`{placeholders}`.

## Provenance

Machine-extracted and model-translated; no native review yet
(`docs/product/followups.md` › "Native review of machine-extracted
translations"). Flag anything you're unsure of rather than guessing.
