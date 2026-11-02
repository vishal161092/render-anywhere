/**
 * de_HXL_PersonAccountView — fills the Person Account layout of the Account 360 widget: header,
 * KPI strip, insight tiles and grouped detail rows. Related lists (devices, cases, …) come from de_HXL_RelatedList.
 *
 * Every field shown comes from HXL_Widget_Field__mdt (widget 'PersonAccount360'), so each org's
 * admins can point the tiles and rows at whatever their generated records populate.
 * Works in orgs without Person Accounts: apply() just returns false and the business view runs.
 * Business accounts can add the same tiles and detail rows under widget 'BusinessAccount360'
 * (applyBusinessFields); with no rows the business layout is unchanged.
 * All record reads are USER_MODE.
 */
public with sharing class de_HXL_PersonAccountView {

    public static final String WIDGET = 'PersonAccount360';
    public static final String BUSINESS_WIDGET = 'BusinessAccount360';

    public static Boolean personAccountsEnabled() {
        return Schema.SObjectType.Account.fields.getMap().containsKey('IsPersonAccount');
    }

    /**
     * Populate `r` with the person view when `accountId` is a Person Account the user can read.
     * Returns false (leaving `r` untouched) for business accounts or when Person Accounts are off.
     */
    public static Boolean apply(de_HXL_GetAccount360.Result r, Id accountId) {
        if (!personAccountsEnabled()) {
            return false;
        }
        List<de_HXL_FieldConfig.Field> summary = de_HXL_FieldConfig.fields(WIDGET, 'Summary', Account.SObjectType);
        List<de_HXL_FieldConfig.Field> tiles = de_HXL_FieldConfig.fields(WIDGET, 'Tile', Account.SObjectType);
        List<de_HXL_FieldConfig.Field> details = de_HXL_FieldConfig.fields(WIDGET, 'Detail', Account.SObjectType);

        Set<String> selectList = new Set<String>{ 'id', 'name', 'ispersonaccount', 'owner.name' };
        for (String f : new List<String>{ 'PersonMailingCity', 'PersonMailingState' }) {
            if (de_HXL_FieldConfig.resolve(Account.SObjectType, f) != null) {
                selectList.add(f.toLowerCase());
            }
        }
        selectList.addAll(de_HXL_FieldConfig.paths(summary));
        selectList.addAll(de_HXL_FieldConfig.paths(tiles));
        selectList.addAll(de_HXL_FieldConfig.paths(details));

        List<SObject> rows = Database.queryWithBinds(
            'SELECT ' + String.join(new List<String>(selectList), ', ')
                + ' FROM Account WHERE Id = :accountId LIMIT 1',
            new Map<String, Object>{ 'accountId' => accountId },
            AccessLevel.USER_MODE
        );
        if (rows.isEmpty() || rows[0].get('IsPersonAccount') != true) {
            return false;
        }
        SObject a = rows[0];

        r.isPersonAccount = true;
        r.isBusinessAccount = false;
        r.name = (String) a.get('Name');
        r.tier = 'Person Account';
        r.headerSubtitle = location(a);
        SObject owner = a.getSObject('Owner');
        r.ownerName = owner != null ? (String) owner.get('Name') : '';
        r.ownerInitials = de_HXL_Format.initials(r.ownerName);
        r.salesforceUrl = de_HXL_Format.recordUrl(a.Id, 'Account');

        applySummary(r, a, summary);
        applyTiles(r, a, tiles);
        applyDetails(r, a, details);
        // Devices are now a configurable related list (de_HXL_RelatedList); the old fields stay, unused.
        r.hasDevices = false;
        r.devices = null;
        r.devicesSummary = '';
        de_HXL_RelatedList.apply(r, WIDGET, accountId);
        return true;
    }

    /** KPI strip tiles the business card shows at most. */
    public static final Integer SUMMARY_SLOTS = 4;

    /**
     * Add the BusinessAccount360 summary, tiles and detail rows to a business-account `r`. Leaves `r`
     * untouched when no rows are configured, so the stock business layout shows.
     */
    public static void applyBusinessFields(de_HXL_GetAccount360.Result r, Id accountId) {
        List<de_HXL_FieldConfig.Field> summary = de_HXL_FieldConfig.fields(BUSINESS_WIDGET, 'Summary', Account.SObjectType);
        List<de_HXL_FieldConfig.Field> tiles = de_HXL_FieldConfig.fields(BUSINESS_WIDGET, 'Tile', Account.SObjectType);
        List<de_HXL_FieldConfig.Field> details = de_HXL_FieldConfig.fields(BUSINESS_WIDGET, 'Detail', Account.SObjectType);
        List<de_HXL_FieldConfig.Field> all = new List<de_HXL_FieldConfig.Field>(summary);
        all.addAll(tiles);
        all.addAll(details);
        SObject a = de_HXL_FieldConfig.record(Account.SObjectType, accountId, all);
        if (a == null) {
            return;
        }
        applySummary(r, a, summary);
        applyTiles(r, a, tiles);
        applyDetails(r, a, details);
    }

    /**
     * The KPI strip from Summary rows. On a business account any configured row replaces the built-in
     * strip, even when every one is hidden as blank, so an org can drop its demo-derived health and
     * renewal. Person accounts have no built-in strip.
     */
    private static void applySummary(de_HXL_GetAccount360.Result r, SObject a, List<de_HXL_FieldConfig.Field> summary) {
        if (summary.isEmpty()) {
            return;
        }
        r.hasBuiltInSummary = false;
        r.summaryTiles = new List<de_HXL_GetAccount360.Tile>();
        for (de_HXL_FieldConfig.Shown s : de_HXL_FieldConfig.shown(a, summary, 'N/A')) {
            if (r.summaryTiles.size() == SUMMARY_SLOTS) {
                break;
            }
            r.summaryTiles.add(tile(s));
        }
        r.hasSummary = !r.summaryTiles.isEmpty();
        r.summaryTiles = (List<de_HXL_GetAccount360.Tile>) nullIfEmpty(r.summaryTiles);
    }

    private static void applyTiles(de_HXL_GetAccount360.Result r, SObject a, List<de_HXL_FieldConfig.Field> tiles) {
        r.personTiles = new List<de_HXL_GetAccount360.Tile>();
        r.personTilesTitle = 'Insights';
        // Title from the first configured tile with a group, so it survives that tile being hidden when blank.
        for (de_HXL_FieldConfig.Field f : tiles) {
            if (String.isNotBlank(f.groupTitle)) {
                r.personTilesTitle = f.groupTitle;
                break;
            }
        }
        for (de_HXL_FieldConfig.Shown s : de_HXL_FieldConfig.shown(a, tiles, 'N/A')) {
            r.personTiles.add(tile(s));
        }
        r.hasPersonTiles = !r.personTiles.isEmpty();
        r.personTiles = (List<de_HXL_GetAccount360.Tile>) nullIfEmpty(r.personTiles);
    }

    /** Gauge colour bands on the 0-100 value, matching the business card's health score. */
    @TestVisible
    private static String gaugeVariant(Decimal value) {
        return value >= 75 ? 'success' : (value >= 55 ? 'warning' : 'error');
    }

    /**
     * One tile in its configured style. Gauge needs a number (shown as a 0-100 bar, clamped); Badge
     * colours the value through the Value Map and Fallback. Blank values, and gauges on non-number fields, show as text.
     */
    @TestVisible
    private static de_HXL_GetAccount360.Tile tile(de_HXL_FieldConfig.Shown s) {
        de_HXL_GetAccount360.Tile t = new de_HXL_GetAccount360.Tile();
        t.label = s.label;
        t.valueDisplay = s.value;
        t.showsText = true;
        t.isBadge = false;
        t.badgeVariant = 'secondary';
        t.isGauge = false;
        t.gaugeValue = 0;
        t.gaugeVariant = 'success';
        String type = s.field == null ? 'Text' : s.field.columnType;
        if (s.raw == null) {
            return t;
        }
        if (type == 'Gauge') {
            Decimal n = number(s.raw);
            if (n != null) {
                t.isGauge = true;
                t.gaugeValue = Math.max(0.0, Math.min(100.0, n)).setScale(0, RoundingMode.HALF_UP);
                t.gaugeVariant = gaugeVariant(t.gaugeValue);
            }
        } else if (type == 'Badge') {
            t.showsText = false;
            t.isBadge = true;
            t.badgeVariant = de_HXL_RelatedList.badgeVariant(
                de_HXL_RelatedList.parseMap(s.field.valueMap), s.field.fallback, s.value
            );
        }
        return t;
    }

    private static Decimal number(Object v) {
        if (v instanceof Decimal) {
            return (Decimal) v;
        }
        if (v instanceof Integer || v instanceof Long || v instanceof Double) {
            return Decimal.valueOf(String.valueOf(v));
        }
        return null;
    }

    private static void applyDetails(de_HXL_GetAccount360.Result r, SObject a, List<de_HXL_FieldConfig.Field> details) {
        r.personDetails = new List<de_HXL_GetAccount360.DetailRow>();
        for (de_HXL_FieldConfig.Shown s : de_HXL_FieldConfig.shown(a, details, '—')) {
            de_HXL_GetAccount360.DetailRow row = new de_HXL_GetAccount360.DetailRow();
            row.label = s.label;
            row.valueDisplay = s.value;
            row.groupTitle = s.groupTitle;
            row.isGroupStart = s.isGroupStart;
            r.personDetails.add(row);
        }
        r.hasPersonDetails = !r.personDetails.isEmpty();
        r.personDetails = (List<de_HXL_GetAccount360.DetailRow>) nullIfEmpty(r.personDetails);
    }

    /**
     * Empty widget lists go out as null, like the unused opportunities/contacts lists: HXL renders a null
     * list behind a false meta.if, but an empty one isn't a shape we've seen render (an account with no
     * Assets broke the card).
     */
    private static List<Object> nullIfEmpty(List<Object> items) {
        return items == null || items.isEmpty() ? null : items;
    }

    private static String location(SObject a) {
        List<String> parts = new List<String>();
        for (String f : new List<String>{ 'PersonMailingCity', 'PersonMailingState' }) {
            Object v = a.isSet(f) ? a.get(f) : null;
            if (v != null && String.isNotBlank(String.valueOf(v))) {
                parts.add(String.valueOf(v));
            }
        }
        return String.join(parts, ', ');
    }

}
