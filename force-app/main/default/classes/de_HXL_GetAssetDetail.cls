/**
 * de_HXL_GetAssetDetail — Agentforce/MCP invocable action that builds an Asset Detail view from
 * standard Asset data (product, serial, status, price/quantity, install/purchase/usage dates,
 * owning account and contact).
 *
 * Follows the flat-primitive style proven on de_HXL_GetAccount360 / de_HXL_GetCaseDetail: a plain
 * `global class` DTO with `public @InvocableVariable` fields, NO @JsonAccess / @AuraEnabled, and NO
 * nested List<> beyond the admin-configured DetailRow collection — this avoids the HXL v2 server
 * introspection bug that flattens nested Apex List<> into "object" at render time.
 *
 * The lifecycle callout (progress bar + badge) is derived from InstallDate -> UsageEndDate, both
 * stock Asset Date fields, so it works on any org without relying on the optional
 * LifecycleStartDate/LifecycleEndDate subscription fields. When UsageEndDate is absent the whole
 * lifecycle section is hidden (hasLifecycle = false) rather than showing a half-empty bar.
 *
 * Accepts an Asset Id, Asset NAME, or SERIAL NUMBER (resolved on the fly via de_HXL_Resolve).
 *
 * Extra label/value rows come from HXL_Widget_Field__mdt (widget 'AssetDetail', section 'Detail'),
 * edited in Widget Field Settings. With no rows the widget hides that section.
 */
global with sharing class de_HXL_GetAssetDetail {

    public static final String WIDGET = 'AssetDetail';

    @InvocableMethod(label='HXL: Get Asset Detail' description='Returns an Asset detail view for HXL widget rendering. Accepts an Asset name, serial number, or Id.')
    global static List<Response> getDetail(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            Response resp = new Response();
            Id assetId = de_HXL_Resolve.toAssetId(req.assetRef);
            resp.detail = build(assetId);
            results.add(resp);
        }
        return results;
    }

    private static Result build(Id assetId) {
        Result r = new Result();
        r.hasDetails = false; // meta.if input: HXL fails on a missing one, so set it even when nothing matches
        r.hasLifecycle = false;
        if (assetId == null) {
            return r;
        }

        List<Asset> assets = [
            SELECT Id, Name, SerialNumber, Status, Quantity, Price, AssetLevel, Description,
                   InstallDate, PurchaseDate, UsageEndDate,
                   Product2Id, Product2.Name, Product2.ProductCode,
                   AccountId, Account.Name, ContactId, Contact.Name
            FROM Asset
            WHERE Id = :assetId
            WITH USER_MODE
            LIMIT 1
        ];
        if (assets.isEmpty()) {
            return r;
        }
        Asset a = assets[0];

        r.assetName = a.Name;
        r.serialNumber = a.SerialNumber;
        r.status = a.Status;
        r.statusVariant = statusVariant(a.Status);
        r.quantityDisplay = a.Quantity != null ? de_HXL_Format.number(a.Quantity) : '';
        r.priceDisplay = a.Price != null ? '$' + de_HXL_Format.number(a.Price) : '';
        r.assetLevelDisplay = a.AssetLevel != null ? de_HXL_Format.number(a.AssetLevel) : '';
        r.description = a.Description;
        r.installDisplay = a.InstallDate != null ? a.InstallDate.format() : '';
        r.purchaseDisplay = a.PurchaseDate != null ? a.PurchaseDate.format() : '';
        r.usageEndDisplay = a.UsageEndDate != null ? a.UsageEndDate.format() : '';

        if (a.Product2Id != null) {
            r.productName = a.Product2.Name;
            r.productCode = a.Product2.ProductCode;
        }
        if (a.AccountId != null) {
            r.accountName = a.Account.Name;
            r.accountUrl = de_HXL_Format.recordUrl(a.AccountId, 'Account');
        }
        if (a.ContactId != null) {
            r.contactName = a.Contact.Name;
            r.contactInitials = de_HXL_Format.initials(a.Contact.Name);
            r.contactUrl = de_HXL_Format.recordUrl(a.ContactId, 'Contact');
        }
        r.salesforceUrl = de_HXL_Format.recordUrl(a.Id, 'Asset');

        applyLifecycle(r, a);
        applyDetails(r, a.Id);

        return r;
    }

    /**
     * Display-only lifecycle callout derived from InstallDate (start) -> UsageEndDate (end).
     * Shows percent of the warranty/usage window elapsed, plus an Active / Expiring soon / Expired
     * badge. Hidden entirely when there is no UsageEndDate to measure against.
     */
    @TestVisible
    private static void applyLifecycle(Result r, Asset a) {
        if (a.UsageEndDate == null) {
            return;
        }
        Date start = a.InstallDate != null ? a.InstallDate : a.PurchaseDate;
        Date ending = a.UsageEndDate;
        Date today = Date.today();

        Integer daysRemaining = today.daysBetween(ending);
        Boolean expired = daysRemaining < 0;

        Decimal pct;
        if (start != null && start < ending) {
            Integer total = start.daysBetween(ending);
            Integer elapsed = start.daysBetween(today);
            pct = total > 0 ? (Decimal.valueOf(elapsed) / total) * 100 : 100;
        } else {
            // No usable start date: fall back to expired(100)/active(0) so the bar still reads sensibly.
            pct = expired ? 100 : 0;
        }
        if (pct < 0) { pct = 0; }
        if (pct > 100) { pct = 100; }

        // Expiring soon = within 90 days of the usage-end date (and not already expired).
        Boolean expiringSoon = !expired && daysRemaining <= 90;

        r.hasLifecycle = true;
        r.lifecyclePercent = pct.setScale(0);
        r.lifecycleEndDisplay = ending.format();
        r.lifecycleStartDisplay = start != null ? start.format() : '';
        if (expired) {
            r.lifecycleStatus = 'Expired';
            r.lifecycleVariant = 'error';
            r.lifecycleColor = 'error';
            r.lifecycleTitle = 'Lifecycle — expired';
        } else if (expiringSoon) {
            r.lifecycleStatus = 'Expiring soon';
            r.lifecycleVariant = 'warning';
            r.lifecycleColor = 'warning';
            r.lifecycleTitle = 'Lifecycle — ' + daysRemaining + ' days left';
        } else {
            r.lifecycleStatus = 'Active';
            r.lifecycleVariant = 'success';
            r.lifecycleColor = 'success';
            r.lifecycleTitle = 'Lifecycle — active';
        }
    }

    /** Admin-chosen detail rows (HXL_Widget_Field__mdt, widget 'AssetDetail', section 'Detail'). */
    private static void applyDetails(Result r, Id recordId) {
        r.details = new List<DetailRow>();
        List<de_HXL_FieldConfig.Field> fields = de_HXL_FieldConfig.fields(WIDGET, 'Detail', Asset.SObjectType);
        SObject rec = de_HXL_FieldConfig.record(Asset.SObjectType, recordId, fields);
        if (rec != null) {
            for (de_HXL_FieldConfig.Shown s : de_HXL_FieldConfig.shown(rec, fields, '—')) {
                DetailRow row = new DetailRow();
                row.label = s.label;
                row.valueDisplay = s.value;
                row.groupTitle = s.groupTitle;
                row.isGroupStart = s.isGroupStart;
                r.details.add(row);
            }
        }
        r.hasDetails = !r.details.isEmpty();
    }

    /** Badge variant for an Asset Status picklist value. */
    @TestVisible
    private static String statusVariant(String status) {
        if (String.isBlank(status)) {
            return 'secondary';
        }
        String s = status.toLowerCase();
        if (s == 'installed' || s == 'registered') {
            return 'success';
        }
        if (s == 'obsolete') {
            return 'error';
        }
        if (s == 'shipped' || s == 'purchased') {
            return 'info';
        }
        return 'info';
    }

    global class Request {
        @InvocableVariable(required=true label='Asset (name, serial number, or Id)' description='An Asset name, serial number, or a 15/18-char Asset Id.')
        public String assetRef;
    }

    global class Response {
        @InvocableVariable(label='Asset Detail')
        public Result detail;
    }

    global class Result {
        @InvocableVariable public String assetName;
        @InvocableVariable public String serialNumber;
        @InvocableVariable public String status;
        @InvocableVariable public String statusVariant;
        @InvocableVariable public String productName;
        @InvocableVariable public String productCode;
        @InvocableVariable public String quantityDisplay;
        @InvocableVariable public String priceDisplay;
        @InvocableVariable public String assetLevelDisplay;
        @InvocableVariable public String installDisplay;
        @InvocableVariable public String purchaseDisplay;
        @InvocableVariable public String usageEndDisplay;
        @InvocableVariable public Boolean hasLifecycle;
        @InvocableVariable public String lifecycleTitle;
        @InvocableVariable public String lifecycleStatus;
        @InvocableVariable public String lifecycleStartDisplay;
        @InvocableVariable public String lifecycleEndDisplay;
        @InvocableVariable public String lifecycleVariant;
        @InvocableVariable public String lifecycleColor;
        @InvocableVariable public Decimal lifecyclePercent;
        @InvocableVariable public String description;
        @InvocableVariable public String accountName;
        @InvocableVariable public String accountUrl;
        @InvocableVariable public String contactName;
        @InvocableVariable public String contactInitials;
        @InvocableVariable public String contactUrl;
        @InvocableVariable public String salesforceUrl;
        @InvocableVariable public Boolean hasDetails;
        @InvocableVariable public List<DetailRow> details;
    }

    global class DetailRow {
        @InvocableVariable public String label;
        @InvocableVariable public String valueDisplay;
        @InvocableVariable public String groupTitle;
        @InvocableVariable public Boolean isGroupStart;
    }
}
