//! Club accounts — the books a treasurer keeps and takes to the AGM.
//!
//! The report is worked out here, from figures the database has already
//! summed, so the arithmetic that decides whether a club's books agree is
//! plain code with tests rather than SQL nobody can step through.
//!
//! Every amount is in minor units (pence). A float never touches money.

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

// MARK: who may open the books

/// Whether somebody may open a club's accounts.
///
/// Two facts decide it, and a role is not one of them: owning the club, or
/// being an active member the club has made its treasurer. A secretary is not
/// a treasurer — club money is the one place where "the secretary can do
/// everything" stops — and the platform's super admin gets no way in either.
pub fn can_open_accounts(is_owner: bool, is_active_treasurer: bool) -> bool {
    is_owner || is_active_treasurer
}

/// Who may change somebody's treasurer flag. The owner, for anybody. A
/// secretary, for anybody but themselves: appointing yourself would turn "a
/// secretary is not a treasurer" into one request. Stepping down is always
/// allowed — giving up access is not the thing being guarded.
pub fn can_set_treasurer(
    is_owner: bool,
    is_secretary: bool,
    is_self: bool,
    appointing: bool,
) -> bool {
    is_owner || (is_secretary && !(is_self && appointing))
}

// MARK: what the books hold

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EntryKind {
    Income,
    Expenditure,
    /// A correction to an earlier year's books. Signed, and printed on the
    /// balance sheet as its own line so it is never taken for trading.
    Adjustment,
}

impl EntryKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Income => "income",
            Self::Expenditure => "expenditure",
            Self::Adjustment => "adjustment",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CategoryKind {
    Income,
    Expenditure,
}

impl CategoryKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Income => "income",
            Self::Expenditure => "expenditure",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AccountPeriod {
    pub id: Uuid,
    pub club_id: Uuid,
    pub label: String,
    pub starts_on: NaiveDate,
    pub ends_on: NaiveDate,
    /// `open` or `closed`.
    pub status: String,
    pub currency: String,
    pub opening_balance_cents: i64,
    pub report_text: Option<String>,
    pub statement_text: Option<String>,
    pub signed_by_name: Option<String>,
    pub signed_on: Option<NaiveDate>,
    pub closed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

impl AccountPeriod {
    pub fn is_open(&self) -> bool {
        self.status == "open"
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AccountCategory {
    pub id: Uuid,
    pub club_id: Uuid,
    /// `income` or `expenditure`.
    pub kind: String,
    pub name: String,
    pub system_key: Option<String>,
    pub sort_order: i32,
    pub footnote: Option<String>,
    pub archived: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct MoneyAccount {
    pub id: Uuid,
    pub club_id: Uuid,
    pub name: String,
    /// `bank`, `cash`, `supplier_credit` or `provider`.
    pub kind: String,
    pub sort_order: i32,
    pub archived: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AccountTransaction {
    pub id: Uuid,
    pub club_id: Uuid,
    pub period_id: Uuid,
    pub occurred_on: NaiveDate,
    pub kind: String,
    pub category_id: Option<Uuid>,
    pub category_name: Option<String>,
    pub money_account_id: Option<Uuid>,
    pub money_account_name: Option<String>,
    pub amount_cents: i64,
    pub description: String,
    pub counterparty: Option<String>,
    pub member_id: Option<Uuid>,
    pub member_name: Option<String>,
    pub event_id: Option<Uuid>,
    pub note: Option<String>,
    pub receipt_url: Option<String>,
    pub extraordinary: bool,
    pub authorised_on: Option<NaiveDate>,
    pub authorisation_ref: Option<String>,
    pub source: Option<String>,
    pub voided_at: Option<DateTime<Utc>>,
    pub void_reason: Option<String>,
    pub created_by_name: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// A debt as the treasurer reads it: what it was, and where it stands.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct DebtPosition {
    pub id: Uuid,
    pub period_id: Uuid,
    /// The year it was raised in, e.g. "2024/25".
    pub period_label: String,
    /// `debtor` (owed to the club) or `creditor` (owed by it).
    pub direction: String,
    /// `member_fees`, `cost_share` or `other`.
    pub kind: String,
    pub description: String,
    pub counterparty: Option<String>,
    pub member_id: Option<Uuid>,
    pub member_name: Option<String>,
    pub event_id: Option<Uuid>,
    pub raised_on: NaiveDate,
    pub amount_cents: i64,
    /// Still owed on the last day of the year being reported.
    pub outstanding_at_close_cents: i64,
    /// Paid after the books closed — "£108.50 paid since books closed".
    pub paid_since_close_cents: i64,
    /// Still owed today.
    pub outstanding_now_cents: i64,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct DebtSettlement {
    pub id: Uuid,
    pub debt_id: Uuid,
    pub settled_on: NaiveDate,
    /// `payment`, `write_off` or `shortfall`.
    pub kind: String,
    pub amount_cents: i64,
    pub money_account_id: Option<Uuid>,
    pub note: Option<String>,
    pub voided_at: Option<DateTime<Utc>>,
}

/// One money account's year, as the balance sheet needs it.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct MoneyAccountPosition {
    pub id: Uuid,
    pub name: String,
    pub kind: String,
    pub opening_cents: i64,
    /// What the books say it should hold at the end of the year.
    pub computed_closing_cents: i64,
    /// What the statement says it held, when the treasurer has entered it.
    pub reconciled_cents: Option<i64>,
    pub reconciled_on: Option<NaiveDate>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct StockPosition {
    pub item_id: Uuid,
    pub name: String,
    pub opening_quantity: i32,
    pub opening_cents: i64,
    pub closing_quantity: i32,
    pub closing_cents: i64,
    pub counted_on: Option<NaiveDate>,
}

/// A payment taken in the app that the books have not yet heard about.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct PaymentSuggestion {
    pub payment_id: Uuid,
    pub paid_on: NaiveDate,
    pub amount_cents: i64,
    pub currency: String,
    pub member_id: Uuid,
    pub member_name: String,
    pub event_id: Uuid,
    pub event_title: String,
    pub event_subtype: String,
    /// The debt it pays off, when the fee was already owed at a year end.
    pub settles_debt_id: Option<Uuid>,
}

/// A match fee nobody has paid, from a fixture in the year being kept.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct UnpaidFee {
    pub event_id: Uuid,
    pub event_title: String,
    pub played_on: NaiveDate,
    pub member_id: Uuid,
    pub member_name: String,
    pub amount_cents: i64,
    /// Already raised as a debtor.
    pub already_raised: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AuditEntry {
    pub id: i64,
    pub actor_name: Option<String>,
    pub action: String,
    pub entity: String,
    pub entity_id: Option<Uuid>,
    pub before: Option<serde_json::Value>,
    pub after: Option<serde_json::Value>,
    pub created_at: DateTime<Utc>,
}

// MARK: requests

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreatePeriodRequest {
    #[validate(length(min = 1, max = 40))]
    pub label: String,
    pub starts_on: NaiveDate,
    pub ends_on: NaiveDate,
    /// Only for a club's first year here; later years carry the last c/f.
    pub opening_balance_cents: Option<i64>,
    #[validate(length(equal = 3))]
    pub currency: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct UpdatePeriodRequest {
    #[validate(length(min = 1, max = 40))]
    pub label: Option<String>,
    pub opening_balance_cents: Option<i64>,
    #[validate(length(max = 20000))]
    pub report_text: Option<String>,
    #[validate(length(max = 2000))]
    pub statement_text: Option<String>,
    #[validate(length(max = 120))]
    pub signed_by_name: Option<String>,
    pub signed_on: Option<NaiveDate>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct ReopenPeriodRequest {
    #[validate(length(min = 3, max = 500))]
    pub reason: String,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateCategoryRequest {
    pub kind: CategoryKind,
    #[validate(length(min = 1, max = 80))]
    pub name: String,
    pub sort_order: Option<i32>,
    #[validate(length(max = 600))]
    pub footnote: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct UpdateCategoryRequest {
    #[validate(length(min = 1, max = 80))]
    pub name: Option<String>,
    pub sort_order: Option<i32>,
    #[serde(default, deserialize_with = "crate::double_option")]
    pub footnote: Option<Option<String>>,
    pub archived: Option<bool>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateMoneyAccountRequest {
    #[validate(length(min = 1, max = 80))]
    pub name: String,
    pub kind: String,
    /// Opening balance in the open year.
    pub opening_cents: Option<i64>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct UpdateMoneyAccountRequest {
    #[validate(length(min = 1, max = 80))]
    pub name: Option<String>,
    pub archived: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SetAccountBalanceRequest {
    pub period_id: Uuid,
    pub opening_cents: Option<i64>,
    /// `null` clears a reconciliation entered by mistake.
    #[serde(default, deserialize_with = "crate::double_option")]
    pub reconciled_cents: Option<Option<i64>>,
    pub reconciled_on: Option<NaiveDate>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateTransactionRequest {
    pub occurred_on: NaiveDate,
    pub kind: EntryKind,
    pub category_id: Option<Uuid>,
    pub money_account_id: Option<Uuid>,
    pub amount_cents: i64,
    #[validate(length(min = 1, max = 200))]
    pub description: String,
    #[validate(length(max = 120))]
    pub counterparty: Option<String>,
    pub member_id: Option<Uuid>,
    pub event_id: Option<Uuid>,
    #[validate(length(max = 2000))]
    pub note: Option<String>,
    #[validate(length(max = 1000))]
    pub receipt_url: Option<String>,
    #[serde(default)]
    pub extraordinary: bool,
    pub authorised_on: Option<NaiveDate>,
    #[validate(length(max = 120))]
    pub authorisation_ref: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct UpdateTransactionRequest {
    pub occurred_on: Option<NaiveDate>,
    pub category_id: Option<Uuid>,
    #[serde(default, deserialize_with = "crate::double_option")]
    pub money_account_id: Option<Option<Uuid>>,
    pub amount_cents: Option<i64>,
    #[validate(length(min = 1, max = 200))]
    pub description: Option<String>,
    #[serde(default, deserialize_with = "crate::double_option")]
    pub counterparty: Option<Option<String>>,
    #[serde(default, deserialize_with = "crate::double_option")]
    pub note: Option<Option<String>>,
    #[serde(default, deserialize_with = "crate::double_option")]
    pub receipt_url: Option<Option<String>>,
    pub extraordinary: Option<bool>,
    #[serde(default, deserialize_with = "crate::double_option")]
    pub authorised_on: Option<Option<NaiveDate>>,
    #[serde(default, deserialize_with = "crate::double_option")]
    pub authorisation_ref: Option<Option<String>>,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct VoidRequest {
    #[validate(length(min = 3, max = 500))]
    pub reason: String,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateDebtRequest {
    /// `debtor` or `creditor`.
    pub direction: String,
    /// `member_fees`, `cost_share` or `other`.
    pub kind: String,
    #[validate(length(min = 1, max = 200))]
    pub description: String,
    #[validate(length(max = 120))]
    pub counterparty: Option<String>,
    pub member_id: Option<Uuid>,
    pub event_id: Option<Uuid>,
    pub amount_cents: i64,
    pub raised_on: NaiveDate,
    #[validate(length(max = 2000))]
    pub note: Option<String>,
    /// Put the other side in the books too: "Match/net fees owed" for fees,
    /// "Cost shares owed" for cost shares. On by default — a debt raised
    /// without it does not change the year's result.
    #[serde(default = "yes")]
    pub accrue: bool,
}

fn yes() -> bool {
    true
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct SettleDebtRequest {
    /// `payment`, `write_off` or `shortfall`.
    pub kind: String,
    pub amount_cents: i64,
    pub settled_on: NaiveDate,
    pub money_account_id: Option<Uuid>,
    #[validate(length(max = 2000))]
    pub note: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RaiseUnpaidFeesRequest {
    /// Fixtures to raise. Empty raises every unpaid fee in the year.
    #[serde(default)]
    pub event_ids: Vec<Uuid>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AcceptPaymentsRequest {
    pub payment_ids: Vec<Uuid>,
    /// Where app payments land — usually the bank, or a "Stripe" account.
    pub money_account_id: Uuid,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateStockItemRequest {
    #[validate(length(min = 1, max = 80))]
    pub name: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SetStockCountRequest {
    pub period_id: Uuid,
    pub opening_quantity: Option<i32>,
    pub opening_cents: Option<i64>,
    pub closing_quantity: Option<i32>,
    pub closing_cents: Option<i64>,
    pub counted_on: Option<NaiveDate>,
}

// MARK: the categories a club starts with

pub struct DefaultCategory {
    pub kind: CategoryKind,
    pub name: &'static str,
    pub system_key: Option<&'static str>,
    pub footnote: Option<&'static str>,
}

const fn cat(
    kind: CategoryKind,
    name: &'static str,
    system_key: Option<&'static str>,
    footnote: Option<&'static str>,
) -> DefaultCategory {
    DefaultCategory { kind, name, system_key, footnote }
}

/// The lines a cricket club's accounts usually have, in the order an AGM
/// expects to read them. A club renames, reorders and adds to these.
pub const DEFAULT_CATEGORIES: &[DefaultCategory] = {
    use CategoryKind::{Expenditure as E, Income as I};
    &[
        cat(I, "Indoor net fees", Some(keys::NET_FEES), None),
        cat(I, "Outdoor match fees", Some(keys::MATCH_FEES), None),
        cat(I, "Match/net fees owed", Some(keys::FEES_OWED), None),
        cat(I, "Miscellaneous", Some(keys::MISC), None),
        cat(I, "Sponsorship", None, None),
        cat(I, "Cost share with other teams", Some(keys::COST_SHARE), None),
        cat(I, "Cost shares owed", Some(keys::COST_SHARE_OWED), None),
        cat(I, "Interest", None, None),
        cat(E, "Indoor nets", Some(keys::NET_HIRE), None),
        cat(E, "Pitch hire", Some(keys::PITCH_HIRE), None),
        cat(E, "Cost share with other teams", Some(keys::COST_SHARE), None),
        cat(
            E,
            "Losses on previous year recovered debt",
            Some(keys::RECOVERED_DEBT_LOSS),
            Some("Fees owed at the last year end that came in short, for example after a payment provider's charges."),
        ),
        cat(
            E,
            "Unrecovered debt",
            Some(keys::UNRECOVERED_DEBT),
            Some("Fees overdue from earlier seasons that the club agreed to write off."),
        ),
        cat(E, "Cost shares owed", Some(keys::COST_SHARE_OWED), None),
        cat(
            E,
            "Equipment purchase",
            Some(keys::EQUIPMENT),
            Some("Match balls used in the season count as spending. Balls bought and not used are added to stock, and stock used from last year is added here."),
        ),
        cat(E, "Public liability insurance", Some(keys::INSURANCE), None),
        cat(E, "Engraving, trophies etc.", None, None),
        cat(E, "Food (home games)", None, None),
        cat(E, "Website", Some(keys::WEBSITE), None),
        cat(E, "Charitable donations", None, None),
        cat(E, "Social", None, None),
        cat(E, "Miscellaneous", Some(keys::MISC), None),
    ]
};

/// The categories the app writes to or reads by itself.
pub mod keys {
    pub const NET_FEES: &str = "net_fees";
    pub const MATCH_FEES: &str = "match_fees";
    pub const FEES_OWED: &str = "fees_owed";
    pub const MISC: &str = "misc";
    pub const COST_SHARE: &str = "cost_share";
    pub const COST_SHARE_OWED: &str = "cost_share_owed";
    pub const NET_HIRE: &str = "net_hire";
    pub const PITCH_HIRE: &str = "pitch_hire";
    pub const RECOVERED_DEBT_LOSS: &str = "recovered_debt_loss";
    pub const UNRECOVERED_DEBT: &str = "unrecovered_debt";
    pub const EQUIPMENT: &str = "equipment";
    pub const INSURANCE: &str = "insurance";
    pub const WEBSITE: &str = "website";
}

/// Which income line a fee paid in the app belongs on.
pub fn fee_category_key(event_subtype: &str) -> &'static str {
    match event_subtype {
        "nets" | "training" => keys::NET_FEES,
        _ => keys::MATCH_FEES,
    }
}

// MARK: the report

/// What the database hands over for one year: totals, not rows.
#[derive(Debug, Clone)]
pub struct ReportInput {
    pub period: AccountPeriod,
    pub categories: Vec<AccountCategory>,
    /// Live income and expenditure per category, in pence.
    pub category_totals: Vec<(Uuid, i64)>,
    /// Sum of prior-period adjustments (signed).
    pub adjustments_cents: i64,
    /// Extraordinary spending, and extraordinary income, kept apart.
    pub extraordinary_expenditure_cents: i64,
    pub extraordinary_income_cents: i64,
    pub money_accounts: Vec<MoneyAccountPosition>,
    pub stock: Vec<StockPosition>,
    pub debts: Vec<DebtPosition>,
    /// Fixtures with a fee that were played in the year.
    pub matches_played: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ReportLine {
    pub category_id: Uuid,
    pub name: String,
    pub system_key: Option<String>,
    pub amount_cents: i64,
    /// The number printed beside the line, (1), (2)…
    pub footnote: Option<u32>,
    /// How much of the amount is the change in stock, not money spent.
    pub stock_adjustment_cents: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Footnote {
    pub number: u32,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AssetLine {
    pub label: String,
    /// `money`, `stock`, `debtors` or `creditors`.
    pub kind: String,
    /// Signed as it counts towards the total: creditors are negative.
    pub amount_cents: i64,
    /// For a money account: whether the figure came off a statement.
    pub reconciled: Option<bool>,
    /// For an unreconciled money account, what the books say instead.
    pub computed_cents: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BalanceSheet {
    pub brought_forward_cents: i64,
    pub adjustments_cents: i64,
    pub income_cents: i64,
    pub total_cents: i64,
    pub expenditure_cents: i64,
    pub carried_forward_cents: i64,
    pub represented_by: Vec<AssetLine>,
    pub represented_total_cents: i64,
    /// Represented by − c/f. Zero when the books agree. Never hidden.
    pub difference_cents: i64,
    /// Money accounts with no statement figure entered.
    pub unreconciled_accounts: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Insights {
    pub surplus_cents: i64,
    pub extraordinary_cents: i64,
    /// The result if the one-off items had not happened.
    pub surplus_excluding_extraordinary_cents: i64,
    pub nets: Option<Comparison>,
    pub match_fees_cents: i64,
    pub matches_played: i64,
    pub match_fee_per_match_cents: Option<i64>,
    pub equipment_per_match_cents: Option<i64>,
    pub debtors_at_close_cents: i64,
    pub paid_since_close_cents: i64,
}

/// Money in against money out for one activity.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Comparison {
    pub received_cents: i64,
    pub cost_cents: i64,
    pub net_cents: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountsReport {
    pub period_id: Uuid,
    pub label: String,
    pub starts_on: NaiveDate,
    pub ends_on: NaiveDate,
    pub status: String,
    pub currency: String,
    pub income: Vec<ReportLine>,
    pub income_total_cents: i64,
    pub expenditure: Vec<ReportLine>,
    pub expenditure_total_cents: i64,
    /// Excess of income over expenditure; negative is a loss.
    pub surplus_cents: i64,
    pub footnotes: Vec<Footnote>,
    pub balance_sheet: BalanceSheet,
    pub debtors: Vec<DebtPosition>,
    pub debtors_total_cents: i64,
    pub creditors: Vec<DebtPosition>,
    pub creditors_total_cents: i64,
    pub stock: Vec<StockPosition>,
    pub insights: Insights,
    pub report_text: Option<String>,
    pub statement_text: Option<String>,
    pub signed_by_name: Option<String>,
    pub signed_on: Option<NaiveDate>,
}

/// Work out one year's accounts.
///
/// Every line of the club's categories is printed, zero or not, in the club's
/// order — an AGM reads this year's figures beside last year's, and a line
/// that vanishes when it is zero makes the two columns impossible to line up.
/// Archived categories print only when they have something in them.
pub fn build_report(input: &ReportInput) -> AccountsReport {
    let total_for = |id: Uuid| -> i64 {
        input
            .category_totals
            .iter()
            .filter(|(c, _)| *c == id)
            .map(|(_, v)| *v)
            .sum()
    };

    let stock_opening: i64 = input.stock.iter().map(|s| s.opening_cents).sum();
    let stock_closing: i64 = input.stock.iter().map(|s| s.closing_cents).sum();
    // Stock that went up was bought and not used: it is an asset, not a cost.
    // Stock that went down was used from last year's shelf: it is a cost.
    let stock_movement = stock_opening - stock_closing;

    let mut cats: Vec<&AccountCategory> = input.categories.iter().collect();
    cats.sort_by(|a, b| a.sort_order.cmp(&b.sort_order).then(a.name.cmp(&b.name)));

    let mut footnotes: Vec<Footnote> = Vec::new();
    let mut lines_for = |kind: &str| -> Vec<ReportLine> {
        let mut out = Vec::new();
        for c in cats.iter().filter(|c| c.kind == kind) {
            let mut amount = total_for(c.id);
            let mut stock_adjustment = 0;
            if kind == "expenditure" && c.system_key.as_deref() == Some(keys::EQUIPMENT) {
                stock_adjustment = stock_movement;
                amount += stock_movement;
            }
            if c.archived && amount == 0 {
                continue;
            }
            let footnote = c.footnote.as_ref().filter(|t| !t.trim().is_empty()).map(|text| {
                let number = footnotes.len() as u32 + 1;
                footnotes.push(Footnote { number, text: text.clone() });
                number
            });
            out.push(ReportLine {
                category_id: c.id,
                name: c.name.clone(),
                system_key: c.system_key.clone(),
                amount_cents: amount,
                footnote,
                stock_adjustment_cents: stock_adjustment,
            });
        }
        out
    };
    let income = lines_for("income");
    let expenditure = lines_for("expenditure");

    let income_total: i64 = income.iter().map(|l| l.amount_cents).sum();
    let expenditure_total: i64 = expenditure.iter().map(|l| l.amount_cents).sum();
    let surplus = income_total - expenditure_total;

    let brought_forward = input.period.opening_balance_cents;
    let total = brought_forward + input.adjustments_cents + income_total;
    let carried_forward = total - expenditure_total;

    let mut represented_by = Vec::new();
    let mut unreconciled = Vec::new();
    for a in &input.money_accounts {
        let (amount, reconciled) = match a.reconciled_cents {
            Some(v) => (v, true),
            None => {
                unreconciled.push(a.name.clone());
                (a.computed_closing_cents, false)
            }
        };
        represented_by.push(AssetLine {
            label: a.name.clone(),
            kind: "money".into(),
            amount_cents: amount,
            reconciled: Some(reconciled),
            computed_cents: (!reconciled || a.computed_closing_cents != amount)
                .then_some(a.computed_closing_cents),
        });
    }
    for s in &input.stock {
        represented_by.push(AssetLine {
            label: s.name.clone(),
            kind: "stock".into(),
            amount_cents: s.closing_cents,
            reconciled: None,
            computed_cents: None,
        });
    }

    let (debtors, creditors): (Vec<DebtPosition>, Vec<DebtPosition>) = input
        .debts
        .iter()
        .filter(|d| d.outstanding_at_close_cents > 0)
        .cloned()
        .partition(|d| d.direction == "debtor");
    let debtors_total: i64 = debtors.iter().map(|d| d.outstanding_at_close_cents).sum();
    let creditors_total: i64 = creditors.iter().map(|d| d.outstanding_at_close_cents).sum();
    represented_by.push(AssetLine {
        label: "Debtors".into(),
        kind: "debtors".into(),
        amount_cents: debtors_total,
        reconciled: None,
        computed_cents: None,
    });
    represented_by.push(AssetLine {
        label: "Creditors".into(),
        kind: "creditors".into(),
        amount_cents: -creditors_total,
        reconciled: None,
        computed_cents: None,
    });
    let represented_total: i64 = represented_by.iter().map(|l| l.amount_cents).sum();

    let amount_for_key = |lines: &[ReportLine], key: &str| -> i64 {
        lines
            .iter()
            .filter(|l| l.system_key.as_deref() == Some(key))
            .map(|l| l.amount_cents)
            .sum()
    };
    let has_key = |lines: &[ReportLine], key: &str| {
        lines.iter().any(|l| l.system_key.as_deref() == Some(key))
    };

    let net_fees = amount_for_key(&income, keys::NET_FEES);
    let net_hire = amount_for_key(&expenditure, keys::NET_HIRE);
    let nets = (has_key(&income, keys::NET_FEES) || has_key(&expenditure, keys::NET_HIRE))
        .then_some(Comparison {
            received_cents: net_fees,
            cost_cents: net_hire,
            net_cents: net_fees - net_hire,
        })
        .filter(|c| c.received_cents != 0 || c.cost_cents != 0);

    let match_fees = amount_for_key(&income, keys::MATCH_FEES);
    let equipment = amount_for_key(&expenditure, keys::EQUIPMENT);
    let per_match = |v: i64| (input.matches_played > 0).then(|| round_div(v, input.matches_played));
    let extraordinary = input.extraordinary_expenditure_cents - input.extraordinary_income_cents;

    AccountsReport {
        period_id: input.period.id,
        label: input.period.label.clone(),
        starts_on: input.period.starts_on,
        ends_on: input.period.ends_on,
        status: input.period.status.clone(),
        currency: input.period.currency.clone(),
        income,
        income_total_cents: income_total,
        expenditure,
        expenditure_total_cents: expenditure_total,
        surplus_cents: surplus,
        footnotes,
        balance_sheet: BalanceSheet {
            brought_forward_cents: brought_forward,
            adjustments_cents: input.adjustments_cents,
            income_cents: income_total,
            total_cents: total,
            expenditure_cents: expenditure_total,
            carried_forward_cents: carried_forward,
            represented_by,
            represented_total_cents: represented_total,
            difference_cents: represented_total - carried_forward,
            unreconciled_accounts: unreconciled,
        },
        insights: Insights {
            surplus_cents: surplus,
            extraordinary_cents: extraordinary,
            surplus_excluding_extraordinary_cents: surplus + extraordinary,
            nets,
            match_fees_cents: match_fees,
            matches_played: input.matches_played,
            match_fee_per_match_cents: per_match(match_fees),
            equipment_per_match_cents: per_match(equipment),
            debtors_at_close_cents: debtors_total,
            paid_since_close_cents: debtors.iter().map(|d| d.paid_since_close_cents).sum(),
        },
        debtors,
        debtors_total_cents: debtors_total,
        creditors,
        creditors_total_cents: creditors_total,
        stock: input.stock.clone(),
        report_text: input.period.report_text.clone(),
        statement_text: input.period.statement_text.clone(),
        signed_by_name: input.period.signed_by_name.clone(),
        signed_on: input.period.signed_on,
    }
}

/// Integer division rounded half away from zero, so an average fee of
/// £115.89½ prints as £115.90 and not £115.89.
fn round_div(n: i64, d: i64) -> i64 {
    if d == 0 {
        return 0;
    }
    let q = n / d;
    let r = n % d;
    if 2 * r.abs() >= d.abs() {
        q + n.signum() * d.signum()
    } else {
        q
    }
}

/// A sensible name for the year starting on `starts_on`: "2025/26" when it
/// crosses a new year, "2026" when it doesn't.
pub fn period_label(starts_on: NaiveDate, ends_on: NaiveDate) -> String {
    use chrono::Datelike;
    if starts_on.year() == ends_on.year() {
        starts_on.year().to_string()
    } else {
        format!("{}/{:02}", starts_on.year(), ends_on.year() % 100)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A real club's 2025/26 and 2024/25 accounts, the figures from its AGM
    /// report. If these stop adding up, the app has started disagreeing with
    /// a treasurer's spreadsheet that balanced.
    struct Example {
        categories: Vec<AccountCategory>,
        club: Uuid,
    }

    impl Example {
        fn new() -> Self {
            let club = Uuid::new_v4();
            let categories = DEFAULT_CATEGORIES
                .iter()
                .enumerate()
                .map(|(i, d)| AccountCategory {
                    id: Uuid::new_v4(),
                    club_id: club,
                    kind: d.kind.as_str().into(),
                    name: d.name.into(),
                    system_key: d.system_key.map(Into::into),
                    sort_order: i as i32,
                    footnote: d.footnote.map(Into::into),
                    archived: false,
                })
                .collect();
            Self { categories, club }
        }

        fn id(&self, kind: &str, name: &str) -> Uuid {
            self.categories
                .iter()
                .find(|c| c.kind == kind && c.name == name)
                .unwrap_or_else(|| panic!("no {kind} category {name}"))
                .id
        }

        fn period(&self, label: &str, start: (i32, u32), opening: i64) -> AccountPeriod {
            AccountPeriod {
                id: Uuid::new_v4(),
                club_id: self.club,
                label: label.into(),
                starts_on: NaiveDate::from_ymd_opt(start.0, start.1, 1).unwrap(),
                ends_on: NaiveDate::from_ymd_opt(start.0 + 1, 9, 30).unwrap(),
                status: "closed".into(),
                currency: "GBP".into(),
                opening_balance_cents: opening,
                report_text: None,
                statement_text: None,
                signed_by_name: None,
                signed_on: None,
                closed_at: None,
                created_at: Utc::now(),
            }
        }

        fn debt(direction: &str, kind: &str, amount: i64, paid_since: i64) -> DebtPosition {
            DebtPosition {
                id: Uuid::new_v4(),
                period_id: Uuid::new_v4(),
                period_label: "2025/26".into(),
                direction: direction.into(),
                kind: kind.into(),
                description: kind.into(),
                counterparty: None,
                member_id: None,
                member_name: None,
                event_id: None,
                raised_on: NaiveDate::from_ymd_opt(2026, 9, 30).unwrap(),
                amount_cents: amount,
                outstanding_at_close_cents: amount,
                paid_since_close_cents: paid_since,
                outstanding_now_cents: amount - paid_since,
                note: None,
            }
        }

        fn year_2025_26(&self) -> ReportInput {
            let i = |n| self.id("income", n);
            let e = |n| self.id("expenditure", n);
            ReportInput {
                period: self.period("2025/26", (2025, 10), 384_659),
                categories: self.categories.clone(),
                category_totals: vec![
                    (i("Indoor net fees"), 64_876),
                    (i("Outdoor match fees"), 254_961),
                    (i("Match/net fees owed"), 33_900),
                    (i("Cost share with other teams"), 62_000),
                    (i("Cost shares owed"), 13_000),
                    (e("Indoor nets"), 112_000),
                    (e("Pitch hire"), 169_250),
                    (e("Cost share with other teams"), 24_500),
                    (e("Losses on previous year recovered debt"), 1_883),
                    // Balls bought this year. The equipment line also carries
                    // the balls used from last year's shelf: 104.94 → 70.85.
                    (e("Equipment purchase"), 34_337),
                    (e("Public liability insurance"), 10_080),
                    (e("Engraving, trophies etc."), 6_000),
                    (e("Food (home games)"), 31_893),
                    (e("Website"), 21_421),
                    (e("Miscellaneous"), 49_000),
                ],
                adjustments_cents: 0,
                extraordinary_expenditure_cents: 49_000,
                extraordinary_income_cents: 0,
                money_accounts: vec![
                    MoneyAccountPosition {
                        id: Uuid::new_v4(),
                        name: "Bank current a/c".into(),
                        kind: "bank".into(),
                        opening_cents: 299_688,
                        computed_closing_cents: 282_546,
                        reconciled_cents: Some(282_546),
                        reconciled_on: NaiveDate::from_ymd_opt(2026, 9, 30),
                    },
                    MoneyAccountPosition {
                        id: Uuid::new_v4(),
                        name: "Credit with nets venue".into(),
                        kind: "supplier_credit".into(),
                        opening_cents: 0,
                        computed_closing_cents: 0,
                        reconciled_cents: Some(0),
                        reconciled_on: NaiveDate::from_ymd_opt(2026, 9, 30),
                    },
                ],
                stock: vec![StockPosition {
                    item_id: Uuid::new_v4(),
                    name: "Unused balls".into(),
                    opening_quantity: 0,
                    opening_cents: 10_494,
                    closing_quantity: 0,
                    closing_cents: 7_085,
                    counted_on: None,
                }],
                debts: vec![
                    Self::debt("debtor", "member_fees", 33_900, 10_850),
                    Self::debt("debtor", "member_fees", 6_100, 0),
                    Self::debt("debtor", "cost_share", 13_000, 0),
                ],
                matches_played: 22,
            }
        }

        fn year_2024_25(&self) -> ReportInput {
            let i = |n| self.id("income", n);
            let e = |n| self.id("expenditure", n);
            ReportInput {
                period: self.period("2024/25", (2024, 10), 324_876),
                categories: self.categories.clone(),
                category_totals: vec![
                    (i("Indoor net fees"), 97_420),
                    (i("Outdoor match fees"), 232_871),
                    (i("Match/net fees owed"), 62_900),
                    (i("Cost share with other teams"), 66_000),
                    (i("Cost shares owed"), 12_000),
                    (e("Indoor nets"), 113_900),
                    (e("Pitch hire"), 194_000),
                    (e("Cost share with other teams"), 23_800),
                    (e("Losses on previous year recovered debt"), 523),
                    (e("Unrecovered debt"), 1_100),
                    (e("Equipment purchase"), 33_982),
                    (e("Public liability insurance"), 10_080),
                    (e("Engraving, trophies etc."), 8_208),
                    (e("Food (home games)"), 12_336),
                    (e("Website"), 13_479),
                ],
                adjustments_cents: 0,
                extraordinary_expenditure_cents: 0,
                extraordinary_income_cents: 0,
                money_accounts: vec![MoneyAccountPosition {
                    id: Uuid::new_v4(),
                    name: "Bank current a/c".into(),
                    kind: "bank".into(),
                    opening_cents: 0,
                    computed_closing_cents: 299_688,
                    reconciled_cents: Some(299_688),
                    reconciled_on: None,
                }],
                stock: vec![StockPosition {
                    item_id: Uuid::new_v4(),
                    name: "Unused balls".into(),
                    opening_quantity: 0,
                    opening_cents: 10_494,
                    closing_quantity: 0,
                    closing_cents: 10_494,
                    counted_on: None,
                }],
                debts: vec![Self::debt("debtor", "member_fees", 74_900, 0)],
                matches_played: 0,
            }
        }
    }

    #[test]
    fn income_and_expenditure_match_the_agm_report() {
        let ex = Example::new();
        let r = build_report(&ex.year_2025_26());
        assert_eq!(r.income_total_cents, 428_737);
        assert_eq!(r.expenditure_total_cents, 463_773);
        assert_eq!(r.surplus_cents, -35_036);

        let equipment = r.expenditure.iter().find(|l| l.name == "Equipment purchase").unwrap();
        assert_eq!(equipment.amount_cents, 37_746, "balls bought plus balls used off the shelf");
        assert_eq!(equipment.stock_adjustment_cents, 3_409);

        let last = build_report(&ex.year_2024_25());
        assert_eq!(last.income_total_cents, 471_191);
        assert_eq!(last.expenditure_total_cents, 411_408);
        assert_eq!(last.surplus_cents, 59_783);
    }

    #[test]
    fn every_line_prints_so_two_years_line_up() {
        let ex = Example::new();
        let r = build_report(&ex.year_2025_26());
        let last = build_report(&ex.year_2024_25());
        let names = |r: &AccountsReport| {
            r.income.iter().chain(&r.expenditure).map(|l| l.name.clone()).collect::<Vec<_>>()
        };
        assert_eq!(names(&r), names(&last));
        assert_eq!(r.income.len(), 8);
        assert_eq!(r.expenditure.len(), 14);
        let sponsorship = r.income.iter().find(|l| l.name == "Sponsorship").unwrap();
        assert_eq!(sponsorship.amount_cents, 0);
    }

    #[test]
    fn footnotes_are_numbered_in_reading_order() {
        let ex = Example::new();
        let r = build_report(&ex.year_2025_26());
        let numbered: Vec<_> = r
            .expenditure
            .iter()
            .filter_map(|l| l.footnote.map(|n| (l.name.as_str(), n)))
            .collect();
        assert_eq!(
            numbered,
            vec![
                ("Losses on previous year recovered debt", 1),
                ("Unrecovered debt", 2),
                ("Equipment purchase", 3),
            ]
        );
        assert_eq!(r.footnotes.len(), 3);
    }

    #[test]
    fn balance_sheet_carries_forward() {
        let ex = Example::new();
        let r = build_report(&ex.year_2025_26());
        let b = &r.balance_sheet;
        assert_eq!(b.brought_forward_cents, 384_659);
        assert_eq!(b.total_cents, 813_396);
        assert_eq!(b.carried_forward_cents, 349_623);

        let last = build_report(&ex.year_2024_25());
        assert_eq!(last.balance_sheet.total_cents, 796_067);
        assert_eq!(last.balance_sheet.carried_forward_cents, 384_659);
        assert_eq!(
            last.balance_sheet.carried_forward_cents,
            b.brought_forward_cents,
            "last year's c/f is this year's b/f"
        );
    }

    #[test]
    fn the_gap_in_the_books_is_shown_not_hidden() {
        let ex = Example::new();
        let r = build_report(&ex.year_2025_26());
        let b = &r.balance_sheet;
        assert_eq!(b.represented_total_cents, 342_631);
        assert_eq!(b.difference_cents, -6_992, "£69.92 short of c/f");
        assert!(b.unreconciled_accounts.is_empty());

        let last = build_report(&ex.year_2024_25());
        assert_eq!(last.balance_sheet.represented_total_cents, 385_082);
        assert_eq!(last.balance_sheet.difference_cents, 423, "£4.23 over c/f");
    }

    #[test]
    fn a_prior_period_adjustment_closes_the_gap() {
        let ex = Example::new();
        let mut input = ex.year_2025_26();
        input.adjustments_cents = -6_992;
        let r = build_report(&input);
        assert_eq!(r.balance_sheet.difference_cents, 0);
        assert_eq!(r.surplus_cents, -35_036, "an adjustment is not trading");
    }

    #[test]
    fn debtors_note_adds_up() {
        let ex = Example::new();
        let r = build_report(&ex.year_2025_26());
        assert_eq!(r.debtors_total_cents, 53_000);
        assert_eq!(r.debtors.len(), 3);
        assert_eq!(r.creditors_total_cents, 0);
        assert_eq!(r.insights.paid_since_close_cents, 10_850);
    }

    #[test]
    fn insights_say_what_the_report_says_in_words() {
        let ex = Example::new();
        let r = build_report(&ex.year_2025_26());
        let i = &r.insights;
        assert_eq!(i.extraordinary_cents, 49_000);
        assert_eq!(i.surplus_excluding_extraordinary_cents, 13_964, "profitable without the one-offs");
        let nets = i.nets.as_ref().unwrap();
        assert_eq!(nets.received_cents, 64_876);
        assert_eq!(nets.cost_cents, 112_000);
        assert_eq!(nets.net_cents, -47_124);
        assert_eq!(i.matches_played, 22);
        assert_eq!(i.match_fee_per_match_cents, Some(11_589), "£2,549.61 / 22 = £115.89");
        assert_eq!(i.equipment_per_match_cents, Some(1_716), "£377.46 / 22 = £17.16");
    }

    #[test]
    fn an_unreconciled_account_is_named() {
        let ex = Example::new();
        let mut input = ex.year_2025_26();
        input.money_accounts[0].reconciled_cents = None;
        input.money_accounts[0].computed_closing_cents = 290_000;
        let r = build_report(&input);
        assert_eq!(r.balance_sheet.unreconciled_accounts, vec!["Bank current a/c".to_string()]);
        let bank = &r.balance_sheet.represented_by[0];
        assert_eq!(bank.amount_cents, 290_000);
        assert_eq!(bank.reconciled, Some(false));
    }

    #[test]
    fn archived_lines_only_print_with_something_in_them() {
        let ex = Example::new();
        let mut input = ex.year_2025_26();
        for c in input.categories.iter_mut() {
            if c.name == "Sponsorship" || c.name == "Website" {
                c.archived = true;
            }
        }
        let r = build_report(&input);
        assert!(!r.income.iter().any(|l| l.name == "Sponsorship"));
        assert!(r.expenditure.iter().any(|l| l.name == "Website"));
    }

    #[test]
    fn only_the_owner_or_a_treasurer_gets_in() {
        assert!(can_open_accounts(true, false));
        assert!(can_open_accounts(false, true));
        assert!(!can_open_accounts(false, false));
    }

    #[test]
    fn a_secretary_cannot_make_themselves_treasurer() {
        // (owner, secretary, self, appointing)
        assert!(can_set_treasurer(true, false, true, true), "an owner may appoint themselves");
        assert!(can_set_treasurer(false, true, false, true), "a secretary appoints somebody else");
        assert!(!can_set_treasurer(false, true, true, true), "but not themselves");
        assert!(can_set_treasurer(false, true, true, false), "stepping down is always allowed");
        assert!(!can_set_treasurer(false, false, false, true), "a member appoints nobody");
    }

    #[test]
    fn labels_and_rounding() {
        let d = |y, m, day| NaiveDate::from_ymd_opt(y, m, day).unwrap();
        assert_eq!(period_label(d(2025, 10, 1), d(2026, 9, 30)), "2025/26");
        assert_eq!(period_label(d(2026, 1, 1), d(2026, 12, 31)), "2026");
        assert_eq!(round_div(254_961, 22), 11_589);
        assert_eq!(round_div(5, 2), 3);
        assert_eq!(round_div(-5, 2), -3);
        assert_eq!(fee_category_key("nets"), keys::NET_FEES);
        assert_eq!(fee_category_key("league_match"), keys::MATCH_FEES);
    }
}
