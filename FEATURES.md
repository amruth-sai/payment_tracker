# Finance service: existing-app integration specification v3

## 1. Request for the implementing AI agent

Add **Finance** as a new service/feature module inside the existing host application. Use this document as its complete feature specification and implementation plan. Finance imports payment SMS, stores finance data locally, and helps users review payments, organize transactions, plan budgets, understand cash flow, and back up finance data.

Service here means an integrated product module accessible through the host's existing service entry points. It does not require a separate app, app shell, login system, or backend microservice. All F01-F16 capabilities remain required inside Finance.

Implement all requirements F01-F16 with persistence, real calculations, Android integrations, and error handling. Use synthetic data for development/tests only. Make routine implementation choices independently and document them. Ask for clarification only when missing information materially changes scope.

The original standalone inventory was verified by source inspection on 14 October 2026; Android device behavior was not tested. This version adapts those capabilities to an existing host app. The target host has not been inspected for this document; Phase 1 discovers its integration points. Target decisions below take precedence over reference behavior. The original repository is optional reference material, not an app to recreate.

### Scope and defaults

| Area | Required default |
| --- | --- |
| Platform | Extend the host's existing framework; Android support is required for native SMS import. Flutter/Dart is the reference stack, not permission to replace another host stack. |
| Currency | INR, Indian digit grouping, support for paise |
| Interface | Reuse host theme, typography, localization, accessibility, and light/dark behavior; reference UI is Material 3. |
| Navigation | Host service entry opens Finance; Overview, Transactions, Plan, Insights are internal Finance destinations. |
| Organization | One optional category and zero or more labels per transaction |
| Categories and labels | Entirely user-managed database records with generated IDs |
| Budget allocation | Category ID; labels are filters/context, never a second allocation |
| Storage | Host-compatible local persistence with transactions/migrations; namespaced finance tables or a Finance-owned SQLite database |
| Processing | Local SMS parsing and database-backed organization rules |
| SMS access | Android `READ_SMS`; inbox and sent folders |
| Backup/export | Encrypted backup through document picker; JSON through share sheet |
| Insights | In-app scan; no scheduled notification delivery required |
| External services | Finance adds no new login, backend, bank API, cloud sync, analytics, or AI API; reuse host identity/access controls where present. |

iOS/web SMS import, new push-notification infrastructure, continuous background monitoring, general manual payment entry, CSV import/export, payments, and automatic reimbursement settlement are outside Finance scope. Android's picker may expose cloud providers without a Finance cloud integration. Preserve host services that already use a backend, login, or notifications. Do not upload finance/SMS content to them or include it in telemetry automatically. Original-app data migration is required only if explicitly requested and supplied.

### Host integration contract

1. **Registration:** discover the host service catalog/dashboard/menu/router and add one Finance entry using its conventions. Reuse feature-access/enablement controls. Preserve host home and global navigation. If the service is disabled, stop Finance scans/listeners and reject new module work without deleting retained finance data unless host policy explicitly requires deletion.
2. **Routes:** Finance owns internal routes and four destinations. Back/close returns to the original host location. Finance deep links use host authentication/access guards and restore module/query context.
3. **Shared foundations:** reuse host routing, state management, dependency injection, theme, localization, errors, and platform adapters. In Flutter, use the existing app/router without a second top-level `MaterialApp` or conflicting global providers. Apply equivalent rules to other frameworks.
4. **Identity/data scope:** derive a stable finance scope from the active host profile/workspace, or explicit local-device scope if no identities exist. Scope every query, relationship, setting, scan cursor, cache, insight, and export. Never expose one profile's finance data to another.
5. **Profile lifecycle:** cancel or safely complete in-flight work against its captured scope on switch/logout. Clear visible state/caches before displaying another scope. Follow host retention/access policy; do not bypass login or delete other services' records. Restore cannot grant access to another profile.
6. **First use/permissions:** activate/onboard Finance on its first entry for the scope, not first host launch. Request SMS only from an explicit Finance setup/import action. Host startup/login/unrelated services remain usable without Finance setup or permission. Auto-scan on subsequent Finance entry only after activation and with permission already granted.
7. **Persistence:** use additive migrations through the host coordinator or a separately owned finance database. Namespace finance entities to avoid host account/category/setting collisions. Never reset the host database or change its schema version outside its migration mechanism.
8. **Backup scope:** finance backup/export contains only the active scope's finance data. Replace means Replace Finance Data in that scope, never reset the host. Exclude host credentials/tokens and other services/profiles.
9. **Native capabilities:** integrate SMS/document picker/share with existing host native setup. Non-Android entry remains safe and explains unavailable import capabilities. If the host cannot support a required capability, report the exact gap and obtain a scope decision; do not silently omit it or rewrite the host.
10. **Isolation/delivery:** initialize finance lazily. Preserve host application ID, branding, signing, dependencies, release process, and unrelated behavior. Baseline host tests first and demonstrate no integration regressions alongside finance checks.

Record the host entry/routes, module folder, identity source, database namespace, lifecycle hooks, native registration, and required host-file edits in the implementation status. These are discovered integration details, not instructions to create a standalone project.

## 2. Product simplifications and their purpose

| Decision | Benefit and required behavior |
| --- | --- |
| One category system | Removes competing assignments and precedence rules. A transaction has one category; the same ID is used in budgets, charts, rules, and exports. |
| Multiple reusable labels | Trips, work, family, reimbursables, and other contexts can overlap without changing the expense category. Labels are user-created, renamed, colored, archived, and deleted. |
| No fixed catalog | Start without mandatory categories/labels. Create them during onboarding, from transaction details, or in Organize. Category names, IDs, keywords, and label names must not be hardcoded into business logic. |
| Four internal Finance destinations | Consolidates finance screens while preserving host navigation; present as local tabs/sections using host conventions. |
| One Inbox within Transactions | Combines unclear SMS, new imports, missing categories, transfer suggestions, ignored items, and recoverable skips as filtered queues. Confirmed unassigned/new records still contribute to totals. |
| Shared transaction list and editor | Accounts, categories, labels, merchants, budgets, charts, and alerts all open the same list with appropriate filters and the same detail editor. |
| Plan combines budgets, salary periods, and recurring payments | Spending limits, coverage gaps, salary closeouts, and recurring burden share the same period and ledger. |
| Insights combines charts and alerts | Category/account/merchant views, calendar heatmap, digest, and anomalies share filters and drilldowns. |
| General bulk editing replaces a special trip tool | Add a trip label across a range while retaining categories. Category changes and label removal/replacement are separate explicit actions. |
| One organization-rule engine | Merchant cleanup, category assignment, and label addition share configurable rules. No separate built-in category classifier tied to a fixed catalog. |
| Shared calculation and query services | Prevents disagreements between dashboard, budgets, charts, and closeouts and avoids repeated database work. |

These are target Finance decisions. Historical standard/custom categories and tags must not become parallel finance systems. They do not require changing the host's unrelated organization models.

## 3. Category and label contract

**Category answers where money belongs.** Each transaction has `categoryId` or null. Example user-created categories: Dining, Transport, Salary, or Investments. These names are illustrative, not a catalog to seed or special values to recognize. Budgets reference the generated category ID.

**Labels answer what the payment relates to.** Each transaction has zero or more `labelIds`. Examples: Goa Trip, Work, Family, or To Claim. One payment can carry several labels. Labels never change its category or budget allocation. Free-text notes remain available; replace the old single tag field with reusable labels.

For example, a dinner can be category Dining and labels Goa Trip and Work. It uses Dining's budget once and appears in both label-filtered reports. Label totals overlap, so do not sum them into a grand total or display them as a partition of spending.

### No hardcoded organization

- Use generated opaque IDs, never enum category values, reserved names, fixed IDs, or string comparisons such as `category.name == 'Salary'`.
- A newly activated finance scope may have zero categories/labels. Show optional setup/inline Create; never block finance import or host usage because organization data is empty.
- Unassigned is a UI state for `categoryId == null`, not an undeletable category record. It still counts in personal spending and outside-budget coverage.
- Every created category/label can be renamed, recolored, reordered, archived/unarchived, or removed using the lifecycle rules below. There is no protected standard/custom distinction.
- Salary status, ignored state, and confirmed self-transfer relationships are transaction metadata. They must work independently of category/label names.
- Reimbursement tracking uses a user-selected set of label IDs in settings. No particular label name is required. Renaming a selected label preserves its meaning; if none are selected, show setup guidance rather than inventing a Reimbursable label.
- Category/label organization rules are stored records that point to existing IDs. An unmatched SMS leaves its category null. SMS extraction may have bank/protocol patterns; those patterns must not embed category IDs or label names.
- Do not ship a mandatory category catalog or undeletable merchant-category presets. Any future optional imported starter configuration must be previewed, saved as editable records with generated IDs, and removable.

### Lifecycle and assignment safety

Renaming changes display text everywhere without breaking budgets or history. Archiving hides an item from new assignments while preserving historical assignments and reports. Existing budgets may remain visible for an archived category, but the UI must show its archived status; users can deactivate those budgets separately. Enabled rules targeting archived items must be flagged and skip that archived assignment.

Prefer Archive for referenced items. Permanent category deletion requires a preview of affected transactions, budgets, and rules. Offer reassignment to another category or clearing assignments; confirm removal of budgets tied to the deleted category. Do not silently combine budget limits. Permanent label deletion removes its assignment links, rule references, and reimbursement-selection references after confirmation. Disable a rule if deletion leaves it with no valid action. Perform these changes atomically and preserve payments/notes.

**Acceptance:** arbitrary names work; rename preserves budget use; archived history stays readable; deleted IDs leave no dangling links; adding/removing labels never changes budget totals; an empty catalog still permits import, review, and charts.

## 4. Shared financial and data rules

1. **Exact money:** store integer paise or equivalent exact decimals. Positive amount plus debit/credit direction; avoid floating-point rupee sums.
2. **Active data:** confirmed, nonignored transactions meeting the tracking start point. Pending/ignored reviews and skipped SMS contribute zero. New/unassigned confirmed transactions are active without needing acknowledgment.
3. **Tracking:** a date includes that entire local day onward. An anchor includes itself and later records in stable `(timestamp, transaction ID)` order. Resolve the anchor independently of a screen's selected period.
4. **Time ranges:** store timestamps consistently; display device-local time. Use `[start, end)` internally and include the entire last day of date selections. Handle midnight, equal timestamps, and month-end deterministically.
5. **Personal totals:** income sums active credits; spending sums active debits; both exclude confirmed self-transfer pairs. Cash-flow net/savings equals income minus spending, not a bank balance.
6. **Transfers:** retain both account ledger movements, exclude them from personal spending/income, budgets, recurring detection, and spending insights. Ledger counts count original records; grouped cards are display groups. Exports retain both active records with relationship metadata.
7. **Category totals and budgets:** each active debit belongs to its single category or Unassigned. Budget eligibility is based on debit/active/transfer status, never on a category name. Every active category can have a budget. Budget usage covers all eligible expenses in that category/period; a label-filtered subtotal is shown separately and cannot change the budget's actual usage. Labels do not allocate amounts or automatically exclude expenses. Salary marking applies to credits only.
8. **Account views:** personal totals exclude transfers; separately labeled account movements can include them. Honor assigned account ID before extracted suffix/sender fallback.
9. **Edit protection:** rescans preserve direction/source/account, category and manual clearing, labels and explicit removals, notes, salary/ignored state, and transfer links. Record category origin/manual override state independently of direction correction.
10. **SMS identity:** generated app IDs retain source identity/context and a fingerprint. Android row IDs are not globally unique across restored devices. Equal amounts alone never imply duplicate SMS.
11. **Atomic updates:** review resolution, bulk edits, category/label deletion, transfer merge/unmerge, and restore complete fully or leave data intact. Reload affected state after success; preserve edits across restart.
12. **Shared queries:** implement a reusable transaction query for period, direction, account, category, labels, merchant, search, and status. All drilldowns use it. OR within selected categories/accounts; AND between dimensions. Labels default to match-any, with an explicit match-all option. Apply the same query to lists and their summary totals.
13. **Host scope:** every operation carries its finance scope. IDs, name uniqueness, joins, source deduplication, cache keys, and cursors are scope-aware. Reject cross-scope references even when IDs collide. Offline finance access remains subject to host authentication/access policy.

### Minimum persisted data

| Entity | Required fields/relationships |
| --- | --- |
| Transaction | Generated ID; SMS identity/fingerprint/context; exact amount/direction/timestamp; original/normalized sender; merchant; UPI/bank/card/wallet/unknown source; optional account/suffix/reference/SMS balance; raw payment SMS; nullable category ID/origin/manual override; note; corrected/salary/ignored flags; transfer group/partner/role; import batch/time |
| Category | Generated ID; user name; icon/emoji; color; sort order; archived flag; created/updated times |
| Label | Generated ID; user name; icon/emoji; color; sort order; archived flag; created/updated times |
| Transaction-label relationship | Transaction ID, label ID; unique pair; assignment origin; enough override history to protect explicit user removal |
| SMS processing record | Source identity/context; sender/time/folder; transaction/review/skipped outcome; reason; related record ID; optional retained payment-like body; parser version/processing time |
| Import batch | ID; scan start/completion/status; outcome counts; acknowledgment time for clearing the New badge without changing financial data |
| Review item | Source identity; amount/extracted fields; raw payment SMS; nullable category/origin; label relationships; pending/ignored/resolved state |
| Account | ID; name; bank/credit-card/wallet/UPI type; optional suffix/issuer; manual/detected origin |
| Organization rule | ID; match text/optional sender constraint; optional normalized merchant, category ID, and label IDs to add; enabled/priority/creation fields |
| Budget | ID; category ID; positive limit; active flag; suggested/manual origin; timestamps |
| Salary cycle | ID; marked salary event reference(s); start/exclusive end; salary amount; optional employer; totals derived from active ledger |
| Insight | Stable event/period key; type/title/message/severity; optional transaction/query reference; read state/time |
| Settings | Onboarding; tracking date/anchor; salary day; monthly income; reimbursement label IDs; scan cursor/source context; schema/parser versions |

Use foreign keys/indexes and versioned migrations, with finance scope ownership on every persisted entity/relationship. Finance bank/card accounts are distinct from host login accounts; map host identity without copying credentials. Separate many-to-many label links from category storage; derived results need not be stored. Do not introduce legacy category/tag columns as competing finance sources or repurpose unrelated host tables.

## 5. Host entry and internal Finance navigation

Register Finance in the host's existing service hub/home/menu. The table describes destinations within Finance, not replacement global host tabs. Finance Settings may also be linked under Host Settings / Services / Finance, opening the same module screens.

| Main destination | Content | Integrated actions/details |
| --- | --- | --- |
| Overview | Current-period income/spending/net, recent payments, budget progress, account cards, import/review counts, important insights | Scan SMS; filtered ledger; account detail; current closeout; Settings |
| Transactions | Shared ledger and Inbox switch; search/filter/sort; selection/bulk editing | Detail editor; new-import list; needs-review/unassigned/transfer queues; ignored/skipped history |
| Plan | Budgets, Salary Periods, Recurring Payments sections with a shared period selector | Budget transaction drilldown; coverage gaps; salary marking; cycle closeout; recurring history |
| Insights | Category/Account/Merchant/Calendar views and Insights feed | Shared filters; chart-to-ledger drilldowns; anomaly/duplicate/digest actions |
| Finance Settings / Organize | Finance Categories, Labels, Rules; tracking/reimbursement preferences; finance data I/O | Reused contextual editors; optional link from host service settings |

The Inbox is one destination with counts and filters, not many independent home shortcuts. Default to actionable queues; ignored/recoverable skipped records remain reachable in History within it. Transfer suggestions appear in Inbox and link to pair details; confirmed transfers appear in the ledger. Alerts that require a decision link to the relevant queue or filtered transactions.

Use one Period Selector component across destinations. Overview initially uses saved salary cycle, then configured salary-day window, then calendar month. Plan uses saved salary cycles or calendar months. Insights additionally supports rolling 7/30/90/365 days. Transactions defaults to all active history; a drilldown carries the originating query/period and clearly displays it. Navigating back restores the caller's filters and scroll state.

Finance accounts open from its Overview/Account insights and reuse the ledger. Organization editors reuse contextual forms. Preserve finance drafts/scroll and host navigation state on module entry/exit. Names such as Settings, Overview, and Inbox below mean Finance destinations unless explicitly identified as host UI.

## 6. Functional requirements and acceptance criteria

### F01. Onboarding and tracking

On first Finance activation for the active scope, offer Track Everything, custom date, This Month, Last 30 Days, and Last 90 Days. Optional organization setup stays skippable. Store finance activation/onboarding/tracking independently of host onboarding. Initial scan follows an explicit permission/import action. Finance Settings supports changing/clearing tracking or choosing a searchable stored transaction anchor.

**Acceptance:** restart retains scoped choices; tracking changes preserve history; ties work; optional setup can be skipped; host users see Finance onboarding once without repeating host onboarding or blocking unrelated services.

### F02. SMS access, extraction, and scanning

Explain/request Android `READ_SMS` only after an explicit Finance setup/import action, coordinating with the host permission adapter. On Finance entry, load scoped cache promptly; after activation auto-scan only with permission already granted, or scan via manual refresh. Never request permission or scan merely because the host launched. Show progress/counts, prevent concurrent scope scans, and advance the scoped cursor after persistence. Use overlap lookback (reference: two days) plus identity deduplication.

Normalize formats such as `DM-HDFCBK` and `AD-AIRBNK-S`. Cover common Indian bank/card/payment senders and UPI/wallet messages, including HDFC, ICICI, SBI, Axis, Kotak, PNB, Bank of Baroda/OneCard, Airtel/Jio Payments Bank, Paytm, Google Pay, PhonePe, BHIM, and Amazon Pay. Unfamiliar inbox messages can qualify when amount indicators and financial context coexist. Sent personal messages never become payments. Sender recognition alone does not confirm a payment.

Extract amount/direction/timestamp, merchant/sender/source, suffix, optional reference/balance. Support INR/Rs/rupee-symbol amounts, commas/decimals, paid/spent/debited/received/credited wording, UPI/card/wallet/NEFT/IMPS/RTGS. Distinguish amount from balance/reference numbers. Skip marketing, reminders, failed/pending attempts, and OTP/security messages without completed-payment evidence. Ambiguity goes to review or explained skip.

Persist one outcome per source identity within the finance scope. Retain skipped body only for payment-like recovery; other skips keep metadata. Permission denial preserves authorized cached finance access and all host functionality. Guard profile changes during scanning so data never lands in another scope. Parsed merchant/source are extraction results; organization requires scoped stored rules or user action.

**Acceptance:** repeat/interrupted scans retain edits; extraction/privacy checks pass; empty organization yields null category; host launch never requests SMS; refusal does not block the host; profile switch during import cannot leak or misassign data.

### F03. New imports inside the Inbox

After a scan, show a compact summary with parsed/review/skipped counts and View New Imports. Maintain a New filter/batch in Transactions rather than forcing a blocking review popup on every refresh. Users can acknowledge all, ignore selected records, or Ignore All after confirmation. New confirmed records are active immediately; acknowledgment only clears the new badge.

**Acceptance:** ignore updates totals and is restorable; repeat scans do not repeat the same new batch; scan summary links to unresolved messages; acknowledgment never changes amounts or category assignments.

### F04. Finance Overview

Inside Finance show current-period dates, income/spending/net/count, five recent records, budget coverage, finance accounts, review counts, and insights. Offer Scan/See All/internal navigation and return to the host. A lightweight direction/account filter may narrow recent records; state summary scope. An optional host-home Finance shortcut/badge can link here but must follow host access rules and must not expose balances/SMS content outside the authorized scope or replace host home.

**Acceptance:** totals obey shared rules; empty categories do not break cards; links carry the right period/query; salary-day fallback clamps months (day 25 on 10 March starts 25 February).

### F05. Shared ledger and transaction editor

Support All/Money In/Money Out, merchant/sender/note search, account/sender/category/label filters, label match-any/all, period/cycle filters, newest-first and amount sorting with stable ties. Show Unassigned as a filter. Opening any budget/chart/account/label/merchant query uses this component.

Details show amount/direction/time, source/merchant/account, optional balance/reference with copy, expandable SMS, category, label chips, note, corrected/ignored state, and transfer information. Edit direction/source/account/category, add/remove multiple labels, edit/clear note, mark eligible credits as salary, or ignore/restore. Category and label pickers support inline create/manage. No separate standard/custom category controls or free-text tag field.

Provide clear swipe-ignore/correct with Undo/confirmation and multi-select bulk actions. Ignored history is an Inbox filter using the shared detail editor. Ignore a grouped transfer as a pair. Changing direction of a linked transfer requires unmerging first; changing a salary credit to debit clears its salary flag with confirmation.

**Acceptance:** queries and displayed totals agree; edits persist across restart/rescan; create-in-picker preserves the draft; label operations do not alter category/budget; filters from a drilldown are visible/resettable.

### F06. Combined review and recovery queues

Inbox filters: Needs Review, New Imports, Unassigned, Transfer Suggestions; History exposes Ignored Transactions, Ignored Review Messages, and Recoverable Skips. Show counts and record-type distinctions. Unassigned is confirmed ledger data, not an ambiguous SMS review item.

For unclear direction with readable amount, show SMS/extracted fields and let users choose Debit/Credit, category, labels, create a rule, or Ignore. Confirm atomically saves one payment and resolves review. Restore ignored reviews to Needs Review. A retained payment-like skip with unreadable amount can be sent to review after positive amount entry. Recheck only skips without reopening resolved/ignored decisions or overwriting edits.

**Acceptance:** resolving twice cannot duplicate; unresolved messages contribute zero; unassigned confirmed expenses do count; recovery/restore return to the correct queue; invalid amounts are rejected.

### F07. Unified organization, labels, and notes

Finance Organize contains Categories, Labels, and Rules. CRUD/appearance/lifecycle follow section 3. Category assignment is one nullable ID; labels are a set of existing IDs. Validate trimmed/nonempty names and prevent duplicate active names within each type and finance scope ignoring case; category and label may independently share a name. Do not alter host categories/tags used by unrelated services.

Assign manually or through F08 rules and store assignment origin. No rule match means Unassigned, for credits and debits alike. Keep manually selected/cleared category protected. Keep manual label additions/removals protected when rerunning rules. Notes remain free text.

Refresh Organization previews proposed rule-based category/merchant/label changes, highlights protected fields, and applies only approved eligible changes. This replaces the fixed automatic-category refresh.

**Acceptance:** arbitrary names are supported everywhere; no income/expense/budget behavior changes when an item is renamed; every assignment refers to a valid ID; manual choices survive refresh; lifecycle operations do not lose payments.

### F08. Database-backed organization rules

One rule can normalize merchant, assign category, add labels, or combine these actions. Require nonblank SMS match text and at least one valid action; merchant name is required only for a merchant-normalization action. Optional sender constraint narrows matching. Rules point to category/label IDs chosen from the same pickers, with inline Create.

Match case-insensitively. Select the winning rule by user priority, longest match, newest creation time, then stable ID. Only that rule's actions apply; show this behavior in preview when rules overlap. Disabled rules never apply. Support create/edit/reorder/enable/disable/delete for every rule; no undeletable brand/category presets. Creating a rule from a payment prefills extracted text but requires a preview before saving/enabling.

Apply to Existing previews matches, actions, and protected fields. Preserve direction/amount/account/source/note/transfer metadata and manual category selection/clearing. Labels are added without replacing existing labels and respect explicit removals unless the user approves an override. Confirm any proposed protected-field override separately. Disabling/deleting a rule does not undo saved changes.

**Acceptance:** labels-only/category-only rules work; winner is deterministic; renamed category still matches by ID; deleted/archived targets are handled safely; no code maps brand text to a fixed category name/ID.

### F09. Bulk editing and trips

From Transactions select individual records, a whole-day range, or two transaction boundaries in stable `(timestamp, ID)` order. Include both boundaries and normalize reversed selections. Default scope is active confirmed history; show selected count/dates/personal totals plus transfer/ignored exclusions where relevant.

Offer category action Keep/Set/Clear and label actions Add/Remove, with an explicit advanced Replace All Labels action requiring confirmation. Default keeps category/existing labels. Preview every effect before atomic Apply; Cancel changes nothing. Add a Trip label across dates using the general tool; retain Dining/Transport/etc. categories and budget allocations. Keep/create labels inline without losing the selection. Preserve notes and all untouched fields.

**Acceptance:** adding a trip label does not move category budgets; date ranges include 23:59 on the last day; label removal does not remove unrelated labels; boundary ties are stable; bulk replacement/clearing requires explicit selection; failed save changes nothing.

### F10. Account summary and ledger integration

Detect candidate bank/card/wallet/UPI accounts from imports; support manual create/edit/delete with name/type and optional suffix/issuer. Show account cards on Overview and comparisons in Insights. Account detail combines summary with shared ledger and source correction. Avoid duplicate detection or merging banks because suffixes happen to match.

Honor assigned account ID; unmatched data uses a labeled unassigned-account group. Deleting an account clears assignments atomically but preserves payments/extracted suffixes. Show personal spending/net distinctly from account movements including transfers; no claim of live bank balance.

**Acceptance:** repeated detection is idempotent; assignments update every account view; shared ledger filters correctly; transfer movements do not inflate personal totals; account deletion preserves history.

### F11. Salary periods and integrated closeouts

In Plan / Salary Periods suggest possible salary credits from wording/recurring credits and require user marking. Salary is metadata, independent of category/label names. Generate cycles from active marked events: start at event, exclusive end at next; last is active. Group simultaneous credits; regenerate removes stale cycles without altering payments.

Separate salary day 1-31 supplies the Overview fallback and does not fabricate income/cycles. Clamp month-end dates. Period cards show salary, spending, salary-based remainder, percent spent, days/employer/active state. Opening one shows closeout and shared ledger together; avoid separate competing totals screens. Label salary remainder (`salary - spending`) and cash-flow savings (`all income - spending`) distinctly.

Closeout shows income/spending/salary/net, first/final seven calendar days' spending, lowest cumulative net flow/date starting at zero, top three category changes against previous cycle, recurring burden, and selected-label reimbursement expenses. Reimbursement label IDs are configurable in Organize/Settings; match any selected label and count a record once. Removing the relevant labels removes it from this report; no automatic settlement. Active closeouts are provisional.

**Acceptance:** cycles have no gaps/overlap; unmark/regenerate clears stale cycles; whole-day week boundaries work; transfers/ignored records are excluded; renaming a salary category or reimbursement label does not change calculations.

### F12. Category budgets and integrated coverage gaps

In Plan / Budgets create/edit/deactivate/delete one positive limit per category. Every active category is eligible; no reserved names or label budgets. Show spent/limit, remaining/overspend, percentage/progress, suggested status, and coverage summary for the selected salary cycle or calendar month. Deactivation makes later selected-period coverage treat that budget as inactive; historical limit snapshots are not required in this version.

Tap a budget to open its category/period query in the shared ledger. Show Unassigned and categorized-without-budget expenses in a Coverage Gaps section on the same page, expandable to a filtered ledger. Assign category or create category/budget inline; never imply labels affect coverage. Recompute after edits.

Suggestions average expenses by category across calendar months containing eligible expenses, treating missing category-months as zero; add 10%, round to INR 500 half upward, use INR 500 if rounded to zero, cap after rounding at positive configured monthly income. Zero income means no cap. Skip null/archived category suggestions and offer assign-category guidance instead. Preview and confirm replacing manual budgets. Monthly income is an optional planning input, not fabricated ledger income.

**Acceptance:** category expense counts once even with many labels; trip labels preserve usage; arbitrary/renamed categories work; unassigned/unbudgeted expenses remain in coverage gaps; labels cannot create a second budget allocation; low/empty history handles safely.

### F13. Consolidated analysis and recurring payments

Insights uses shared period/account/category/label filters and Category/Account/Merchant/Calendar views. Plan / Recurring Payments houses the former EMI-like detector and occurrence details; closeout links to it rather than duplicating detection logic.

| View | Required behavior |
| --- | --- |
| Category | Pie/ranked totals, shares/counts; include Unassigned; each record once; chart tap opens ledger query |
| Account | Personal totals/comparison bars, ledger counts/net; separate clearly labeled transfer-inclusive movements |
| Merchant | Leading bar chart/ranked totals/share/count; normalized merchant with sender fallback |
| Calendar | Month navigation/intensity legend; tap day for ledger; total, average per spending day, peak day/amount, active-day count |
| Label context | Label filters and optional comparison totals; warn that labels overlap; never a pie partition or summed grand total |
| Recurring Payments | Candidates by amount; active/inactive, estimated amount/day, occurrences/history, active/detected count and monthly burden |

Provide All Time and rolling 7/30/90/365-day choices where meaningful, plus salary cycles/custom range through the shared selector; Calendar retains month navigation.

Recurring detection uses normalized merchant/sender and similar amounts (initial amount grouping: nearest INR 100), at least two occurrences, at least half of intervals 25-40 days, and maximum deviation 10% from mean. Active means last occurrence within 45 days; burden sums active average amounts. These are recurring-payment candidates, not verified loans or notifications; classification into category/labels remains user-managed. Use an injectable clock.

**Acceptance:** charts/drilldowns agree; arbitrary category/label edits appear without code changes; label overlaps do not inflate totals; heatmap average excludes no-spend days; recurring results exclude transfers/ignored records.

### F14. Transfer review and repair

Put equal-amount unlinked debit/credit pair suggestions in Inbox. Explain confidence using timing, account difference, reference, transfer words, source and amount. Known same-account pairs are ineligible; no automatic merge or ownership claim. Bound/paginate candidates and prevent overlapping accepted groups.

Pair detail offers Confirm Transfer, Dismiss/Undo, and underlying records. Confirm atomically sets group/reciprocal links and debit-source/credit-destination roles. Confirmed pairs appear as grouped ledger cards with accounts/date/amount and Unmerge. Dismissal can last for the current review session; refresh may restore suggestions. Unmerge clears both links and retains organization/notes.

Data Integrity Check is an advanced data-maintenance action in Settings with links from broken pair details. Report missing partners, oversized groups, mismatched amount/direction/roles/links. Preview safe repairs; clear orphaned/corrupted links without deleting payments; leave uncertain mismatches for manual review and report unresolved counts.

**Acceptance:** reject same-record, wrong-direction, unequal amounts or already-linked merges; no partial updates; unmerge recomputes totals; labels/category edits remain; repair never deletes payments.

### F15. Insights feed and actionable notifications

Insights includes an in-app feed, while Overview surfaces important unread items. Explicit Refresh Insights scans active data. Store stable event/period keys, preserve read state, support individual/all read and clearing alerts older than 30 days. Cards open shared queries, budgets, or the relevant Inbox queue. Duplicate/transfer decisions do not require a second independent review workflow.

| Insight | Initial rule |
| --- | --- |
| Unusual merchant spending | At least five eligible ledger records overall, three merchant expenses, recent and historical data; recent seven-day spend at least 2x historical weekly average warning, 3x critical. Use sorted historical dates and at least one week denominator. |
| First-time high charge | One eligible merchant expense within 30 days greater than INR 5,000 |
| Possible duplicate | Same amount/normalized sender/direction, within five minutes, distinct source identities; flag, never automatically delete |
| Budget | Warning 80% to below 100%; critical 100% or more; chosen active planning period |
| Recurring payment | Active candidate with at least three occurrences, linked to Plan / Recurring Payments |
| Digest | Previous local day's expense total/count and current-period budget use where available |

Filter the feed by type/severity/read state rather than requiring many standalone alert screens. Scan failure keeps existing results and exposes Retry.

**Acceptance:** repeated scans do not duplicate/reset read state; no category/label name affects alert eligibility; transfers/ignored items do not trigger spending alerts; opening a card preserves its query context.

### F16. Settings, encrypted backup, and complete export

Finance Settings contains Organize, scoped tracking/salary/reimbursement preferences, local processing information/counts, recheck skips, integrity, finance backup/restore, and export. Link from Finance and optionally Host Settings / Services / Finance. Export the current finance query from Transactions as well; preserve host settings and unrelated data controls.

Backup only the active scope's persisted finance data: payment SMS, reviews, categories/labels/links, rules, budgets, finance settings/accounts, insights, import metadata, and transfers. Include finance format/schema/scope metadata but no host credentials/tokens, other profiles/services, or device-wide database dump. Request/confirm password and never store it. Use authenticated encryption such as AES-GCM with fresh salt/nonce and password-derived key off the UI thread. Reuse host Android Storage Access Framework integration without broad storage permission.

Restore validates password/format/schema/integrity and previews target scope/date/counts. Offer Merge Finance Data or Replace Finance Data in the currently authorized scope only; never reset the host app/database or change host identity. Explicitly confirm importing a user-selected backup from another scope into the active one, remapping ownership rather than restoring host access. Merge preserves conflicting local finance edits/settings. For same-name/different-ID conflicts, preview an imported name suffix and retain valid relationships; mapping to an existing item needs explicit selection and budget-conflict review. Remap all finance links consistently. Replace requires destructive confirmation and atomic finance-only changes. Password/file/cancellation/write failures leave host and finance data intact; scope switch aborts or safely completes against the captured authorized scope. Reconcile scan context/cursor and refresh finance caches afterward.

JSON export supports All Active, dates, cycle, and current query within the active finance scope. Include version/time/query/period/count and transaction ID/date/amount/direction/source, merchant/sender/suffix, category ID/name, label ID/name pairs, note, salary/transfer flags/group, and referenced organization metadata. Retain both active transfer records. Exclude ignored/untracked records, pending reviews, SMS/balances/references/fingerprints, host identity/credentials, and other service/profile data. Explain contents and reuse host sharing integration.

**Acceptance:** round-trip preserves finance organization/links; merge is idempotent and conflict-safe; password/cancellation failures change nothing; query exports are accurate/private; finance Replace never changes unrelated host tables/settings/accounts; switch/logout cannot leak another scope's data.

## 7. Engineering and performance

- Keep Finance in a feature/module boundary using host conventions. Separate its UI/state, repositories, SMS extraction, rules, calculations, queries, transfers, and I/O; inject host context/storage/SMS reader/clock for tests.
- Reuse host router, state/DI, theme/localization, platform channels/adapters, error handling, and shared components where compatible. Namespace route/state/table/channel names and models such as FinanceAccount to avoid collisions. Do not create a second application shell or competing global service container.
- Use one finance calculation/query contract for all views. Cache by finance scope, data revision, and query; invalidate after edits/scope switch. Never serve a prior profile's result from cache. Keep one category/ledger source of truth.
- Batch writes; index source identity, timestamps, category/account IDs, and label join pairs. Paginate/virtualize long lists. Do not reread all SMS/database rows on every widget build.
- Keep scans/rule previews/insights/encryption responsive with progress, retry, cancellation where feasible, and cached-data access. Do not advance completion state before durable writes.
- Reuse Period Selector, Transaction List/Editor, Category Picker, Label Picker, Account Picker, Rule Editor, and confirmation/preview components.
- Implement loading/empty/error/permission-denied/success states; preserve filters, scroll and draft edits across contextual navigation. Respect safe areas, keyboard, large text, screen readers, and dark mode.
- Initialize lazily on authorized Finance entry. No SMS request/scan, schema reset, or heavy work on unrelated host startup paths. Cancel subscriptions/in-flight work safely on scope change/module disposal and preserve host lifecycle behavior.
- Keep finance/SMS/passwords out of telemetry/logs and provide offline finance behavior within host access policy. Preserve host application ID, branding, signing, entrypoints, flavors, and build workflow; document finance integration rather than standalone app setup.
- Reference Flutter dependencies include Provider, sqflite, another_telephony, permission_handler, intl, fl_chart, uuid, and share_plus. Prefer compatible host packages/adapters over duplicate state/database/permission/share stacks. For another framework, implement equivalent module behavior without embedding a new Flutter app. Document only necessary dependency/native changes.

## 8. Delivery and validation

Follow the implementation plan below in dependency order. Complete each phase's working behavior and relevant checks before marking that phase complete. A feature spanning multiple phases stays partially implemented until all its dependencies and acceptance criteria pass. All F01-F16 remain required despite fewer screens.

### Execution rules for the agent

- Read this entire specification first. Treat sections 1-7 as the product contract and the following phases as the execution order.
- Work inside the supplied host repository. Inspect its instructions, framework, service registry, routes, identity/lifecycle, design system, persistence/migrations, native adapters, and build/test setup. Record the Finance module location and integration changes; do not run a new-app initializer or replace host startup.
- Reuse host choices for dependencies/state/folders where compatible. Record necessary additions and unresolved capability gaps. A fixed finance category catalog or name-based business rule remains prohibited.
- Maintain `FINANCE_IMPLEMENTATION_STATUS.md` in the host's documentation location: host integration map/baseline checks, module ownership/scope policy, phase status, F01-F16 coverage, changed host/finance files, executed results, and remaining work. Do not overwrite another feature's progress document.
- At each phase: implement, verify the relevant behavior, fix failures, update the status file, and give a short progress report. Continue to the next phase without asking for routine approval unless the user requested a stop or a single-phase run.
- Initial Finance scaffolding is temporary. Placeholders/inert controls/fake production services do not satisfy a feature. Keep existing host features operational while integration proceeds.
- Fixtures use isolated finance test storage/scopes and never populate host production data. A newly activated scope has no mandatory categories/labels/fake transactions.
- If a tool/device check is unavailable, report what was attempted and mark it unverified. Continue independent work, but do not claim a blocked check passed or the affected feature was fully verified.
- Do not fill Finance with extra scope or unrelated host refactors. Preserve four internal destinations, host global navigation, and shared finance components. Extend the existing app; do not create a standalone clone.

### Phase 1. Inspect the host and register the Finance module

**Implement:**

1. Inspect the existing repository and record framework, service entry points, navigation, identity/profile lifecycle, DB/migrations, design system, permissions/native adapters, and build/test conventions.
2. Run available baseline host checks and distinguish pre-existing failures from integration regressions. Document the Finance module path, required host edits, scope ownership, and capability gaps.
3. Register one Finance service entry and internal Overview/Transactions/Plan/Insights routes using host guards/router. Reuse host appearance and back behavior; add Finance Settings without replacing Host Settings.
4. Establish module domain/repository/service/state boundaries and injectable host context, persistence, SMS, clock, and data-I/O adapters.
5. Preserve application ID/signing/branding/global startup. Document necessary dependency additions, integration build commands, and feature checklist.

**Complete when:** the host launches/builds as before; Finance is reachable and exits back correctly; guards/theme follow the host; no global tabs/login/app identity are replaced; no SMS request or fixtures appear on host startup. Internal scaffolds stay marked unfinished until later phases deliver behavior.

### Phase 2. Implement finance models and host-compatible persistence

**Implement:**

1. Model exact money, nullable category, reusable labels, label relationships, accounts, transaction metadata, and manual assignment/removal protection.
2. Add the section 4 finance entities with stable host-profile/device scope ownership; namespace tables/models to avoid existing host entities.
3. Integrate additive migrations into the host coordinator or a separate Finance-owned DB. Add foreign keys/indexes/unique identity and label-pair constraints within scopes; reject cross-scope links.
4. Implement scoped repositories/atomic changes/settings and lifecycle-safe context handling. Do not copy host credentials or reset host schema/data.
5. Establish isolated finance fixtures/test storage and host-upgrade preservation tests.

**Complete when:** Finance initializes on an existing populated host installation without losing data; scoped reopen/constraints/rollback/migration tests pass; profile isolation is enforced; empty categories are valid; host schema coordination remains intact.

### Phase 3. Build the shared query and financial calculation layer

**Implement:**

1. Create scope-enforced transaction queries for period, direction, finance account, category/Unassigned, labels any/all, merchant, search, and status. Callers cannot omit ownership filtering.
2. Resolve active/ignored/tracked data, stable timestamp/ID ordering, whole-day ranges, transaction anchors, and salary-day fallback with month-end clamping.
3. Calculate personal income/spending/net, ledger counts, category totals, and separately labeled account movements with consistent transfer exclusion.
4. Ensure category budgets use the full category-period expense set; expose filtered label subtotals separately.
5. Add scope/data-revision/query cache invalidation and clear visible results on profile switch/logout according to host policy.

**Complete when:** money/query/boundary/transfer checks pass; renaming does not change ID-based results; two profiles with colliding names/IDs cannot see each other's rows, settings, or cached summaries.

### Phase 4. Deliver category and label management

**Implement:**

1. Build Finance Organize / Categories and Labels within the module, using host UI/localization and scope-local name validation. Preserve unrelated host organization screens.
2. Implement the reusable Category Picker and multi-select Label Picker with inline Create/Manage and draft preservation.
3. Add referenced-item impact previews and atomic permanent-delete flows for remap/clear, budget removal, rule cleanup, and reimbursement-label references.
4. Add reimbursement-label selection by ID without requiring a particular name.

**Complete when:** empty setup, inline creation, rename propagation, archive history, and safe deletion pass repository/widget checks. Assignment supports one category and multiple labels; deletion preserves payments and leaves no dangling references.

### Phase 5. Deliver the shared ledger and transaction editor

**Implement:**

1. Build the Transactions ledger from the shared query service with search, filters, label any/all, period selection, sorting, pagination, and visible query scope.
2. Build one detail editor for direction/source/account/category/labels/note/salary/ignored metadata, optional SMS/balance/reference display, and copying.
3. Implement manual assignment protection, persistent edits, swipe actions with Undo/confirmation, and ignored transaction history.
4. Add Finance routes for filtered-ledger navigation, caller-state return, and host-guarded deep links. Enforce salary-credit/linked-transfer invariants and discard inaccessible drafts on scope change.

**Complete when:** fixture-backed behavior uses the real repository; edits survive restart; list and summary agree; labels never change category budget allocation; shared editors/pickers handle missing optional data. Transfer-specific confirmation is completed in Phase 9.

### Phase 6. Implement onboarding, Android SMS import, and core Inbox

**Implement:**

1. Deliver per-scope Finance activation/onboarding/tracking without changing host onboarding. Optional organization stays skippable.
2. Integrate existing host permission/native registration with a real SMS adapter and pure extraction parser; prompt only from an explicit Finance action.
3. Add scoped cached-data-first scans, cursors/deduplication/outcomes/batches and profile-switch cancellation/commit safety. Auto-scan only on authorized, previously activated Finance entry with granted permission.
4. Implement the nonblocking import summary/New queue and persistent acknowledgment; new confirmed records become active immediately.
5. Build Needs Review, Unassigned, and History queues, atomic Debit/Credit resolution, ignored-review restore, malformed-amount recovery, and safe skipped-message recheck.
6. Leave unmatched imported payments category-null; no catalog or brand/category classification may be introduced as an import fallback.

**Complete when:** parser/import/privacy/review checks pass; acknowledgment does not change totals; host launch/permission denial/non-Android entry are safe; scope switch during scanning cannot misassign data. Test Android import where available. Rule execution follows in Phase 7 and transfers in Phase 9.

### Phase 7. Deliver organization rules and general bulk editing

**Implement:**

1. Build stored merchant/category/label actions with optional sender constraint, priority, deterministic winner, and enable/edit/reorder/delete controls.
2. Integrate the rule engine into new import/review flows; use generated category/label IDs and skip invalid/archived assignments safely.
3. Deliver rule creation from a transaction, match preview, Apply to Existing, Refresh Organization, and explicit override confirmation with manual-field protection.
4. Implement selection, whole-day and transaction-boundary bulk ranges; category Keep/Set/Clear; label Add/Remove and explicitly confirmed Replace All.
5. Make adding a trip label preserve existing categories, labels, notes, and budget allocations by default.

**Complete when:** category-only and label-only rules work; overlaps are deterministic; disabled rules do nothing; manual clearing/removal remains protected; bulk changes are atomic and boundary checks pass.

### Phase 8. Integrate accounts and the Overview

**Implement:**

1. Detect candidate accounts without duplicates or suffix-only cross-bank merges; deliver manual create/edit/delete and transaction assignment.
2. Build account cards/details with the shared ledger and separately labeled personal totals/account movements.
3. Wire Finance Overview to scoped totals, records/accounts, scan/Inbox state, filtered navigation, and return to the host; optional host shortcut/badge follows access rules.
4. Complete tracking/date fallback labels and empty/error states. Keep budget and insight integration explicitly pending their later phases.

**Complete when:** finance accounts/history/totals are correct, host login accounts are untouched, module navigation/cache are scoped, and host/Finance remain usable after permission denial. Budget progress follows in Phase 10 and insight cards in Phase 12.

### Phase 9. Complete transfer review and integrity repair

**Implement:**

1. Add explainable bounded pair suggestions to the existing Inbox, temporary Dismiss/Undo, and underlying-record navigation.
2. Implement confirmed merge/unmerge atomically with reciprocal links/roles and grouped ledger cards.
3. Support pair ignoring/restoring and enforce direction changes through explicit unmerge.
4. Add Settings integrity reports, safe repair previews, and unresolved issue counts without deleting payments.
5. Recheck shared totals after every relationship mutation.

**Complete when:** invalid/overlapping merges are rejected, rollback prevents partial pairs, unmerge preserves organization/notes, repair retains records, and personal totals exclude confirmed pairs consistently.

### Phase 10. Deliver Plan budgets and salary closeouts

**Implement:**

1. Generate/regenerate contiguous salary cycles from marked credit events and remove stale derived cycles; support separate salary-day fallback.
2. Build Plan / Salary Periods cards and closeout with shared ledger, distinct remainder/net measures, whole-day timing, category changes, and configurable reimbursement labels.
3. Build Plan / Budgets with category-ID limits, activation/deletion, periods, usage/overspend, suggestions, and inline category creation.
4. Integrate Coverage Gaps for Unassigned/unbudgeted records with recategorization and shared ledger drilldowns.
5. Connect Overview budget progress and current closeout. Recurring closeout data is completed in Phase 11.

**Complete when:** cycle boundaries/regeneration, arbitrary category budgets, rename persistence, label-independent allocation, suggestion rounding/caps, and reimbursement-ID checks pass. Planning income never creates ledger income.

### Phase 11. Deliver recurring payments and chart analysis

**Implement:**

1. Implement one clock-injected recurring detector with the F13 interval/amount/activity thresholds.
2. Build Plan / Recurring Payments list/detail and connect its derived data to salary closeouts.
3. Build Insights Category/Account/Merchant/Calendar views from shared queries, with common period/category/account/label filters.
4. Add text totals/legends, zero-data handling, month navigation, and chart-to-ledger drilldowns.
5. Ensure label context remains overlapping filters/totals and never an additive spending partition.

**Complete when:** chart and query totals agree, heatmap/recurring boundary cases pass, all drilldowns reuse the editor, and renamed items appear without source changes.

### Phase 12. Deliver the actionable Insights feed

**Implement:**

1. Implement F15 anomaly, first-charge, duplicate, budget, recurring, and digest rules using shared data and an injectable clock.
2. Persist stable insight keys/read state; add explicit refresh, type/severity/read filters, cleanup, and retry without losing existing results.
3. Link cards to budgets, recurring candidates, shared ledger queries, and Inbox review decisions.
4. Wire Overview unread counts and important cards; remove duplicate standalone review/alert workflows.

**Complete when:** repeat scans are idempotent and preserve read state, thresholds/history cases pass, ignored/transfers do not inflate alerts, and deep links retain query context.

### Phase 13. Deliver encrypted backup, restore, and query export

**Implement:**

1. Complete Finance Settings and reuse host document-picker/share/native adapters without changing unrelated data controls.
2. Implement versioned encrypted backups containing only the active scope's finance entities/links, never host credentials/settings or other profiles/services.
3. Implement scoped preview/Merge Finance Data/Replace Finance Data with authorized target ownership, conflict remapping, atomic rollback, and scan-context reconciliation. Never wipe the host database.
4. Export active finance queries with readable organization metadata and all privacy/ownership exclusions.
5. Refresh only relevant finance state and verify IDs/links; prove that host records and another scope remain unchanged.

**Complete when:** scoped round-trip/failure/conflict/remap/export checks pass; Finance Replace demonstrably preserves unrelated host rows/settings/identity and other scopes; lifecycle changes cannot leak restored data. Test actual Android adapters and list unverified integrations.

### Phase 14. Verify Finance and host regressions, then hand over

**Implement and verify:**

1. Run all finance scenarios, arbitrary-name checks, scoped-data tests, host-entry/back/deep-link guards, and existing populated-install migration checks.
2. Check four internal destinations, Finance Settings/Inbox/editors, restart/rescan, host theme/localization/accessibility, profile switch/logout, permission denial, and non-Android safe entry where supported.
3. Remove finance placeholders/fixtures/duplicate infrastructure and fix introduced host regressions without unrelated redesign.
4. Run the host's existing analysis/tests and Android debug build. For Flutter use `flutter analyze`, `flutter test`, and the established `flutter build apk --debug` command with required flavor/entrypoint options. For another framework use equivalent documented host checks; native Android finance smoke checks remain required where executable.
5. Finish host-compatible integration documentation and `FINANCE_IMPLEMENTATION_STATUS.md`, listing F01-F16 evidence, changed host files/migrations/adapters, baseline vs final results, and unresolved limitations.

**Complete when:** all finance requirements and host integration contracts have working evidence; required executable checks pass with no introduced host regressions; existing service/navigation/identity/data flows remain intact. Distinguish pre-existing baseline failures and unavailable device checks honestly, without claiming full verification.

### Feature-to-phase coverage

| Requirement | Implementation phases |
| --- | --- |
| F01 Onboarding/tracking | 2, 3, 6 |
| F02 SMS import | 2, 6, 7 |
| F03 New imports | 2, 6 |
| F04 Finance Overview | 3, 8, 10, 12 |
| F05 Ledger/editor | 3, 4, 5, 8, 9 |
| F06 Inbox/recovery | 6, 7, 9 |
| F07 Organization | 2, 4, 5, 7 |
| F08 Rules | 2, 7 |
| F09 Bulk/trips | 3, 5, 7 |
| F10 Accounts | 2, 5, 8 |
| F11 Salary/closeout | 3, 10, 11 |
| F12 Budgets/coverage | 3, 4, 10 |
| F13 Analysis/recurring | 3, 8, 11 |
| F14 Transfers | 3, 5, 9 |
| F15 Insights feed | 3, 11, 12 |
| F16 Data I/O/settings | 2, 4, 6, 9, 13 |

Phase 14 validates all requirements and the host integration contract together. The matrix does not replace feature or host acceptance criteria.

Deliver the Finance module plus necessary host integration/native changes, dependency additions, additive migrations, fixtures/tests, and integration README. Document service registration/routes, scope/lifecycle policy, host setup/build steps, offline/privacy behavior, parser coverage, and limitations. Run host checks and Android finance smoke tests; record unavailable checks explicitly. A standalone app is not a valid substitute deliverable.

Test financial/import/organization/query/boundary/atomicity/I-O behavior as specified, plus host installation upgrades, entry/back routing, access guards, lazy initialization, per-profile isolation, scope-switch cancellation/cache clearing, finance-only replacement, and unaffected existing services. Final handoff maps F01-F16 and integration contracts to evidence. Placeholders or introduced failing required checks mean integration is incomplete.

### Synthetic acceptance scenarios

The following names are examples created in an authorized finance scope, not seeded constants. Repeat with unrelated names and retain existing host fixtures to detect hidden naming dependencies or host data damage.

1. Start with no categories/labels. Import salary credit INR 50,000, debit INR 500, debit INR 1,000 and confirmed self-transfer debit/credit INR 10,000. Income is INR 50,000, spending INR 1,500, net INR 48,500; both expenses appear as Unassigned/coverage gaps.
2. Create Dining and Shopping categories and assign the debits; create their category budgets. Ignore Shopping payment: spending INR 500; restore: INR 1,500. Restart/rescan retains all edits.
3. Add Goa Trip and Work labels to Dining. Dining budget uses INR 500 once. Each label filter finds the same payment; their overlap does not become INR 1,000 spending.
4. Rename Dining to Meals and Goa Trip to Holiday. Budgets/rules/exports still follow the original IDs. Archive Meals: history remains visible. Delete only after explicit remap/clear and related-budget confirmation.
5. Add Holiday to an inclusive two-day window containing a last-day 23:59 payment. Categories/budget usage and unrelated labels are unchanged; ignored/out-of-tracking records stay untouched.
6. Configure Work as a reimbursement-tracking label, rename it to Claims, and verify closeout still includes the same ID's expenses. Remove Claims from a payment and it leaves that report.
7. Import ambiguous `INR 250 transaction at ACME via UPI`: contributes zero until confirmed Debit, then contributes once. An unassigned confirmed transaction contributes immediately.
8. Save a category/labels-only rule, preview/apply it, and verify merchant normalization is optional and manual category/label removals remain protected.
9. Open category/account/merchant/budget/chart drilldowns. Each uses the same ledger/editor with visible filters and totals consistent with its caller.
10. Backup, edit, merge: local conflict survives; replace: snapshot returns; wrong password changes nothing. Export current query: category/label names and links are readable, private SMS/balance/reference/fingerprint data is absent.
11. Launch the existing host with Finance unused. Its home/login/services behave as before, no finance onboarding/permission/scan runs, and application ID/branding/global navigation remain unchanged.
12. Open Finance from the host service entry, complete finance setup once, navigate internally, and return to the original host location. Re-entry/deep links preserve scope and honor host access guards.
13. Deny SMS and, where supported, enter on non-Android. Finance explains import limitations while authorized cached data and unrelated host services remain usable.
14. With two synthetic host scopes, import/edit data in A, switch to B during a scan, and verify no A records/settings/badges/caches appear in B. Follow host logout/access policy; test service disablement without unintended deletion.
15. Apply additive finance migrations to a populated host installation, then perform Replace Finance Data in A. Verify host users/settings/other services and B finance data remain unchanged; Finance exports/backups contain none of them.

## 9. Optional historical source map

The original repository is evidence for SMS extraction and baseline capabilities, not the target organization/navigation design. Its fixed-category and single-tag structures are superseded. The host's existing startup/router/native registration remains authoritative; do not replace it by copying reference `main.dart` or an entire native activity.

| Area | Original files |
| --- | --- |
| SMS/app | `lib/main.dart`; `lib/services/sms_service.dart`, `sms_reader.dart`, `sms_parser.dart`, `sms_processing_service.dart` |
| Storage/tracking | `lib/services/local_storage_service.dart` |
| Historical organization | `lib/models/standard_category.dart`, `merchant_rule_suggestion.dart`; `lib/services/category_service.dart`; `lib/screens/merchant_rules_screen.dart` |
| Planning | `lib/services/budget_service.dart`, `salary_closeout_service.dart`; `lib/screens/budget_screen.dart`, `salary_cycle_screen.dart`, `salary_month_closeout_screen.dart` |
| Selection/transfers/insights | `lib/services/transaction_window_service.dart`, `transfer_service.dart`, `emi_service.dart`, `anomaly_service.dart` |
| Data I/O | `lib/services/backup_service.dart`, `transaction_export_service.dart`; `android/app/src/main/kotlin/com/example/payment_tracker/MainActivity.kt` |
| Test evidence | `test/core_services_test.dart`, `test/widget_test.dart` |

## 10. Copy-and-paste request for the host-app agent

Attach this file to the agent working in the existing host repository. Identify the repository or desired Finance entry location if available; otherwise the agent discovers those integration points in Phase 1.

```text
Add Finance as a new service/feature module to this existing application using
the attached FEATURES.md v3 as its full specification and execution plan.
Implement every F01-F16 feature inside the host; do not create a standalone app.

Read the entire document, then implement the 14 phases in section 8 in order.
Start by inspecting host service registration, routes, identity/profile lifecycle,
database/migrations, state/DI, theme/localization, native adapters, and baseline
build/tests. State the module location and necessary host integration changes,
then begin Phase 1. Continue implementing rather than returning only a plan.

Preserve these product rules throughout:
- One host Finance entry with internal Overview, Transactions, Plan, Insights.
- Preserve host global navigation, login, identity, branding, signing, and services.
- Reuse host framework/router/state/design system; no replacement app shell.
- Scope finance data/settings/caches to the authorized host profile or device.
- Finance first-use setup and SMS permission must never block host startup.
- One nullable database-managed category per transaction.
- Multiple reusable user-managed labels; no fixed catalogs or name-based logic.
- Budgets reference category IDs; labels never double-count budget allocation.
- Trip labeling preserves categories and unrelated labels by default.
- Shared transaction queries, lists, editors, pickers, and financial calculations.
- Host-compatible local finance persistence, real Android SMS integration,
  configurable organization rules, encrypted finance backup, and JSON export.
- Finance Merge/Replace affects only the active finance scope, never host data.
- Empty categories/labels are valid; fixtures stay separate from production.

Implement and validate each phase before marking it complete. Fix failures and
keep FINANCE_IMPLEMENTATION_STATUS.md current with the integration map/baseline,
phase progress, F01-F16 coverage, changed host/module files, checks/results,
and remaining dependencies. Give a short
checkpoint report after each phase and continue without routine confirmation.
If I explicitly request one phase only or a pause, honor that instruction.

Make routine technical decisions independently and document them. Ask only for
missing information that materially changes scope. Report blocked tools/device
checks accurately and continue work that does not depend on them.

Finish all finance and host-regression acceptance scenarios, the established
host analysis/tests/Android build, and available native smoke checks. For a
Flutter host use its existing Flutter commands/flavors; for another stack use
equivalent host tooling without creating a Flutter app. Deliver module/native
integration changes, migrations/tests, integration README, completion matrix,
baseline/final validation evidence, and limitations. Do not claim placeholders
or unverified checks as completed work.
```

For a later session resuming the same build, use:

```text
Read the finance FEATURES.md and FINANCE_IMPLEMENTATION_STATUS.md in this host
repository. Inspect integration changes and recorded baseline/final checks,
identify the first incomplete phase, and resume without recreating finished
work. Preserve host behavior, scope isolation, all finance product rules, and
the implementation/verification checkpoints in section 8.
```
