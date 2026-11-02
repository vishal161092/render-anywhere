/**
 * de_HXL_GetOpportunityPipeline — Agentforce/MCP invocable action that builds an Opportunity
 * Pipeline snapshot (open pipeline, weighted forecast, quota attainment, top open opportunities)
 * for either the logged-in user or a named User.
 *
 * Accepts an optional User NAME (resolved via de_HXL_Resolve.toUserId); a blank userRef defaults to
 * UserInfo.getUserId() so "show me my pipeline" needs no argument.
 *
 * Quota is a DEMO value: no standard Quota/ForecastingQuota data exists for the users in this org,
 * so a stable per-user quarterly quota is derived deterministically from the User Id (same pattern
 * as de_HXL_GetAccount360's demoHealth/demoRenewalDate) — clearly not a real quota field. "Current
 * quarter" here is a calendar quarter (Jan-Mar/Apr-Jun/Jul-Sep/Oct-Dec), not the org's fiscal year
 * settings, since this is demo data.
 *
 * Each opportunity row can show up to two extra "Label: value" lines from HXL_Widget_Field__mdt
 * (widget 'OpportunityPipeline', section 'OpportunityDetail'), edited in Widget Field Settings.
 */
global with sharing class de_HXL_GetOpportunityPipeline {

    public static final String WIDGET = 'OpportunityPipeline';
    private static final Integer TOP_OPP_LIMIT = 5;

    /** Fixed detail slots on each opportunity row (flat fields keep the widget tree simple). */
    private static final Integer DETAIL_SLOTS = 2;

    @InvocableMethod(label='HXL: Get Opportunity Pipeline' description='Returns an Opportunity pipeline snapshot for HXL widget rendering. Accepts an optional User name — leave blank for the logged-in user\'s own pipeline.')
    global static List<Response> getPipeline(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            Response resp = new Response();
            Id userId = String.isNotBlank(req.userRef)
                ? de_HXL_Resolve.toUserId(req.userRef)
                : UserInfo.getUserId();
            resp.pipeline = build(userId);
            results.add(resp);
        }
        return results;
    }

    private static Result build(Id userId) {
        Result r = new Result();
        if (userId == null) {
            return r;
        }

        List<User> users = [
            SELECT Id, Name, Title
            FROM User
            WHERE Id = :userId
            WITH USER_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) {
            return r;
        }
        User u = users[0];

        r.userName = u.Name;
        r.userInitials = de_HXL_Format.initials(u.Name);
        r.userTitle = u.Title != null ? u.Title : ''; // null text fails the HXL render
        r.salesforceUrl = de_HXL_Format.recordUrl(u.Id, 'User');
        r.headerSubtitle = 'Open pipeline for the current quarter';

        // Open opportunities, soonest-to-close first — doubles as the KPI source and the table rows.
        List<de_HXL_FieldConfig.Field> details = de_HXL_FieldConfig.fields(WIDGET, 'OpportunityDetail', Opportunity.SObjectType);
        while (details.size() > DETAIL_SLOTS) {
            details.remove(details.size() - 1);
        }
        Set<String> selectList = new Set<String>{ 'id', 'name', 'stagename', 'amount', 'probability', 'closedate' };
        selectList.addAll(de_HXL_FieldConfig.paths(details));
        List<Opportunity> openOpps = Database.queryWithBinds(
            'SELECT ' + String.join(new List<String>(selectList), ', ')
                + ' FROM Opportunity WHERE OwnerId = :userId AND IsClosed = false'
                + ' ORDER BY CloseDate ASC NULLS LAST LIMIT 200',
            new Map<String, Object>{ 'userId' => userId },
            AccessLevel.USER_MODE
        );

        Decimal openAmount = 0;
        Decimal weighted = 0;
        r.opportunities = new List<OpportunityRow>();
        for (Opportunity o : openOpps) {
            Decimal amt = o.Amount == null ? 0 : o.Amount;
            Decimal prob = o.Probability == null ? 0 : o.Probability;
            openAmount += amt;
            weighted += amt * (prob / 100);

            if (r.opportunities.size() < TOP_OPP_LIMIT) {
                OpportunityRow row = new OpportunityRow();
                row.name = o.Name;
                row.stageName = o.StageName;
                row.stageVariant = stageVariant(o.Probability);
                row.amountDisplay = de_HXL_Format.currencyCompact(amt);
                row.closeDisplay = o.CloseDate != null ? o.CloseDate.format() : '';
                applyDetails(row, o, details);
                r.opportunities.add(row);
            }
        }
        r.openAmountDisplay = de_HXL_Format.currencyCompact(openAmount);
        r.weightedForecastDisplay = de_HXL_Format.currencyCompact(weighted);

        // Closed-won this calendar quarter, compared against the DEMO quota (see class doc).
        Date todayDate = Date.today();
        Date qStart = quarterStart(todayDate);
        Date qEnd = qStart.addMonths(3).addDays(-1);
        Decimal closedWon = 0;
        for (AggregateResult ar : [
            SELECT SUM(Amount) total
            FROM Opportunity
            WHERE OwnerId = :userId AND IsWon = true
                  AND CloseDate >= :qStart AND CloseDate <= :qEnd
            WITH USER_MODE
        ]) {
            Object total = ar.get('total');
            if (total != null) {
                closedWon = (Decimal) total;
            }
        }

        Decimal quota = demoQuarterlyQuota(userId);
        r.quotaDisplay = de_HXL_Format.currencyCompact(quota);
        Decimal attainmentPct = quota > 0 ? (closedWon / quota * 100).setScale(0) : 0;
        r.quotaAttainmentPct = attainmentPct;
        r.quotaAttainmentDisplay = attainmentPct + '% of quota';
        r.quotaAttainmentColor = attainmentPct >= 100 ? 'success' : (attainmentPct >= 60 ? 'warning' : 'error');

        return r;
    }

    /** Fill the detail1/detail2 slots from the configured fields. */
    private static void applyDetails(OpportunityRow row, Opportunity o, List<de_HXL_FieldConfig.Field> details) {
        List<de_HXL_FieldConfig.Shown> shown = de_HXL_FieldConfig.shown(o, details, '—');
        if (shown.size() > 0) {
            row.detail1Label = shown[0].label;
            row.detail1Value = shown[0].value;
        }
        if (shown.size() > 1) {
            row.detail2Label = shown[1].label;
            row.detail2Value = shown[1].value;
        }
        row.hasDetail1 = shown.size() > 0;
        row.hasDetail2 = shown.size() > 1;
    }

    /** Map win probability to a badge/stage color token. */
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

    /** First day of the calendar quarter containing the given date. */
    private static Date quarterStart(Date d) {
        Integer quarterStartMonth = ((d.month() - 1) / 3) * 3 + 1;
        return Date.newInstance(d.year(), quarterStartMonth, 1);
    }

    /**
     * DEMO quarterly quota derived deterministically from the User Id (no real quota field exists
     * in this org). Stable per user, in a realistic $150K-$400K/quarter band for an AE.
     */
    private static Decimal demoQuarterlyQuota(Id userId) {
        Integer offset = Math.mod(Math.abs(String.valueOf(userId).hashCode()), 250000); // 0..249,999
        return 150000 + offset;
    }

    global class Request {
        @InvocableVariable(label='User (name, optional)' description='A User full name (e.g. "Alex Morgan"). Leave blank to use the logged-in user\'s own pipeline.')
        public String userRef;
    }

    global class Response {
        @InvocableVariable(label='Opportunity Pipeline')
        public Result pipeline;
    }

    global class Result {
        @InvocableVariable public String userName;
        @InvocableVariable public String userInitials;
        @InvocableVariable public String userTitle;
        @InvocableVariable public String headerSubtitle;
        @InvocableVariable public String salesforceUrl;
        @InvocableVariable public String openAmountDisplay;
        @InvocableVariable public String weightedForecastDisplay;
        @InvocableVariable public String quotaDisplay;
        @InvocableVariable public String quotaAttainmentDisplay;
        @InvocableVariable public Decimal quotaAttainmentPct;
        @InvocableVariable public String quotaAttainmentColor;
        @InvocableVariable public List<OpportunityRow> opportunities;
    }

    global class OpportunityRow {
        @InvocableVariable public String name;
        @InvocableVariable public String stageName;
        @InvocableVariable public String stageVariant;
        @InvocableVariable public String amountDisplay;
        @InvocableVariable public String closeDisplay;
        @InvocableVariable public String detail1Label;
        @InvocableVariable public String detail1Value;
        @InvocableVariable public Boolean hasDetail1;
        @InvocableVariable public String detail2Label;
        @InvocableVariable public String detail2Value;
        @InvocableVariable public Boolean hasDetail2;
    }
}
