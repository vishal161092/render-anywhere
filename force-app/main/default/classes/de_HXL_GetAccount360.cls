/**
 * de_HXL_GetAccount360 — Agentforce/MCP invocable action that builds an Account 360 Snapshot
 * from standard Account data (plus related Contacts / open Opportunities).
 *
 * Rebuilt to match the canonical HotelSearchResult reference bundle exactly:
 *   - Plain `global class` DTOs with `public @InvocableVariable` fields (no @JsonAccess / @AuraEnabled).
 *   - Flat, primitive-only Result — NO nested List<> collections. The related contacts and
 *     opportunities are flattened into fixed slots (top 3 each) so the whole payload is
 *     primitives, exactly like the reference Hotel DTO. This avoids the HXL v2 server
 *     introspection flattening nested Apex List<> into "object", which triggered the
 *     fallback auto-generated widget (and the string-tier-in-meta.if error).
 *   - The output DTO (Result) is referenced by the payload Custom Lightning Type as
 *     @apexClassType/c__HXL_GetAccount360$Result.
 *
 * Person Accounts: when the resolved account IsPersonAccount, de_HXL_PersonAccountView fills the
 * person layout instead (tiles, grouped details, devices — all chosen by admins in
 * HXL_Widget_Field__mdt) and the widget switches sections on isPersonAccount / isBusinessAccount.
 * Business accounts can add tiles and detail rows too (widget 'BusinessAccount360'); they fill the
 * same personTiles / personDetails lists, which the widget shows whenever they're non-empty.
 * Business 'Summary' rows replace the built-in KPI strip (ARR, pipeline, demo health and renewal).
 * Both kinds get two configurable related lists (list1* / list2*) from de_HXL_RelatedList; the
 * contacts / opportunities / devices fields are still filled or kept for compatibility but no
 * longer rendered.
 * Result fields are add-only: a deployed widget schema can't drop attributes.
 */
global with sharing class de_HXL_GetAccount360 {

    @InvocableMethod(label='HXL: Get Account 360 Snapshot' description='Returns an Account 360 snapshot for HXL widget rendering. Accepts an Account name or Id.')
    global static List<Response> getSnapshot(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            Response resp = new Response();
            // Accept a name OR an Id: resolve on the fly so the caller need not know the Id.
            Id accountId = de_HXL_Resolve.toAccountId(req.accountRef);
            resp.snapshot = build(accountId);
            results.add(resp);
        }
        return results;
    }

    private static Result build(Id accountId) {
        Result r = new Result();
        r.isPersonAccount = false;
        r.isBusinessAccount = false;
        // The widget evaluates every meta.if, even for the other account kind, and HXL fails on a
        // function over a missing attr, so expression inputs always go out set.
        r.hasEmployees = false;
        r.hasArrDelta = false;
        r.hasPersonTiles = false;
        r.hasPersonDetails = false;
        r.hasBuiltInSummary = false;
        r.hasSummary = false;
        r.hasDevices = false;
        r.devicesSummary = '';
        r.openPipelineDisplay = '';
        r.openPipelineAmount = '—';
        de_HXL_RelatedList.hideAll(r);
        if (accountId == null) {
            return r;
        }
        if (de_HXL_PersonAccountView.apply(r, accountId)) {
            return r;
        }

        List<Account> accts = [
            SELECT Id, Name, Industry, Rating, AnnualRevenue, NumberOfEmployees,
                   BillingCity, BillingState, Owner.Name
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (accts.isEmpty()) {
            return r;
        }
        Account a = accts[0];

        r.isBusinessAccount = true;
        r.hasBuiltInSummary = true;
        r.name = a.Name;
        r.tier = a.Rating;
        r.headerSubtitle = subtitle(a.Industry, a.BillingCity, a.BillingState);
        r.arrDisplay = de_HXL_Format.currencyCompact(a.AnnualRevenue);
        r.arrDelta = '';
        r.employeesDisplay = de_HXL_Format.number(a.NumberOfEmployees);
        r.hasEmployees = String.isNotBlank(r.employeesDisplay);
        r.hasArrDelta = String.isNotBlank(r.arrDelta);

        // DEMO VALUES: this org has no business-account field for account health or
        // renewal (the SDO_Cust360_* health fields are Person-Account-only, and demo
        // accounts like this are Business Accounts). To match the reference card, health
        // and renewal are derived deterministically from ARR + open pipeline so they are
        // sensible, stable per account, and non-random — clearly labelled as demo-derived,
        // not sourced from a real field.
        Integer health = demoHealth(a.AnnualRevenue);
        r.healthValue = health;
        r.healthDisplay = health + ' / 100';
        r.healthVariant = health >= 75 ? 'success' : (health >= 55 ? 'warning' : 'error');
        // Renewal: a stable future date derived from the account Id, ~9-12 months out.
        Date renewal = demoRenewalDate(a.Id);
        r.renewalDisplay = renewal.format();
        r.renewalStatus = health >= 75 ? 'On track' : (health >= 55 ? 'Monitor' : 'At risk');
        r.renewalVariant = health >= 75 ? 'success' : (health >= 55 ? 'warning' : 'error');
        r.ownerName = a.Owner != null ? a.Owner.Name : '';
        r.ownerInitials = a.Owner != null ? de_HXL_Format.initials(a.Owner.Name) : '';
        r.salesforceUrl = de_HXL_Format.recordUrl(a.Id, 'Account');

        // Top 3 contacts as a nested array (the Playground forEach shape).
        r.contacts = new List<ContactRow>();
        for (Contact ct : [
            SELECT Id, Name, Title, LastActivityDate
            FROM Contact
            WHERE AccountId = :accountId
            WITH USER_MODE
            ORDER BY LastActivityDate DESC NULLS LAST, Name
            LIMIT 3
        ]) {
            ContactRow row = new ContactRow();
            row.name = ct.Name;
            row.title = ct.Title;
            row.initials = de_HXL_Format.initials(ct.Name);
            // Visible text must not be null (HXL fails to render it), so no-activity contacts show a dash.
            row.lastTouch = ct.LastActivityDate != null ? de_HXL_Format.timeAgo(ct.LastActivityDate) : '—';
            r.contacts.add(row);
        }

        // Top 3 open opportunities as a nested array.
        r.opportunities = new List<OpportunityRow>();
        Decimal pipeline = 0;
        for (Opportunity o : [
            SELECT Id, Name, StageName, Amount, CloseDate, Probability
            FROM Opportunity
            WHERE AccountId = :accountId AND IsClosed = false
            WITH USER_MODE
            ORDER BY Amount DESC NULLS LAST
            LIMIT 3
        ]) {
            OpportunityRow row = new OpportunityRow();
            row.name = o.Name;
            row.stageName = o.StageName;
            row.stageVariant = stageVariant(o.Probability);
            row.amountDisplay = de_HXL_Format.currencyCompact(o.Amount);
            row.closeDisplay = o.CloseDate != null ? o.CloseDate.format() : '';
            r.opportunities.add(row);
            if (o.Amount != null) {
                pipeline += o.Amount;
            }
        }
        if (!r.opportunities.isEmpty() && pipeline > 0) {
            r.openPipelineDisplay = de_HXL_Format.currencyCompact(pipeline) + ' pipeline';
        }
        // The KPI tile shows every open opportunity, not just the top 3 listed above.
        AggregateResult[] totals = [
            SELECT SUM(Amount) total
            FROM Opportunity
            WHERE AccountId = :accountId AND IsClosed = false
            WITH USER_MODE
        ];
        Decimal openTotal = totals.isEmpty() ? null : (Decimal) totals[0].get('total');
        if (openTotal != null && openTotal > 0) {
            r.openPipelineAmount = de_HXL_Format.currencyCompact(openTotal);
        }
        de_HXL_PersonAccountView.applyBusinessFields(r, a.Id);
        de_HXL_RelatedList.apply(r, de_HXL_PersonAccountView.BUSINESS_WIDGET, a.Id);

        return r;
    }

    private static String subtitle(String industry, String city, String state) {
        List<String> place = new List<String>();
        if (String.isNotBlank(city)) {
            place.add(city);
        }
        if (String.isNotBlank(state)) {
            place.add(state);
        }
        String loc = String.join(place, ', ');
        List<String> parts = new List<String>();
        if (String.isNotBlank(industry)) {
            parts.add(industry);
        }
        if (String.isNotBlank(loc)) {
            parts.add(loc);
        }
        return parts.isEmpty() ? '' : String.join(parts, ' • ');
    }

    /** Map win probability to a badge/stage color variant. */
    private static String stageVariant(Decimal probability) {
        if (probability == null) {
            return 'secondary';
        }
        if (probability >= 70) {
            return 'success';
        }
        if (probability >= 40) {
            return 'warning';
        }
        return 'info';
    }

    /**
     * DEMO health score (0..100) derived deterministically from ARR.
     * No real business-account health field exists in this org, so this is a stable,
     * sensible demo value: higher ARR -> higher health, floored/capped to a realistic band.
     */
    private static Integer demoHealth(Decimal annualRevenue) {
        Decimal arr = (annualRevenue == null) ? 0 : annualRevenue;
        // Map $0..$100M onto 62..92; cap at 92 so nothing looks unrealistically perfect.
        Decimal scaled = (arr >= 100000000) ? 30 : (arr / 100000000) * 30;
        Integer health = 62 + (Integer) scaled.round();
        if (health > 92) health = 92;
        if (health < 62) health = 62;
        return health;
    }

    /**
     * DEMO renewal date derived deterministically from the account Id, ~9-12 months out,
     * so it is stable per account and non-random. No real renewal field exists in this org.
     */
    private static Date demoRenewalDate(Id accountId) {
        Integer offset = Math.mod(Math.abs(String.valueOf(accountId).hashCode()), 120); // 0..119 days
        return Date.today().addMonths(9).addDays(offset);
    }

    global class Request {
        @InvocableVariable(required=true label='Account (name or Id)' description='An Account name (e.g. "Northwind Traders") or a 15/18-char Account Id.')
        public String accountRef;
    }

    global class Response {
        @InvocableVariable(label='Account 360 Snapshot')
        public Result snapshot;
    }

    global class Result {
        @InvocableVariable public String name;
        @InvocableVariable public String tier;
        @InvocableVariable public String headerSubtitle;
        @InvocableVariable public String arrDisplay;
        @InvocableVariable public String arrDelta;
        @InvocableVariable public String employeesDisplay;
        @InvocableVariable public String healthDisplay;
        @InvocableVariable public Decimal healthValue;
        @InvocableVariable public String healthVariant;
        @InvocableVariable public String renewalDisplay;
        @InvocableVariable public String renewalStatus;
        @InvocableVariable public String renewalVariant;
        @InvocableVariable public String ownerName;
        @InvocableVariable public String ownerInitials;
        @InvocableVariable public String salesforceUrl;
        @InvocableVariable public String openPipelineDisplay;
        @InvocableVariable public List<ContactRow> contacts;
        @InvocableVariable public List<OpportunityRow> opportunities;
        // Person Account view (see de_HXL_PersonAccountView).
        @InvocableVariable public Boolean isPersonAccount;
        @InvocableVariable public Boolean isBusinessAccount;
        @InvocableVariable public String personTilesTitle;
        @InvocableVariable public Boolean hasPersonTiles;
        @InvocableVariable public List<Tile> personTiles;
        @InvocableVariable public Boolean hasPersonDetails;
        @InvocableVariable public List<DetailRow> personDetails;
        @InvocableVariable public Boolean hasDevices;
        @InvocableVariable public String devicesSummary;
        @InvocableVariable public List<DeviceRow> devices;
        @InvocableVariable public Boolean hasEmployees;
        @InvocableVariable public Boolean hasArrDelta;
        @InvocableVariable public String openPipelineAmount;
        // Business KPI strip: the built-in tiles above, or up to 4 admin-configured Summary rows.
        @InvocableVariable public Boolean hasBuiltInSummary;
        @InvocableVariable public Boolean hasSummary;
        @InvocableVariable public List<Tile> summaryTiles;
        // Configurable related lists (see de_HXL_RelatedList), two slots.
        @InvocableVariable public Boolean hasList1;
        @InvocableVariable public Boolean list1IsCard;
        @InvocableVariable public Boolean list1IsTable;
        @InvocableVariable public Boolean list1IsEmpty;
        @InvocableVariable public String list1Title;
        @InvocableVariable public String list1Icon;
        @InvocableVariable public String list1Summary;
        @InvocableVariable public String list1EmptyText;
        @InvocableVariable public List<ListRow> list1Rows;
        @InvocableVariable public List<TableColumn> list1Columns;
        @InvocableVariable public List<TableRow> list1TableRows;
        @InvocableVariable public Boolean hasList2;
        @InvocableVariable public Boolean list2IsCard;
        @InvocableVariable public Boolean list2IsTable;
        @InvocableVariable public Boolean list2IsEmpty;
        @InvocableVariable public String list2Title;
        @InvocableVariable public String list2Icon;
        @InvocableVariable public String list2Summary;
        @InvocableVariable public String list2EmptyText;
        @InvocableVariable public List<ListRow> list2Rows;
        @InvocableVariable public List<TableColumn> list2Columns;
        @InvocableVariable public List<TableRow> list2TableRows;
    }

    /** One card-list row (de_HXL_RelatedList): leading image or icon, linked title, badge, subtitle, 4 details. */
    global class ListRow {
        @InvocableVariable public String title;
        @InvocableVariable public String salesforceUrl;
        @InvocableVariable public String subtitle;
        @InvocableVariable public Boolean hasSubtitle;
        @InvocableVariable public String badgeLabel;
        @InvocableVariable public String badgeVariant;
        @InvocableVariable public Boolean hasBadge;
        @InvocableVariable public String imageUrl;
        @InvocableVariable public Boolean hasImage;
        @InvocableVariable public String iconName;
        @InvocableVariable public Boolean hasIcon;
        @InvocableVariable public String detail1Label;
        @InvocableVariable public String detail1Value;
        @InvocableVariable public Boolean hasDetail1;
        @InvocableVariable public String detail2Label;
        @InvocableVariable public String detail2Value;
        @InvocableVariable public Boolean hasDetail2;
        @InvocableVariable public String detail3Label;
        @InvocableVariable public String detail3Value;
        @InvocableVariable public Boolean hasDetail3;
        @InvocableVariable public String detail4Label;
        @InvocableVariable public String detail4Value;
        @InvocableVariable public Boolean hasDetail4;
    }

    /** A tile/table column: `key` is the TableRow cell (c1..c5). */
    global class TableColumn {
        @InvocableVariable public String key;
        @InvocableVariable public String header;
    }

    /** A tile/table row: formatted cells c1..c5. */
    global class TableRow {
        @InvocableVariable public String c1;
        @InvocableVariable public String c2;
        @InvocableVariable public String c3;
        @InvocableVariable public String c4;
        @InvocableVariable public String c5;
    }

    global class Tile {
        @InvocableVariable public String label;
        @InvocableVariable public String valueDisplay;
        /** Display type flags (exactly one of the value styles shows; always set for the widget). */
        @InvocableVariable public Boolean showsText;
        @InvocableVariable public Boolean isBadge;
        @InvocableVariable public String badgeVariant;
        @InvocableVariable public Boolean isGauge;
        @InvocableVariable public Decimal gaugeValue;
        @InvocableVariable public String gaugeVariant;
    }

    global class DetailRow {
        @InvocableVariable public String label;
        @InvocableVariable public String valueDisplay;
        @InvocableVariable public String groupTitle;
        @InvocableVariable public Boolean isGroupStart;
    }

    global class DeviceRow {
        @InvocableVariable public String title;
        @InvocableVariable public String subtitle;
        @InvocableVariable public String imageUrl;
        @InvocableVariable public Boolean hasImage;
        @InvocableVariable public String salesforceUrl;
        @InvocableVariable public String detail1Label;
        @InvocableVariable public String detail1Value;
        @InvocableVariable public Boolean hasDetail1;
        @InvocableVariable public String detail2Label;
        @InvocableVariable public String detail2Value;
        @InvocableVariable public Boolean hasDetail2;
        @InvocableVariable public String detail3Label;
        @InvocableVariable public String detail3Value;
        @InvocableVariable public Boolean hasDetail3;
        @InvocableVariable public String detail4Label;
        @InvocableVariable public String detail4Value;
        @InvocableVariable public Boolean hasDetail4;
    }

    global class ContactRow {
        @InvocableVariable public String name;
        @InvocableVariable public String title;
        @InvocableVariable public String initials;
        @InvocableVariable public String lastTouch;
    }

    global class OpportunityRow {
        @InvocableVariable public String name;
        @InvocableVariable public String stageName;
        @InvocableVariable public String stageVariant;
        @InvocableVariable public String amountDisplay;
        @InvocableVariable public String closeDisplay;
    }
}
