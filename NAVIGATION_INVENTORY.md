# Navigation inventory

Audit baseline: local commit `3ce0c0f` (net-budget calculation update), following the RCS import and transaction-selection commits. The mapping below was recorded before editing application source. Every feature implementation remains the existing widget; only its entry point and presentation change.

## Main entry points

| Before | After | Existing destination |
|---|---|---|
| Home > Accounts | Plan > Accounts | AccountsScreen |
| Home > Breakdown (pie icon) | Insights > Spending Breakdown | SpendingBreakdownScreen |
| Home > Salary | Plan > Salary Cycles | SalaryCycleScreen |
| Home > Breakdown (category icon) | Insights > Category Breakdown | CategoryBreakdownScreen |
| Home > Budgets | Budgets bottom tab | BudgetScreen |
| Home > Heatmap | Insights > Spending Heatmap | SpendingHeatmapScreen |
| Home > Merchants | Insights > Merchant Rankings | MerchantRankingsScreen |
| Home > EMIs | Plan > EMI Tracker | EMITrackerScreen |
| Home > Categories | Plan > Categories | CategoriesScreen |
| Home > Tracking | Settings > Tracking Settings | TrackingSettingsScreen |
| Home > Ignored | Activity > Activity tools > Ignored Transactions | IgnoredTransactionsScreen |
| Home > Review | Activity > Activity tools > Review Inbox; Home needs-review shortcut | TransactionReviewScreen |
| Home > Paste payment message | Activity > Activity tools > Paste Payment Message; existing Settings entry | ImportMessageScreen |
| Home toolbar > Transfer Management | Activity > Activity tools > Transfer Management | TransferManagementScreen |
| Home toolbar/banner > Alerts | Home toolbar/banner > Alerts | AlertsScreen |
| Home toolbar > Settings | Top-right Settings icon on all five tabs | SettingsScreen |
| Home toolbar/pull-to-refresh/retry > Scan | Home toolbar/pull-to-refresh/retry > Scan | SmsService.loadTransactions |
| Home > See All with selected direction | Activity with the requested All / Money In / Money Out direction | AllTransactionsScreen |
| Home current-cycle filters / bank selection / recent rows | Home current-cycle filters / bank selection / recent rows | Existing current-cycle calculations and card handlers |
| Ignored Transactions toolbar > Ignored Messages | Same route; also Activity > Activity tools > Skipped / Ignored Messages | IgnoredMessagesScreen |

## Contextual actions and nested destinations

| Surface | Preserved actions and nested controls | Reachable through |
|---|---|---|
| All Transactions | Search; bank/category/tag/cycle chips; All/In/Out tabs; date/amount sorting; filtered credit/debit/net/internal transfer totals; long-press selection; select/deselect all; assign-category picker; category setup; date/transaction-window categorization; detail sheet; swipe ignore/undo and direction correction; transfer detail and unlink | Activity |
| Transaction detail sheet | Merchant editing and rule creation; category picker and management; note add/edit/clear; tag add/edit/clear; salary marking; debit/credit correction; ignored state; raw-message expansion; linked-transfer detail/unmerge; sheet dismissal | Home or Activity transaction row, or existing report/budget drill-down |
| Review Inbox | Refresh; choose credit/debit; ignore; top Ignore all button (restorable, with progress and retry for failed items); choose/create category; merchant-rule dialog including matching, merchant, category and tag; cancel/save | Activity > Activity tools > Review Inbox |
| Ignored Transactions | Refresh; restore; transaction details; Ignored Messages toolbar entry | Activity > Activity tools > Ignored Transactions |
| Ignored Messages | Ignored-review restore; retained payment-like skipped messages; enter amount/send to review; recheck skipped messages; refresh; tabs and explanatory counts | Activity > Activity tools > Skipped / Ignored Messages, or Ignored Transactions toolbar |
| Transfer Management | Suggestions/Merged tabs; individual merge; Merge all; dismiss and Undo; merged detail; unmerge/swipe; refresh suggestions; integrity check, report and repair dialogs | Activity > Activity tools > Transfer Management |
| Paste Payment Message | Explicit clipboard paste; editable sender/body; original date and time pickers; preview; save; duplicate status; import another; Back | Activity > Activity tools > Paste Payment Message; Settings original entry |
| Spending Breakdown | Period selector; account/source summary and chart; expandable account cards; account transaction sheet; transaction details | Insights > Spending Breakdown |
| Category Breakdown | Period selector; pie chart; category list; category transaction sheet and details | Insights > Category Breakdown |
| Spending Heatmap | Search; All/Money In/Money Out; multi-bank/category/tag chips; salary-cycle intersection; optional internal transfers; Reset and refresh; previous/next month; filtered calendar colors, statistics and day transaction sheet | Insights > Spending Heatmap |
| Merchant Rankings | Period selector; ranking chart and merchant list | Insights > Merchant Rankings |
| Accounts | Add/edit account dialogs; account type/name/bank/last-four fields; save/cancel; delete confirmation; grouped account list | Plan > Accounts |
| Salary Cycles | Candidate salary marking/unmarking; generation/regeneration; salary-day picker; setup guidance; cycle detail and credit/debit transaction lists; transaction detail; salary-month closeout | Plan > Salary Cycles |
| Salary Month Closeout | Cycle picker; monthly closeout summary and transaction/category sections | Plan > Salary Cycles > closeout |
| Budgets | Period chips; income dialog; spending suggestions and apply; add/edit/delete budget; category creation; per-category transaction sheet; debit/credit/net and remaining; Outside Budgets | Budgets bottom tab |
| Outside Budgets | Selected period/all-time selector; search; signed transaction amounts; category assignment sheet; category management; details; return refresh | Budgets > Outside your budgets |
| EMI Tracker | Existing recurring-payment summary, empty state and EMI cards/details | Plan > EMI Tracker |
| Categories | Add/edit sheet; name, emoji, color; create/save/cancel; delete confirmation; keyboard-safe scrolling | Plan > Categories, plus all existing category-management entry points |
| Transaction Window Category | Date range vs boundary-transaction modes; date picker; boundary search; preview; category setup; tag entry; apply confirmation; cancel/save | Activity > Activity tools > Categorize a date or transaction window (original toolbar action retained in standalone All Transactions routes) |
| Tracking Settings | Date or boundary transaction picker; save; clear/reset; explanatory start-point controls; Back | Settings > Tracking Settings |
| Settings | Original paste entry; encrypted backup/password/share; restore file/password and merge/replace choice; replacement confirmation; JSON export scopes/date range/salary cycle/share; cache stats; skipped-message recheck; merchant rules and matching preview; supported senders | Any primary tab > Settings; existing entries retained |
| Merchant Rules | Add/edit rule sheet; match text, merchant, category and tag; category creation; enabled switch; delete; preview/apply existing transactions and confirmations | Settings > Merchant cleanup rules |
| Alerts | Actual unread badge; tabs; refresh/generate; mark-read and existing alert-card actions; return badge refresh | Home toolbar or unread-alert banner |
| Startup and permission states | Tracking onboarding choices; existing SMS permission request; initial scan/loading/retry; newly-found transaction confirmation, individual ignore, Ignore All and confirm | Home mounted once inside the shell |

## Navigation and lifecycle contracts

- Exactly five primary destinations: Home, Activity, Budgets, Insights and Plan. Budgets has moved out of Plan into its own retained tab. The shell retains visited tabs with IndexedStack and uses the existing root Navigator for detail screens. There are no additional Providers or nested Navigators.
- Home remains the sole owner of startup onboarding, SMS permission/scan and newly-found review. Tab selection never invokes a scan. Home direction, sender and scroll state survive switching.
- Activity retains the existing AllTransactionsScreen state. Home See All requests the selected direction on that same Activity instance. Search, filters, sorting and selection are retained on normal tab switches.
- Salary Cycles and Review Inbox retain reloadFromCache on return. Settings retains loadTransactions on return. Existing screen-local update and restore callbacks stay in their original widgets.
- Android Back dismisses an active child route or Activity selection first, returns a primary non-Home tab to Home next, and permits normal exit from Home. Hidden Activity selection cannot intercept another tab's Back.
- Primary tabs keep their bottom bar; existing child routes open above the shell with a normal Back route. The bar temporarily hides while the keyboard is open, so the feature Scaffold handles keyboard insets once.
- Current-cycle summary values continue to come directly from SmsService.currentCycleCredits, currentCycleDebits, currentCycleTransactions, currentCycleLabel and currentCycleSubtitle.
- Database/schema, repository/storage, models, parser, SMS permissions, backups and domain calculations are outside the edit scope.

## Baseline control index

The following index records every callback binding and dialog/sheet/search entry found in the audited screen widgets and transaction/onboarding support widgets. For unchanged feature files, these exact controls remain in their existing implementation under the entry point mapped above. Home links are relocated according to the main-entry table. Line numbers refer to the baseline source, not the refactored files.

| Baseline source | Control or entry | Source binding |
|---|---|---|
| `lib/screens/accounts_screen.dart:53` | onPressed | `onPressed: () => _loadAccounts(detectNew: true),` |
| `lib/screens/accounts_screen.dart:64` | onPressed | `onPressed: () => _showAddAccountDialog(),` |
| `lib/screens/accounts_screen.dart:173` | onSelected | `onSelected: (value) async {` |
| `lib/screens/accounts_screen.dart:236` | showDialog | `final confirm = await showDialog<bool>(` |
| `lib/screens/accounts_screen.dart:243` | onPressed | `onPressed: () => Navigator.pop(context, false),` |
| `lib/screens/accounts_screen.dart:247` | onPressed | `onPressed: () => Navigator.pop(context, true),` |
| `lib/screens/accounts_screen.dart:271` | showDialog | `final result = await showDialog<Account>(` |
| `lib/screens/accounts_screen.dart:292` | showDialog | `final result = await showDialog<Account>(` |
| `lib/screens/accounts_screen.dart:373` | onChanged | `onChanged: (value) {` |
| `lib/screens/accounts_screen.dart:400` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/accounts_screen.dart:403` | onPressed | `FilledButton(onPressed: _save, child: Text(isEditing ? 'Save' : 'Add')),` |
| `lib/screens/alerts_screen.dart:152` | onPressed | `onPressed: _refreshAlerts,` |
| `lib/screens/alerts_screen.dart:155` | onSelected | `onSelected: (value) async {` |
| `lib/screens/alerts_screen.dart:250` | onPressed | `onPressed: _refreshAlerts,` |
| `lib/screens/alerts_screen.dart:286` | onTap | `onTap: () async {` |
| `lib/screens/all_transactions_screen.dart:73` | showModalBottomSheet | `final categoryId = await showModalBottomSheet<String>(` |
| `lib/screens/all_transactions_screen.dart:169` | onPressed | `onPressed: () async {` |
| `lib/screens/all_transactions_screen.dart:192` | showModalBottomSheet | `await showModalBottomSheet<void>(` |
| `lib/screens/all_transactions_screen.dart:205` | onTap | `onTap: () => TransactionDetailSheet.show(` |
| `lib/screens/all_transactions_screen.dart:212` | onTap | `onTap: () => TransactionDetailSheet.show(` |
| `lib/screens/all_transactions_screen.dart:218` | onPressed | `onPressed: () async {` |
| `lib/screens/all_transactions_screen.dart:329` | onPopInvokedWithResult | `onPopInvokedWithResult: (didPop, result) {` |
| `lib/screens/all_transactions_screen.dart:337` | onPressed | `onPressed: _assigningCategory ? null : _exitSelection,` |
| `lib/screens/all_transactions_screen.dart:350` | onPressed | `onPressed: () async {` |
| `lib/screens/all_transactions_screen.dart:367` | onPressed | `onPressed: () => Navigator.push(` |
| `lib/screens/all_transactions_screen.dart:385` | onSelected | `onSelected: (value) => setState(() => _sort = value),` |
| `lib/screens/all_transactions_screen.dart:420` | onPressed | `onPressed: _assigningCategory &#124;&#124; visibleIds.isEmpty` |
| `lib/screens/all_transactions_screen.dart:438` | onPressed | `onPressed: _assigningCategory &#124;&#124; _selectedIds.isEmpty` |
| `lib/screens/all_transactions_screen.dart:466` | onChanged | `onChanged: (value) =>` |
| `lib/screens/all_transactions_screen.dart:510` | onSelected | `onSelected: (_) => setState(() => _cycleId = null),` |
| `lib/screens/all_transactions_screen.dart:527` | onSelected | `onSelected: (_) => setState(` |
| `lib/screens/all_transactions_screen.dart:581` | onPressed | `onPressed: transactions.isEmpty &#124;&#124; _selecting` |
| `lib/screens/all_transactions_screen.dart:710` | onSelected | `onSelected: (_) => setState(selected.clear),` |
| `lib/screens/all_transactions_screen.dart:720` | onSelected | `onSelected: (value) => setState(() {` |
| `lib/screens/all_transactions_screen.dart:811` | onSourceSelected | `onSourceSelected: (value) =>` |
| `lib/screens/all_transactions_screen.dart:813` | onDestinationSelected | `onDestinationSelected: (value) =>` |
| `lib/screens/all_transactions_screen.dart:815` | onLongPress | `onLongPress: () => _startSelection([` |
| `lib/screens/all_transactions_screen.dart:819` | onTap | `onTap: _selecting` |
| `lib/screens/all_transactions_screen.dart:834` | onSelected | `onSelected: (value) => _setSelected([tx.id], value),` |
| `lib/screens/all_transactions_screen.dart:835` | onLongPress | `onLongPress: () => _startSelection([tx.id]),` |
| `lib/screens/all_transactions_screen.dart:840` | onTap | `onTap: () => TransactionDetailSheet.show(context, tx),` |
| `lib/screens/all_transactions_screen.dart:841` | onSwipeIgnore | `onSwipeIgnore: (tx) => _edit(tx, ignore: true),` |
| `lib/screens/all_transactions_screen.dart:842` | onSwipeToggleType | `onSwipeToggleType: _edit,` |
| `lib/screens/all_transactions_screen.dart:891` | onTap | `onTap: () => Navigator.pop(context, category.id),` |
| `lib/screens/all_transactions_screen.dart:897` | onPressed | `onPressed: () => Navigator.push(` |
| `lib/screens/all_transactions_screen.dart:905` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/budget_screen.dart:145` | onPressed | `onPressed: _showSuggestions,` |
| `lib/screens/budget_screen.dart:152` | onRefresh | `onRefresh: _loadData,` |
| `lib/screens/budget_screen.dart:168` | onPressed | `onPressed: _showAddBudgetDialog,` |
| `lib/screens/budget_screen.dart:179` | onTap | `onTap: _setMonthlyIncome,` |
| `lib/screens/budget_screen.dart:241` | onSelected | `onSelected: (_) => _selectPeriod(period),` |
| `lib/screens/budget_screen.dart:391` | onPressed | `onPressed: _showSuggestions,` |
| `lib/screens/budget_screen.dart:446` | onPressed | `onPressed: _showOutsideBudgetTransactions,` |
| `lib/screens/budget_screen.dart:483` | onTap | `onTap: () => _showCategoryTransactions(status),` |
| `lib/screens/budget_screen.dart:510` | onSelected | `onSelected: (value) async {` |
| `lib/screens/budget_screen.dart:591` | showModalBottomSheet | `await showModalBottomSheet<void>(` |
| `lib/screens/budget_screen.dart:604` | showDialog | `final result = await showDialog<double>(` |
| `lib/screens/budget_screen.dart:619` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/budget_screen.dart:623` | onPressed | `onPressed: () {` |
| `lib/screens/budget_screen.dart:656` | showDialog | `final accepted = await showDialog<bool>(` |
| `lib/screens/budget_screen.dart:695` | onPressed | `onPressed: () => Navigator.pop(context, false),` |
| `lib/screens/budget_screen.dart:699` | onPressed | `onPressed: () => Navigator.pop(context, true),` |
| `lib/screens/budget_screen.dart:777` | showDialog | `final result = await showDialog<Budget>(` |
| `lib/screens/budget_screen.dart:796` | onChanged | `onChanged: (value) {` |
| `lib/screens/budget_screen.dart:816` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/budget_screen.dart:820` | onPressed | `onPressed: () {` |
| `lib/screens/budget_screen.dart:1039` | onPressed | `onPressed: () => Navigator.of(context).pop(),` |
| `lib/screens/budget_screen.dart:1146` | onTap | `onTap: () => TransactionDetailSheet.show(context, tx),` |
| `lib/screens/categories_screen.dart:159` | onPressed | `onPressed: () => _showEditor(context),` |
| `lib/screens/categories_screen.dart:167` | onPressed | `child: TextButton(onPressed: _load, child: Text(_error!)),` |
| `lib/screens/categories_screen.dart:186` | onPressed | `onPressed: () => _showEditor(context),` |
| `lib/screens/categories_screen.dart:201` | onEdit | `onEdit: () => _showEditor(context, existing: cat),` |
| `lib/screens/categories_screen.dart:202` | onDelete | `onDelete: () => _delete(cat),` |
| `lib/screens/categories_screen.dart:209` | onPressed | `onPressed: () => _showEditor(context),` |
| `lib/screens/categories_screen.dart:217` | showDialog | `final confirmed = await showDialog<bool>(` |
| `lib/screens/categories_screen.dart:226` | onPressed | `onPressed: () => Navigator.pop(ctx, false),` |
| `lib/screens/categories_screen.dart:230` | onPressed | `onPressed: () => Navigator.pop(ctx, true),` |
| `lib/screens/categories_screen.dart:247` | showModalBottomSheet | `final result = await showModalBottomSheet<AppCategory>(` |
| `lib/screens/categories_screen.dart:301` | onPressed | `onPressed: onEdit,` |
| `lib/screens/categories_screen.dart:309` | onPressed | `onPressed: onDelete,` |
| `lib/screens/categories_screen.dart:420` | onTap | `onTap: () => setState(() => _selectedEmoji = e),` |
| `lib/screens/categories_screen.dart:453` | onTap | `onTap: () => setState(() => _selectedColorValue = c.toARGB32()),` |
| `lib/screens/categories_screen.dart:481` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/categories_screen.dart:488` | onPressed | `onPressed: () {` |
| `lib/screens/category_breakdown_screen.dart:121` | onSelected | `onSelected: (_) {` |
| `lib/screens/category_breakdown_screen.dart:139` | touchCallback | `touchCallback: (event, response) {` |
| `lib/screens/category_breakdown_screen.dart:233` | onTap | `onTap: () => _showCategoryTransactions(cat),` |
| `lib/screens/category_breakdown_screen.dart:244` | showModalBottomSheet | `showModalBottomSheet(` |
| `lib/screens/category_breakdown_screen.dart:271` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/emi_tracker_screen.dart:45` | onRefresh | `onRefresh: _loadData,` |
| `lib/screens/home_screen.dart:65` | onDone | `onDone: () {` |
| `lib/screens/home_screen.dart:113` | onRetry | `onRetry: () => sms.loadTransactions(),` |
| `lib/screens/home_screen.dart:121` | onRefresh | `onRefresh: () => sms.loadTransactions(),` |
| `lib/screens/home_screen.dart:131` | onPressed | `onPressed: () => sms.loadTransactions(),` |
| `lib/screens/home_screen.dart:175` | onPressed | `onPressed: () => Navigator.push(` |
| `lib/screens/home_screen.dart:197` | onTap | `onTap: () =>` |
| `lib/screens/home_screen.dart:199` | onSwipeIgnore | `onSwipeIgnore: (tx) => _handleSwipeIgnore(context, tx),` |
| `lib/screens/home_screen.dart:200` | onSwipeToggleType | `onSwipeToggleType: (tx) =>` |
| `lib/screens/home_screen.dart:227` | onPressed | `onPressed: () => context.read<SmsService>().loadTransactions(),` |
| `lib/screens/home_screen.dart:233` | onPressed | `onPressed: () async {` |
| `lib/screens/home_screen.dart:266` | onPressed | `onPressed: () {` |
| `lib/screens/home_screen.dart:277` | onPressed | `onPressed: () async {` |
| `lib/screens/home_screen.dart:305` | onTap | `onTap: () => Navigator.push(` |
| `lib/screens/home_screen.dart:315` | onTap | `onTap: () => Navigator.push(` |
| `lib/screens/home_screen.dart:327` | onTap | `onTap: () async {` |
| `lib/screens/home_screen.dart:344` | onTap | `onTap: () => Navigator.push(` |
| `lib/screens/home_screen.dart:361` | onTap | `onTap: () => Navigator.push(` |
| `lib/screens/home_screen.dart:371` | onTap | `onTap: () => Navigator.push(` |
| `lib/screens/home_screen.dart:383` | onTap | `onTap: () => Navigator.push(` |
| `lib/screens/home_screen.dart:395` | onTap | `onTap: () => Navigator.push(` |
| `lib/screens/home_screen.dart:410` | onTap | `onTap: () => Navigator.push(` |
| `lib/screens/home_screen.dart:420` | onTap | `onTap: () => Navigator.push(` |
| `lib/screens/home_screen.dart:432` | onTap | `onTap: () => Navigator.push(` |
| `lib/screens/home_screen.dart:444` | onTap | `onTap: () async {` |
| `lib/screens/home_screen.dart:462` | onPressed | `onPressed: () => Navigator.push(` |
| `lib/screens/home_screen.dart:475` | onTap | `onTap: () async {` |
| `lib/screens/home_screen.dart:556` | onSelected | `onSelected: (_) => setState(() => _selectedFilter = i),` |
| `lib/screens/home_screen.dart:575` | onSelected | `onSelected: (_) => setState(() => _selectedBank = null),` |
| `lib/screens/home_screen.dart:589` | onSelected | `onSelected: (_) => setState(() {` |
| `lib/screens/home_screen.dart:635` | onPressed | `onPressed: () async {` |
| `lib/screens/home_screen.dart:666` | onPressed | `onPressed: () async {` |
| `lib/screens/home_screen.dart:709` | onPressed | `onPressed: onRetry,` |
| `lib/screens/home_screen.dart:737` | onTap | `onTap: onTap,` |
| `lib/screens/ignored_messages_screen.dart:77` | showDialog | `final amount = await showDialog<double>(` |
| `lib/screens/ignored_messages_screen.dart:105` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/ignored_messages_screen.dart:109` | onPressed | `onPressed: () {` |
| `lib/screens/ignored_messages_screen.dart:191` | onPressed | `onPressed: () => _restore(review),` |
| `lib/screens/ignored_messages_screen.dart:216` | onPressed | `onPressed: _recheckSkipped,` |
| `lib/screens/ignored_messages_screen.dart:247` | onPressed | `onPressed:` |
| `lib/screens/ignored_messages_screen.dart:270` | onRefresh | `onRefresh: () async {` |
| `lib/screens/ignored_transactions_screen.dart:81` | onPressed | `onPressed: () => Navigator.push(` |
| `lib/screens/ignored_transactions_screen.dart:110` | onRefresh | `onRefresh: () async {` |
| `lib/screens/ignored_transactions_screen.dart:139` | onRefresh | `onRefresh: () async {` |
| `lib/screens/ignored_transactions_screen.dart:162` | onTap | `onTap: () => TransactionDetailSheet.show(` |
| `lib/screens/ignored_transactions_screen.dart:165` | onUpdated | `onUpdated: (_) => setState(_reload),` |
| `lib/screens/ignored_transactions_screen.dart:171` | onPressed | `onPressed: () => _restoreTransaction(tx),` |
| `lib/screens/import_message_screen.dart:72` | showDatePicker | `final selected = await showDatePicker(` |
| `lib/screens/import_message_screen.dart:88` | showTimePicker | `final selected = await showTimePicker(` |
| `lib/screens/import_message_screen.dart:225` | onPressed | `onPressed: _paste,` |
| `lib/screens/import_message_screen.dart:240` | onTap | `onTap: _saved ? null : _chooseDate,` |
| `lib/screens/import_message_screen.dart:252` | onTap | `onTap: _saved ? null : _chooseTime,` |
| `lib/screens/import_message_screen.dart:271` | onPressed | `onPressed: _parse,` |
| `lib/screens/import_message_screen.dart:308` | onPressed | `onPressed: _save,` |
| `lib/screens/import_message_screen.dart:320` | onPressed | `onPressed: _another,` |
| `lib/screens/merchant_rankings_screen.dart:93` | onSelectionChanged | `onSelectionChanged: (s) {` |
| `lib/screens/merchant_rules_screen.dart:60` | showModalBottomSheet | `final rule = await showModalBottomSheet<MerchantRule>(` |
| `lib/screens/merchant_rules_screen.dart:84` | showDialog | `final confirmed = await showDialog<bool>(` |
| `lib/screens/merchant_rules_screen.dart:100` | onPressed | `onPressed: () => Navigator.pop(context, false),` |
| `lib/screens/merchant_rules_screen.dart:104` | onPressed | `onPressed: count == 0 ? null : () => Navigator.pop(context, true),` |
| `lib/screens/merchant_rules_screen.dart:152` | showDialog | `final confirmed = await showDialog<bool>(` |
| `lib/screens/merchant_rules_screen.dart:161` | onPressed | `onPressed: () => Navigator.pop(context, false),` |
| `lib/screens/merchant_rules_screen.dart:165` | onPressed | `onPressed: () => Navigator.pop(context, true),` |
| `lib/screens/merchant_rules_screen.dart:192` | onPressed | `onPressed: () async {` |
| `lib/screens/merchant_rules_screen.dart:205` | onRetry | `? _LoadError(message: _loadError!, onRetry: _load)` |
| `lib/screens/merchant_rules_screen.dart:234` | onChanged | `onChanged: _isBusy` |
| `lib/screens/merchant_rules_screen.dart:245` | onPressed | `onPressed: _isBusy` |
| `lib/screens/merchant_rules_screen.dart:251` | onPressed | `onPressed: _isBusy ? null : () => _delete(rule),` |
| `lib/screens/merchant_rules_screen.dart:255` | onPressed | `onPressed: !rule.isEnabled &#124;&#124; _isBusy` |
| `lib/screens/merchant_rules_screen.dart:269` | onPressed | `onPressed: _isBusy ? null : () => _showEditor(),` |
| `lib/screens/merchant_rules_screen.dart:292` | onPressed | `OutlinedButton(onPressed: onRetry, child: const Text('Retry')),` |
| `lib/screens/merchant_rules_screen.dart:422` | onChanged | `onChanged: (value) => setState(() => _categoryId = value ?? ''),` |
| `lib/screens/merchant_rules_screen.dart:443` | onPressed | `onPressed: _save,` |
| `lib/screens/outside_budget_transactions_screen.dart:100` | showModalBottomSheet | `final selectedId = await showModalBottomSheet<String>(` |
| `lib/screens/outside_budget_transactions_screen.dart:122` | onTap | `onTap: () => Navigator.pop(sheetContext, '__manage'),` |
| `lib/screens/outside_budget_transactions_screen.dart:126` | onTap | `onTap: () => Navigator.pop(sheetContext, ''),` |
| `lib/screens/outside_budget_transactions_screen.dart:138` | onTap | `onTap: () => Navigator.pop(sheetContext, category.id),` |
| `lib/screens/outside_budget_transactions_screen.dart:157` | onTap | `onTap: () => Navigator.pop(sheetContext, category.id),` |
| `lib/screens/outside_budget_transactions_screen.dart:244` | onSelectionChanged | `onSelectionChanged: (values) =>` |
| `lib/screens/outside_budget_transactions_screen.dart:268` | onChanged | `onChanged: (value) => setState(() => _search = value),` |
| `lib/screens/outside_budget_transactions_screen.dart:310` | onTap | `onTap: () => TransactionDetailSheet.show(` |
| `lib/screens/outside_budget_transactions_screen.dart:313` | onUpdated | `onUpdated: (_) => _load(),` |
| `lib/screens/outside_budget_transactions_screen.dart:319` | onPressed | `onPressed: _saving` |
| `lib/screens/salary_cycle_screen.dart:71` | onPressed | `onPressed: () => Navigator.push(` |
| `lib/screens/salary_cycle_screen.dart:82` | onPressed | `onPressed: _regenerateCycles,` |
| `lib/screens/salary_cycle_screen.dart:99` | onRefresh | `onRefresh: _loadData,` |
| `lib/screens/salary_cycle_screen.dart:112` | onPressed | `onPressed: () => setState(` |
| `lib/screens/salary_cycle_screen.dart:165` | onPressed | `onPressed: _loadData,` |
| `lib/screens/salary_cycle_screen.dart:209` | onPressed | `onPressed: _generateCyclesFromMarked,` |
| `lib/screens/salary_cycle_screen.dart:305` | onTap | `onTap: () => _toggleSalaryMark(tx),` |
| `lib/screens/salary_cycle_screen.dart:318` | onTap | `onTap: () => _showCycleDetails(cycle),` |
| `lib/screens/salary_cycle_screen.dart:473` | onPressed | `onPressed: () async {` |
| `lib/screens/salary_cycle_screen.dart:480` | onPressed | `onPressed: _showSalaryCycleDayPicker,` |
| `lib/screens/salary_cycle_screen.dart:491` | showDialog | `final result = await showDialog<int>(` |
| `lib/screens/salary_cycle_screen.dart:515` | onSelectedItemChanged | `onSelectedItemChanged: (index) {` |
| `lib/screens/salary_cycle_screen.dart:545` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/salary_cycle_screen.dart:549` | onPressed | `onPressed: () => Navigator.pop(context, selected),` |
| `lib/screens/salary_cycle_screen.dart:611` | showDialog | `final confirm = await showDialog<bool>(` |
| `lib/screens/salary_cycle_screen.dart:620` | onPressed | `onPressed: () => Navigator.pop(context, false),` |
| `lib/screens/salary_cycle_screen.dart:624` | onPressed | `onPressed: () => Navigator.pop(context, true),` |
| `lib/screens/salary_cycle_screen.dart:637` | showModalBottomSheet | `showModalBottomSheet(` |
| `lib/screens/salary_month_closeout_screen.dart:78` | showDialog | `final cycle = await showDialog<SalaryCycle>(` |
| `lib/screens/salary_month_closeout_screen.dart:85` | onPressed | `onPressed: () => Navigator.pop(context, cycle),` |
| `lib/screens/salary_month_closeout_screen.dart:114` | onRetry | `? _CloseoutMessage(message: _error!, onRetry: _load)` |
| `lib/screens/salary_month_closeout_screen.dart:135` | onPressed | `onPressed: _chooseCycle,` |
| `lib/screens/salary_month_closeout_screen.dart:375` | onPressed | `OutlinedButton(onPressed: onRetry, child: const Text('Retry')),` |
| `lib/screens/settings_screen.dart:69` | onTap | `onTap: () async {` |
| `lib/screens/settings_screen.dart:109` | onTap | `onTap: _refreshRuleCategories,` |
| `lib/screens/settings_screen.dart:132` | onPressed | `onPressed: () => Navigator.push(` |
| `lib/screens/settings_screen.dart:167` | onPressed | `onPressed: _isBackingUp &#124;&#124; _isRestoring` |
| `lib/screens/settings_screen.dart:190` | onPressed | `onPressed: _isBackingUp &#124;&#124; _isRestoring` |
| `lib/screens/settings_screen.dart:235` | onPressed | `onPressed: _isExporting` |
| `lib/screens/settings_screen.dart:282` | onPressed | `onPressed: _recheckSkippedMessages,` |
| `lib/screens/settings_screen.dart:348` | showDialog | `final confirmed = await showDialog<bool>(` |
| `lib/screens/settings_screen.dart:375` | onPressed | `onPressed: () => Navigator.pop(context, false),` |
| `lib/screens/settings_screen.dart:379` | onPressed | `onPressed: () => Navigator.pop(context, true),` |
| `lib/screens/settings_screen.dart:405` | showDialog | `final confirmed = await showDialog<bool>(` |
| `lib/screens/settings_screen.dart:416` | onPressed | `onPressed: () => Navigator.pop(context, false),` |
| `lib/screens/settings_screen.dart:420` | onPressed | `onPressed: () => Navigator.pop(context, true),` |
| `lib/screens/settings_screen.dart:531` | showDialog | `final password = await showDialog<String>(` |
| `lib/screens/settings_screen.dart:572` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/settings_screen.dart:576` | onPressed | `onPressed: () {` |
| `lib/screens/settings_screen.dart:604` | showDialog | `return showDialog<BackupRestoreMode>(` |
| `lib/screens/settings_screen.dart:629` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/settings_screen.dart:633` | onPressed | `onPressed: () => Navigator.pop(context, BackupRestoreMode.merge),` |
| `lib/screens/settings_screen.dart:637` | onPressed | `onPressed: () => Navigator.pop(context, BackupRestoreMode.replace),` |
| `lib/screens/settings_screen.dart:647` | showDialog | `return await showDialog<bool>(` |
| `lib/screens/settings_screen.dart:657` | onPressed | `onPressed: () => Navigator.pop(context, false),` |
| `lib/screens/settings_screen.dart:661` | onPressed | `onPressed: () => Navigator.pop(context, true),` |
| `lib/screens/settings_screen.dart:682` | showDialog | `final scope = await showDialog<_ExportScope>(` |
| `lib/screens/settings_screen.dart:688` | onPressed | `onPressed: () => Navigator.pop(context, _ExportScope.allActive),` |
| `lib/screens/settings_screen.dart:696` | onPressed | `onPressed: () => Navigator.pop(context, _ExportScope.dateRange),` |
| `lib/screens/settings_screen.dart:704` | onPressed | `onPressed: () => Navigator.pop(context, _ExportScope.salaryCycle),` |
| `lib/screens/settings_screen.dart:729` | showDateRangePicker | `final range = await showDateRangePicker(` |
| `lib/screens/settings_screen.dart:772` | showDialog | `final cycle = await showDialog<SalaryCycle>(` |
| `lib/screens/settings_screen.dart:779` | onPressed | `onPressed: () => Navigator.pop(context, cycle),` |
| `lib/screens/spending_breakdown_screen.dart:135` | onSelected | `onSelected: (_) {` |
| `lib/screens/spending_breakdown_screen.dart:221` | onTap | `onTap: () => _showAccountTransactions(stat),` |
| `lib/screens/spending_breakdown_screen.dart:327` | showModalBottomSheet | `showModalBottomSheet(` |
| `lib/screens/spending_breakdown_screen.dart:371` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/spending_heatmap_screen.dart:103` | onPressed | `onPressed: () {` |
| `lib/screens/spending_heatmap_screen.dart:119` | onPressed | `onPressed: () {` |
| `lib/screens/spending_heatmap_screen.dart:220` | onTap | `onTap: () => _showDayDetail(day, amount),` |
| `lib/screens/spending_heatmap_screen.dart:310` | showModalBottomSheet | `showModalBottomSheet(` |
| `lib/screens/tracking_settings_screen.dart:96` | showDatePicker | `final picked = await showDatePicker(` |
| `lib/screens/tracking_settings_screen.dart:113` | showModalBottomSheet | `final selected = await showModalBottomSheet<Transaction>(` |
| `lib/screens/tracking_settings_screen.dart:143` | onPressed | `TextButton(onPressed: _clearAll, child: const Text('Clear')),` |
| `lib/screens/tracking_settings_screen.dart:258` | onPressed | `onPressed: _pickDate,` |
| `lib/screens/tracking_settings_screen.dart:292` | onPressed | `onPressed: _pickTransaction,` |
| `lib/screens/tracking_settings_screen.dart:312` | onPressed | `onPressed: _save,` |
| `lib/screens/tracking_settings_screen.dart:381` | onChanged | `onChanged: (v) => setState(() => _query = v),` |
| `lib/screens/tracking_settings_screen.dart:433` | onTap | `onTap: () => Navigator.pop(context, tx),` |
| `lib/screens/transaction_review_screen.dart:121` | showModalBottomSheet | `final selected = await showModalBottomSheet<String>(` |
| `lib/screens/transaction_review_screen.dart:129` | onTap | `onTap: () => Navigator.pop(sheetContext, ''),` |
| `lib/screens/transaction_review_screen.dart:135` | onTap | `onTap: () => Navigator.pop(sheetContext, category.id),` |
| `lib/screens/transaction_review_screen.dart:141` | onTap | `onTap: () => Navigator.pop(sheetContext, '__manage'),` |
| `lib/screens/transaction_review_screen.dart:234` | showDialog | `final result = await showDialog<_MerchantRuleDraft>(` |
| `lib/screens/transaction_review_screen.dart:274` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/screens/transaction_review_screen.dart:278` | onPressed | `onPressed: () {` |
| `lib/screens/transaction_review_screen.dart:328` | onPressed | `onPressed: _isLoading ? null : _load,` |
| `lib/screens/transaction_review_screen.dart:340` | onRefresh | `onRefresh: _load,` |
| `lib/screens/transaction_review_screen.dart:353` | onIgnore | `onIgnore: () => _ignore(review),` |
| `lib/screens/transaction_review_screen.dart:354` | onDebit | `onDebit: () => _resolve(review, TransactionType.debit),` |
| `lib/screens/transaction_review_screen.dart:355` | onCredit | `onCredit: () => _resolve(review, TransactionType.credit),` |
| `lib/screens/transaction_review_screen.dart:356` | onCategory | `onCategory: () => _chooseCategory(review),` |
| `lib/screens/transaction_review_screen.dart:357` | onSaveMerchantRule | `onSaveMerchantRule: () => _saveMerchantRule(review),` |
| `lib/screens/transaction_review_screen.dart:443` | onPressed | `onPressed: isSaving ? null : onIgnore,` |
| `lib/screens/transaction_review_screen.dart:448` | onPressed | `onPressed: isSaving ? null : onDebit,` |
| `lib/screens/transaction_review_screen.dart:453` | onPressed | `onPressed: isSaving ? null : onCredit,` |
| `lib/screens/transaction_review_screen.dart:458` | onPressed | `onPressed: isSaving ? null : onCategory,` |
| `lib/screens/transaction_review_screen.dart:463` | onPressed | `onPressed: isSaving ? null : onSaveMerchantRule,` |
| `lib/screens/transaction_window_category_screen.dart:88` | showDateRangePicker | `final range = await showDateRangePicker(` |
| `lib/screens/transaction_window_category_screen.dart:99` | showSearch | `final selected = await showSearch<Transaction?>(` |
| `lib/screens/transaction_window_category_screen.dart:134` | showDialog | `final confirmed = await showDialog<bool>(` |
| `lib/screens/transaction_window_category_screen.dart:147` | onPressed | `onPressed: () => Navigator.pop(dialogContext, false),` |
| `lib/screens/transaction_window_category_screen.dart:151` | onPressed | `onPressed: () => Navigator.pop(dialogContext, true),` |
| `lib/screens/transaction_window_category_screen.dart:213` | onSelectionChanged | `onSelectionChanged: (values) =>` |
| `lib/screens/transaction_window_category_screen.dart:229` | onTap | `onTap: _chooseDates,` |
| `lib/screens/transaction_window_category_screen.dart:243` | onTap | `onTap: () => _chooseTransaction(first: true),` |
| `lib/screens/transaction_window_category_screen.dart:256` | onTap | `onTap: () => _chooseTransaction(first: false),` |
| `lib/screens/transaction_window_category_screen.dart:324` | onChanged | `onChanged: (value) => setState(() => _categoryId = value),` |
| `lib/screens/transaction_window_category_screen.dart:329` | onPressed | `onPressed: _manageCategories,` |
| `lib/screens/transaction_window_category_screen.dart:345` | onChanged | `onChanged: (_) => setState(() {}),` |
| `lib/screens/transaction_window_category_screen.dart:349` | onPressed | `onPressed:` |
| `lib/screens/transaction_window_category_screen.dart:381` | onPressed | `IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),` |
| `lib/screens/transaction_window_category_screen.dart:386` | onPressed | `onPressed: () => close(context, null),` |
| `lib/screens/transaction_window_category_screen.dart:426` | onTap | `onTap: () => close(context, tx),` |
| `lib/screens/transfer_management_screen.dart:88` | onSelected | `onSelected: (value) async {` |
| `lib/screens/transfer_management_screen.dart:184` | onPressed | `onPressed: () => _mergeTransfers(List.of(_potentialTransfers)),` |
| `lib/screens/transfer_management_screen.dart:205` | onMerge | `onMerge: () => _mergeTransfers([transferPair]),` |
| `lib/screens/transfer_management_screen.dart:206` | onDismiss | `onDismiss: () => _handleDismissSuggestion(index),` |
| `lib/screens/transfer_management_screen.dart:251` | onTap | `onTap: () => _showMergedTransferDetail(mergedTransfer),` |
| `lib/screens/transfer_management_screen.dart:252` | onSwipeUnmerge | `onSwipeUnmerge: (mt) => _handleUnmergeTransfer(mt),` |
| `lib/screens/transfer_management_screen.dart:308` | onPressed | `onPressed: () {` |
| `lib/screens/transfer_management_screen.dart:347` | showModalBottomSheet | `showModalBottomSheet(` |
| `lib/screens/transfer_management_screen.dart:360` | showDialog | `showDialog(` |
| `lib/screens/transfer_management_screen.dart:393` | showDialog | `final shouldFix = await showDialog<bool>(` |
| `lib/screens/transfer_management_screen.dart:452` | onPressed | `onPressed: () => Navigator.of(context).pop(false),` |
| `lib/screens/transfer_management_screen.dart:458` | onPressed | `onPressed: () => Navigator.of(context).pop(true),` |
| `lib/screens/transfer_management_screen.dart:487` | showDialog | `showDialog(` |
| `lib/screens/transfer_management_screen.dart:647` | onPressed | `onPressed: () async {` |
| `lib/screens/transfer_management_screen.dart:671` | onPressed | `onPressed: () => Navigator.of(context).pop(),` |
| `lib/widgets/merged_transfer_card.dart:54` | onTap | `onTap: onTap,` |
| `lib/widgets/merged_transfer_card.dart:55` | onLongPress | `onLongPress: onLongPress,` |
| `lib/widgets/merged_transfer_card.dart:79` | onChanged | `onChanged: (value) =>` |
| `lib/widgets/merged_transfer_card.dart:93` | onChanged | `onChanged: (value) =>` |
| `lib/widgets/merged_transfer_card.dart:421` | onPressed | `onPressed: onDismiss,` |
| `lib/widgets/merged_transfer_card.dart:426` | onPressed | `onPressed: onMerge,` |
| `lib/widgets/new_transactions_review_sheet.dart:27` | showModalBottomSheet | `return showModalBottomSheet(` |
| `lib/widgets/new_transactions_review_sheet.dart:35` | onDone | `onDone: onDone,` |
| `lib/widgets/new_transactions_review_sheet.dart:148` | onToggleIgnore | `onToggleIgnore: () {` |
| `lib/widgets/new_transactions_review_sheet.dart:172` | onPressed | `onPressed: _saving` |
| `lib/widgets/new_transactions_review_sheet.dart:190` | onPressed | `onPressed: _saving ? null : _confirm,` |
| `lib/widgets/new_transactions_review_sheet.dart:289` | onTap | `onTap: onToggleIgnore,` |
| `lib/widgets/tracking_onboarding_sheet.dart:21` | showModalBottomSheet | `return showModalBottomSheet<OnboardingResult>(` |
| `lib/widgets/tracking_onboarding_sheet.dart:114` | onTap | `onTap: () => _pickDate(context),` |
| `lib/widgets/tracking_onboarding_sheet.dart:125` | onTap | `onTap: () {` |
| `lib/widgets/tracking_onboarding_sheet.dart:148` | onTap | `onTap: () {` |
| `lib/widgets/tracking_onboarding_sheet.dart:159` | onTap | `onTap: () {` |
| `lib/widgets/tracking_onboarding_sheet.dart:171` | onTap | `onTap: () {` |
| `lib/widgets/tracking_onboarding_sheet.dart:187` | onPressed | `onPressed: _selectedOption == -1 ? null : _onContinue,` |
| `lib/widgets/tracking_onboarding_sheet.dart:208` | showDatePicker | `final picked = await showDatePicker(` |
| `lib/widgets/tracking_onboarding_sheet.dart:270` | onTap | `onTap: onTap,` |
| `lib/widgets/tracking_onboarding_sheet.dart:343` | onPressed | `onPressed: onTap,` |
| `lib/widgets/transaction_card.dart:65` | onTap | `onTap: selectionMode ? () => onSelected?.call(!selected) : onTap,` |
| `lib/widgets/transaction_card.dart:66` | onLongPress | `onLongPress: onLongPress,` |
| `lib/widgets/transaction_card.dart:84` | onChanged | `onChanged: (value) => onSelected?.call(value ?? false),` |
| `lib/widgets/transaction_detail_sheet.dart:30` | showModalBottomSheet | `showModalBottomSheet(` |
| `lib/widgets/transaction_detail_sheet.dart:35` | onTransactionUpdated | `TransactionDetailSheet(tx: tx, onTransactionUpdated: onUpdated),` |
| `lib/widgets/transaction_detail_sheet.dart:157` | onPressed | `onPressed: _showCorrectionDialog,` |
| `lib/widgets/transaction_detail_sheet.dart:177` | onTap | `onTap: _toggleIgnore,` |
| `lib/widgets/transaction_detail_sheet.dart:223` | onChanged | `onChanged: (_) => _toggleIgnore(),` |
| `lib/widgets/transaction_detail_sheet.dart:246` | onTap | `onTap: _showCategoryPicker,` |
| `lib/widgets/transaction_detail_sheet.dart:250` | onPressed | `onPressed: _showCategoryPicker,` |
| `lib/widgets/transaction_detail_sheet.dart:270` | onTap | `onTap: _showTagEditor,` |
| `lib/widgets/transaction_detail_sheet.dart:324` | onTap | `onTap: _showNoteEditor,` |
| `lib/widgets/transaction_detail_sheet.dart:382` | onTap | `onTap: _showSourcePicker,` |
| `lib/widgets/transaction_detail_sheet.dart:415` | onTap | `onTap: _accounts.isNotEmpty ? _showAccountPicker : null,` |
| `lib/widgets/transaction_detail_sheet.dart:518` | showDialog | `showDialog(` |
| `lib/widgets/transaction_detail_sheet.dart:541` | onPressed | `onPressed: () => Navigator.pop(context),` |
| `lib/widgets/transaction_detail_sheet.dart:546` | onPressed | `onPressed: () => _correctType(TransactionType.debit),` |
| `lib/widgets/transaction_detail_sheet.dart:553` | onPressed | `onPressed: () => _correctType(TransactionType.credit),` |
| `lib/widgets/transaction_detail_sheet.dart:602` | showDialog | `showDialog(` |
| `lib/widgets/transaction_detail_sheet.dart:617` | onPressed | `onPressed: () => Navigator.pop(ctx),` |
| `lib/widgets/transaction_detail_sheet.dart:621` | onPressed | `onPressed: () async {` |
| `lib/widgets/transaction_detail_sheet.dart:647` | showDialog | `showDialog(` |
| `lib/widgets/transaction_detail_sheet.dart:662` | onPressed | `onPressed: () => Navigator.pop(ctx),` |
| `lib/widgets/transaction_detail_sheet.dart:667` | onPressed | `onPressed: () async {` |
| `lib/widgets/transaction_detail_sheet.dart:682` | onPressed | `onPressed: () async {` |
| `lib/widgets/transaction_detail_sheet.dart:735` | showDialog | `showDialog(` |
| `lib/widgets/transaction_detail_sheet.dart:757` | onTap | `onTap: () => _updateSource(ctx, source),` |
| `lib/widgets/transaction_detail_sheet.dart:764` | onPressed | `onPressed: () => Navigator.pop(ctx),` |
| `lib/widgets/transaction_detail_sheet.dart:826` | showModalBottomSheet | `showModalBottomSheet(` |
| `lib/widgets/transaction_detail_sheet.dart:866` | onPressed | `onPressed: () {` |
| `lib/widgets/transaction_detail_sheet.dart:904` | onTap | `onTap: () {` |
| `lib/widgets/transaction_detail_sheet.dart:934` | showModalBottomSheet | `showModalBottomSheet<void>(` |
| `lib/widgets/transaction_detail_sheet.dart:946` | onPressed | `onPressed: () async {` |
| `lib/widgets/transaction_detail_sheet.dart:962` | onTap | `onTap: () {` |
| `lib/widgets/transaction_detail_sheet.dart:972` | onTap | `onTap: () {` |
| `lib/widgets/transaction_detail_sheet.dart:1086` | onPressed | `onPressed: _viewPartnerTransaction,` |
| `lib/widgets/transaction_detail_sheet.dart:1105` | onPressed | `onPressed: _unmergeTransfer,` |
| `lib/widgets/transaction_detail_sheet.dart:1204` | onTap | `onTap: () {` |
| `lib/widgets/transaction_detail_sheet.dart:1245` | onTap | `onTap: onTap,` |

Baseline controls indexed: **352**.

## Implemented files and rationale

- `lib/main.dart`: use MainShellScreen as the app entry; keep the original Provider and Material 3 light/dark themes.
- `lib/screens/main_shell_screen.dart`: five retained primary destinations, root Navigator routes, explicit existing return-refresh callbacks, Activity tool menu and Android Back handling.
- `lib/widgets/navigation_hub.dart`: shared, responsive navigation cards for Insights and Plan; every row opens an existing screen.
- `lib/screens/home_screen.dart`: real summary first; remove the mapped shortcut grid; retain current-cycle filtering, details, swipes, startup and permission flows; read actual alert/review counts after scans and route returns.
- `lib/screens/all_transactions_screen.dart`: embed the existing Activity screen, preserve filters and scroll/selection state, handle See All direction requests, refresh salary-cycle choices with reads, and route Back safely when tabs are retained. All original totals and transaction operations remain.
- `lib/screens/spending_heatmap_screen.dart`: Activity-style filters, exact filtered calendar/day/month amounts, optional incoming/activity views and internal transfers, retained filter choices across months, responsive scrolling and accessible calendar labels.
- `lib/utils/transaction_filters.dart`: share the existing Activity matching predicate with the heatmap; Activity classification and totals remain unchanged.
- `test/heatmap_filters_test.dart`: filter combinations, search, chart intensity, exact daily/month statistics, directions and transfers, cycle/month boundaries, tracking start, refresh, data integrity, dark mode, text scale and keyboard.
- `lib/screens/budget_screen.dart`: use the existing budget screen as a retained primary tab, preserve the selected period and scroll, reload current income/categories/salary-period choices on return, and expose Settings. All budget calculations and existing workflows remain.
- `lib/screens/settings_screen.dart`: add Tracking Settings, keeping every existing Settings entry and handler.
- `lib/widgets/summary_card.dart`: display the existing cycle title and adapt the existing totals layout to narrow screens and larger text; no formula/format changes.
- `lib/widgets/tracking_onboarding_sheet.dart`: wrap preset chips and allow sheet scrolling to fix the overflow exposed by navigation tests; choices and persistence are unchanged.
- `lib/screens/transaction_review_screen.dart`: top Ignore all action reuses the existing per-message ignore operation; pending items are retained on write failure, conflicting actions are disabled while saving, and messages remain restorable in Message Decisions.
- `test/review_ignore_all_test.dart`: offscreen bulk ignore, unchanged transaction/other stored data, restore, partial-write failure/retry, empty state and small-screen accessibility.
- `test/navigation_shell_test.dart`: focused coverage of navigation, state, return callbacks and responsive layout using the production SQLite schema and real service summary getters. Only the SMS/platform scanning boundary is replaced by a counting test service.
- `NAVIGATION_INVENTORY.md`: baseline action mapping, contextual-control index, lifecycle contracts and final verification record.

## UI structure

- Home: app title/Scan/actual Alerts badge/Settings, current salary-cycle summary, optional actual review/alert shortcuts, original direction and bank filters, recent transactions and See All.
- Activity: original transaction search, filters, selection, totals and list; Activity tools, sorting and Settings in the toolbar.
- Budgets: existing Smart Budgets screen with income, period selection, category budgets, suggestions, Add Budget and Outside Budgets; Settings in the toolbar.
- Insights: Spending Breakdown, Category Breakdown, Spending Heatmap and Merchant Rankings.
- Plan: Accounts and income (Accounts, Salary Cycles); Commitments (EMI Tracker); Organization (Categories).
- Settings and existing feature detail routes keep their original full content and Back behavior. Salary closeout, Outside Budgets, transaction windows, transfer merge/unmerge, category assignment and backup tools remain within their existing workflows.

## Heatmap filter behavior

- Default is Money Out with internal transfers excluded, preserving the original expense-only calendar.
- All, Money In and Money Out use Activity's direction, search, sender, category, tag and salary-cycle matching predicate. Choices within a chip group are combined with OR; groups are combined with AND. Uncategorized is a selectable category.
- Money In shows credit amounts; All shows credit plus debit activity. Including internal transfers displays their matching debit/credit entries as activity; a complete pair contributes both amounts in All mode. This is a gross-activity view.
- Salary-cycle boundaries use the existing inclusive start and exclusive end, intersected with the displayed calendar month. Month changes keep the current filter choices; Reset clears filters back to the default spending view while keeping the displayed month.
- Daily color intensity, monthly total, average per active day, peak and active-day count all come from the same matching transactions used by the selected-day sheet. Paise are retained. Ignored and untracked transactions remain excluded.
- Refresh reloads current stored transactions, category names and cycle options while retaining valid filters. All filter and month changes are read-only.

## Verification

Validated against the final application source:

| Check | Result |
|---|---|
| `flutter analyze --no-pub` | Passed, no issues |
| `flutter test --no-pub` | Passed, 114 tests (87 existing, 17 navigation, 3 bulk-ignore and 7 heatmap-filter tests) |
| Original four-tab refactor: `flutter build apk --debug --no-pub` | Passed; debug artifact predates the five-tab follow-up |
| Five-tab, bulk-ignore and heatmap-filter follow-ups: `flutter build apk --release --no-pub` | Passed; `build/app/outputs/flutter-apk/app-release.apk` (54.3 MB), using the existing signing configuration |
| `git diff --check` | Passed |
| SHA-256 comparison of all pre-existing Dart files | The original refactor changed six existing UI/entry files. The five-tab follow-up additionally adapts BudgetScreen; services, storage, models and accounting/classification remain unchanged; Activity matching is extracted into a shared pure helper |

Navigation coverage includes all five tabs; all eight Insights/Plan destinations, the Budgets primary tab and salary closeout; all seven Activity tools; Settings from every tab, Tracking Settings and Merchant Rules; actual alert/review counts, bulk-ignore return refresh and pull-to-refresh; startup onboarding and new-transaction review; salary/review/settings return callbacks; repeated See All direction requests; retained Home filters, Activity filters/search/scroll/selection, Budget period/scroll and its Outside Budgets return route; Android Back including hidden-tab selection; loading/permission-error/retry; 320-pixel dark layouts with 1.6 text scale; and keyboard insets. A database snapshot confirms that switching tabs causes no storage mutations or scans.

All 12 former Home grid destinations, toolbar actions, Settings entries and the indexed contextual controls remain reachable. No dependencies, database/schema, services, storage, models, parser, SMS permission or backup implementation changed. Existing accounting and classification remain unchanged; the heatmap now offers explicit incoming and gross-activity views in addition to its original spending default. Temporary screenshot tooling was removed from the repository changes. No commit or push was made.

### Practical validation limits

Widget tests replace the Android SMS/platform scanning boundary with a counting service; real summaries and the production SQLite schema are used. APK builds were verified as recorded above; this task did not install/run the app on a physical phone. Device-only permission prompts, SMS scanning and system backup/file-sharing integrations were not exercised on hardware. Their implementations are unchanged. No known incomplete implementation remains within this UI/navigation scope.
