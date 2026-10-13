import 'package:flutter/material.dart';

import '../column_limits.dart';
import '../auth_error.dart';
import '../event_category.dart';
import '../event_gym_template.dart';
import '../event_pricing.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../minor_units.dart';
import '../social_service.dart';
import '../typed_decimal.dart';
import 'full_screen_form.dart';

/// Full-screen dialog for creating a new event under a club. Mirrors
/// the web `EventEditor.svelte` (one-off / weekly / biweekly / monthly, with
/// an optional end date or occurrence count, capacity, a series price for a
/// host who can take payments, and a session plan for a class).
/// Presentation goes through [showFullScreenForm], the shared
/// create/edit-entity wrapper.
///
/// Resolves to `'ok'` when the event was created cleanly, to a localized
/// message when it was created but a follow-up write (its price or its
/// session plan) failed — the caller shows it, and the host fixes it on the
/// event — and to null when the form was dismissed.
Future<String?> showEventFormSheet(
  BuildContext context, {
  required SocialService social,
  required String clubId,
  bool clubIsPublic = true,
}) {
  final formKey = GlobalKey<_EventFormState>();
  return showFullScreenForm<String>(
    context,
    title: AppLocalizations.of(context).eventFormTitle,
    isDirty: () => formKey.currentState?.isDirty ?? false,
    builder: (_) => _EventForm(
        key: formKey,
        social: social,
        clubId: clubId,
        clubIsPublic: clubIsPublic),
  );
}

class _EventForm extends StatefulWidget {
  final SocialService social;
  final String clubId;
  // The members-only toggle is only meaningful in a public club (a private
  // club's events are already members-only via the club gate), so it's hidden
  // for a private club.
  final bool clubIsPublic;
  const _EventForm({
    super.key,
    required this.social,
    required this.clubId,
    this.clubIsPublic = true,
  });

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _meetLabel = TextEditingController();
  final _distanceKm = TextEditingController();
  final _durationMin = TextEditingController();
  final _discipline = TextEditingController();
  final _capacity = TextEditingController();
  final _count = TextEditingController();
  final _price = TextEditingController();
  final _currency = TextEditingController(text: 'usd');
  final _salesClose = TextEditingController(text: '0');
  String _category = 'run';
  DateTime? _until;
  String? _sessionPlanId;
  List<({String id, String title})> _sessionPlans = const [];
  // Or one of the club's gym routine templates (decisions § 1869). A class
  // carries one or the other, never both.
  String? _gymRoutineId;
  List<({String id, String title})> _gymRoutines = const [];
  bool _chargesEnabled = false;
  bool _charge = false;
  String _refundPolicy = kDefaultEventRefundPolicy;
  String? _capacityError;
  String? _countError;
  String? _priceError;
  String? _currencyError;
  String? _salesCloseError;
  DateTime _starts = DateTime.now().add(const Duration(days: 1, hours: 1));
  String _recurrence = 'none'; // none | weekly | biweekly | monthly
  bool _isPublic = true;
  bool _busy = false;
  // Title validation renders inline on the title field; _error stays for
  // save failures only.
  String? _titleError;
  String? _error;
  late String _initialSnapshot;

  @override
  void initState() {
    super.initState();
    _initialSnapshot = _snapshot();
    _loadOptions();
  }

  /// The host's payout capability, their session plans and the club's gym
  /// routine templates. Best-effort: a failure leaves the form usable without
  /// a price, a plan or a routine (L4).
  Future<void> _loadOptions() async {
    try {
      final results = await Future.wait([
        widget.social.fetchPayoutCapability(),
        widget.social.fetchSessionPlanOptions(),
        widget.social.fetchClubGymRoutineOptions(widget.clubId),
      ]);
      if (!mounted) return;
      final payout =
          results[0] as ({bool chargesEnabled, String? defaultCurrency})?;
      final plans = results[1] as List<({String id, String title})>;
      final routines = results[2] as List<({String id, String title})>;
      final wasDirty = isDirty;
      setState(() {
        _chargesEnabled = payout?.chargesEnabled ?? false;
        final seeded = payout?.defaultCurrency;
        if (seeded != null && seeded.isNotEmpty) _currency.text = seeded;
        _sessionPlans = plans;
        _gymRoutines = routines;
      });
      if (!wasDirty) _initialSnapshot = _snapshot();
    } catch (e) {
      debugPrint('event form options load failed: $e');
    }
  }

  String _snapshot() => [
        _title.text,
        _description.text,
        _meetLabel.text,
        _distanceKm.text,
        _durationMin.text,
        _discipline.text,
        _category,
        _recurrence,
        _isPublic.toString(),
        _starts.toIso8601String(),
        _capacity.text,
        _count.text,
        _until?.toIso8601String() ?? '',
        _sessionPlanId ?? '',
        _gymRoutineId ?? '',
        _charge.toString(),
        _price.text,
        _currency.text,
        _salesClose.text,
        _refundPolicy,
      ].join('\u0000');

  bool get isDirty => _snapshot() != _initialSnapshot;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _meetLabel.dispose();
    _distanceKm.dispose();
    _durationMin.dispose();
    _discipline.dispose();
    _capacity.dispose();
    _count.dispose();
    _price.dispose();
    _currency.dispose();
    _salesClose.dispose();
    super.dispose();
  }

  // Hiding a field leaves its controller text intact, so a user who types
  // a distance then switches to a class would silently submit it. Clear
  // the now-irrelevant fields the moment the category leaves the set that
  // owns them, mirroring the web editor's pickCategory.
  void _pickCategory(String next) {
    if (_category == next) return;
    setState(() {
      _category = next;
      if (!isAthleticEventCategory(next)) {
        _distanceKm.clear();
      }
      if (next != 'class') {
        _discipline.clear();
        _sessionPlanId = null;
        _gymRoutineId = null;
      }
    });
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _starts,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_starts),
    );
    if (time == null || !mounted) return;
    setState(() {
      _starts = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickUntil() async {
    final first = DateTime(_starts.year, _starts.month, _starts.day);
    final date = await showDatePicker(
      context: context,
      initialDate: _until ?? DateTime(first.year, first.month, first.day + 28),
      firstDate: first,
      lastDate: DateTime(first.year + 5, first.month, first.day),
    );
    if (date == null || !mounted) return;
    // Inclusive, as web's "Ends on": the series runs to the end of that day.
    setState(() => _until = DateTime(date.year, date.month, date.day, 23, 59, 59));
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final title = _title.text.trim();
    final capacity = parseOptionalWhole(_capacity.text, min: 1);
    final recurring = _recurrence != 'none';
    final count = recurring
        ? parseOptionalWhole(_count.text, min: 1, max: eventRecurrenceCountMax)
        : (value: null, ok: true);
    final priced = _charge && _chargesEnabled;
    final price = priced ? parseEventPrice(_price.text) : null;
    final currency = priced ? parseCurrencyCode(_currency.text) : null;
    final salesClose = priced
        ? parseOptionalWhole(_salesClose.text,
            min: 0, max: eventSalesCloseMaxMinutes)
        : (value: null, ok: true);
    // An empty title used to return silently — Create looked dead. Flag
    // the field instead (sign_up_screen idiom), and every other refused
    // field beside it, so one press shows everything that needs fixing.
    setState(() {
      _titleError = title.isEmpty ? l10n.eventFormErrTitle : null;
      _capacityError = capacity.ok ? null : l10n.eventFormErrCapacity;
      _countError = count.ok ? null : l10n.eventFormErrCount;
      _priceError = priced && price == null ? l10n.eventFormErrPrice : null;
      _currencyError =
          priced && currency == null ? l10n.eventFormErrCurrency : null;
      _salesCloseError = salesClose.ok ? null : l10n.eventFormErrSalesClose;
    });
    if (title.isEmpty ||
        !capacity.ok ||
        !count.ok ||
        _priceError != null ||
        _currencyError != null ||
        !salesClose.ok) {
      return;
    }
    final athletic = isAthleticEventCategory(_category);
    final distance = athletic ? parseTypedDecimal(_distanceKm.text) : null;
    final duration = int.tryParse(_durationMin.text.trim());
    final discipline = _category == 'class' ? _discipline.text.trim() : null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Recurrence mapping mirrors `apps/web/src/lib/social/recurrence.ts`:
      // weekly → FREQ=WEEKLY, biweekly → WEEKLY+INTERVAL=2 (we collapse
      // to "weekly_alt" via a byday hint for v1), monthly → MONTHLY.
      String? freq;
      String? byday;
      switch (_recurrence) {
        case 'weekly':
          freq = 'weekly';
          break;
        case 'biweekly':
          freq = 'biweekly';
          break;
        case 'monthly':
          freq = 'monthly';
          break;
      }
      if (freq != null) {
        // ISO weekday byday hint for repeat-on-same-DOW behaviour.
        const dow = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
        byday = dow[(_starts.weekday - 1) % 7];
      }
      final created = await widget.social.createEvent(
        clubId: widget.clubId,
        title: title,
        startsAt: _starts,
        category: _category,
        discipline: discipline,
        gymTemplate: _category == 'class'
            ? gymTemplateFromInputs(discipline, duration)
            : null,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        durationMin: duration,
        meetLabel:
            _meetLabel.text.trim().isEmpty ? null : _meetLabel.text.trim(),
        distanceM: distance == null ? null : distance * 1000,
        capacity: capacity.value,
        recurrenceFreq: freq,
        recurrenceUntil: freq == null ? null : _until,
        recurrenceCount: freq == null ? null : count.value,
        // `recurrence_byday` is a text[] column — wrap the single
        // weekday code in a one-element list so postgrest receives a
        // JSON array, not a bare string.
        recurrenceByDay: byday == null ? null : [byday],
        // In a private club every event is members-only regardless; the toggle
        // is hidden there and we leave this public (the column is moot — the
        // club gate already restricts read + discovery skips the club).
        isPublic: widget.clubIsPublic ? _isPublic : true,
      );
      // Pricing and the session plan are separate writes with their own
      // gates (the charges-enabled trigger, the organiser trigger). The event
      // exists whichever of them fails, so a failure is reported, not retried
      // here — a second Create would make a second event.
      String? followUpFailure;
      if (priced) {
        try {
          await widget.social.setEventPricing(
            eventId: created.id,
            priceCents: toMinorUnits(price!, currency!),
            currency: currency,
            refundPolicy: _refundPolicy,
            salesCloseOffsetMinutes: salesClose.value ?? 0,
          );
        } catch (pe) {
          debugPrint('event pricing write failed: $pe');
          followUpFailure = l10n.eventFormPricingFailed;
        }
      }
      if (_category == 'class' && _sessionPlanId != null) {
        try {
          await widget.social.setEventSessionPlan(created.id, _sessionPlanId);
        } catch (se) {
          debugPrint('event session plan attach failed: $se');
          followUpFailure ??= l10n.eventFormSessionPlanFailed;
        }
      } else if (_category == 'class' && _gymRoutineId != null) {
        try {
          await widget.social.setEventGymRoutine(created.id, _gymRoutineId);
        } catch (ge) {
          debugPrint('event gym routine attach failed: $ge');
          followUpFailure ??= l10n.eventFormGymRoutineFailed;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop<String?>(followUpFailure ?? 'ok');
    } catch (e) {
      debugPrint('event create failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(AppLocalizations.of(context), e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final athletic = isAthleticEventCategory(_category);
    // Heading lives in the host AppBar (showFullScreenForm).
    return FullScreenFormBody(
      children: [
            Text(l10n.eventEditorCategory, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final option in [
                  ('run', l10n.eventEditorCatRun),
                  ('cycle', l10n.eventEditorCatCycle),
                  ('class', l10n.eventEditorCatClass),
                  ('social', l10n.eventEditorCatSocial),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _category == option.$1,
                    onSelected: (_) => _pickCategory(option.$1),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.eventEditorCategoryHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_category == 'class') ...[
              TextField(
                controller: _discipline,
                maxLength: 60,
                decoration: InputDecoration(
                  labelText: l10n.eventEditorDiscipline,
                  hintText: l10n.eventEditorDisciplinePlaceholder,
                ),
              ),
              const SizedBox(height: 8),
              // Re-keyed on the value so picking the other source, which clears
              // this one, rebuilds the field with its new initial value.
              KeyedSubtree(
                key: ValueKey('plan-${_sessionPlanId ?? ''}'),
                child: DropdownButtonFormField<String?>(
                  key: const Key('event-form-session-plan'),
                  initialValue: _sessionPlanId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.eventFormSessionPlan,
                    helperText: _sessionPlans.isEmpty
                        ? l10n.eventFormSessionPlanEmpty
                        : null,
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.eventFormSessionPlanNone),
                    ),
                    for (final p in _sessionPlans)
                      DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(p.title, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _sessionPlanId = v;
                    if (v != null) _gymRoutineId = null;
                  }),
                ),
              ),
              const SizedBox(height: 8),
              KeyedSubtree(
                key: ValueKey('routine-${_gymRoutineId ?? ''}'),
                child: DropdownButtonFormField<String?>(
                  key: const Key('event-form-gym-routine'),
                  initialValue: _gymRoutineId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.eventFormGymRoutine,
                    helperText: _gymRoutines.isEmpty
                        ? l10n.eventFormGymRoutineEmpty
                        : l10n.eventFormGymRoutineHint,
                    helperMaxLines: 3,
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.eventFormGymRoutineNone),
                    ),
                    for (final r in _gymRoutines)
                      DropdownMenuItem<String?>(
                        value: r.id,
                        child: Text(r.title, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _gymRoutineId = v;
                    if (v != null) _sessionPlanId = null;
                  }),
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: l10n.eventFormTitleLabel,
                errorText: _titleError,
              ),
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDateTime,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.eventFormStartsAt,
                  suffixIcon: const Icon(Icons.event),
                ),
                child: Text(formatDateTime(
                    _starts, localeToTag(Localizations.localeOf(context)))),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 3,
              maxLength: columnLength('events.description'),
              decoration: InputDecoration(
                labelText: l10n.eventFormDescriptionLabel,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _meetLabel,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: l10n.eventFormMeetLabel,
                hintText: l10n.eventFormMeetHint,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (athletic) ...[
                  Expanded(
                    child: TextField(
                      controller: _distanceKm,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.eventFormDistanceLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: TextField(
                    controller: _durationMin,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.eventFormDurationLabel,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('event-form-capacity'),
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.eventFormCapacity,
                helperText: l10n.eventFormCapacityHint,
                errorText: _capacityError,
              ),
              onChanged: (_) {
                if (_capacityError != null) {
                  setState(() => _capacityError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            Text(l10n.eventFormRecurrence, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final option in [
                  ('none', l10n.eventFormRecurOneOff),
                  ('weekly', l10n.eventFormRecurWeekly),
                  ('biweekly', l10n.eventFormRecurBiweekly),
                  ('monthly', l10n.eventFormRecurMonthly),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _recurrence == option.$1,
                    onSelected: (_) =>
                        setState(() => _recurrence = option.$1),
                  ),
              ],
            ),
            if (_recurrence != 'none') ...[
              const SizedBox(height: 8),
              InkWell(
                key: const Key('event-form-until'),
                onTap: _pickUntil,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.eventFormEndsOn,
                    suffixIcon: _until == null
                        ? const Icon(Icons.event)
                        : IconButton(
                            tooltip: l10n.eventFormEndsOnClear,
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _until = null),
                          ),
                  ),
                  child: Text(_until == null
                      ? l10n.eventFormEndsOnNone
                      : formatDateMed(_until!,
                          localeToTag(Localizations.localeOf(context)))),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('event-form-count'),
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.eventFormEndAfter,
                  helperText: l10n.eventFormRepeatEndHint,
                  helperMaxLines: 3,
                  errorText: _countError,
                ),
                onChanged: (_) {
                  if (_countError != null) setState(() => _countError = null);
                },
              ),
            ],
            if (widget.clubIsPublic) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: !_isPublic,
                onChanged: (v) => setState(() => _isPublic = !v),
                title: Text(l10n.eventEditorMembersOnlyToggle),
                subtitle: Text(l10n.eventEditorMembersOnlyHint),
              ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              key: const Key('event-form-charge'),
              contentPadding: EdgeInsets.zero,
              value: _charge && _chargesEnabled,
              onChanged: _chargesEnabled
                  ? (v) => setState(() => _charge = v)
                  : null,
              title: Text(l10n.eventFormCharge),
              subtitle: Text(_chargesEnabled
                  ? l10n.eventFormChargeHint
                  : l10n.eventFormChargeNeedsPayout),
            ),
            if (_charge && _chargesEnabled) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const Key('event-form-price'),
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l10n.eventFormPrice,
                        errorText: _priceError,
                      ),
                      onChanged: (_) {
                        if (_priceError != null) {
                          setState(() => _priceError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('event-form-currency'),
                      controller: _currency,
                      maxLength: 3,
                      decoration: InputDecoration(
                        labelText: l10n.eventFormCurrency,
                        errorText: _currencyError,
                        counterText: '',
                      ),
                      onChanged: (_) {
                        if (_currencyError != null) {
                          setState(() => _currencyError = null);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('event-form-sales-close'),
                controller: _salesClose,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.eventFormSalesClose,
                  helperText: l10n.eventFormSalesCloseHint,
                  helperMaxLines: 2,
                  errorText: _salesCloseError,
                ),
                onChanged: (_) {
                  if (_salesCloseError != null) {
                    setState(() => _salesCloseError = null);
                  }
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('event-form-refund-policy'),
                initialValue: _refundPolicy,
                isExpanded: true,
                decoration:
                    InputDecoration(labelText: l10n.eventFormRefundPolicy),
                items: [
                  for (final p in kEventRefundPolicies)
                    DropdownMenuItem<String>(
                      value: p,
                      child: Text(eventRefundPolicyLabel(l10n, p)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _refundPolicy = v);
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.maybePop(context),
                  child: Text(l10n.eventFormCancel),
                ),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.eventFormCreate),
                ),
              ],
            ),
          ],
        );
  }

}
