/**
 * de_HXL_RelatedList — builds the two configurable related lists on the Person and Business Account 360
 * cards from HXL_Related_List__mdt (one record per list: object, parent field, filter, sort, limit,
 * Card or Table layout) and its columns, which are HXL_Widget_Field__mdt rows in section
 * List1Column / List2Column of the same widget, each with a Column Type:
 *
 *   Card list: Link = row title (opens the record), Subtitle, Badge (Value Map picks the colour),
 *              Image (https URL from a field, a Value Map, or the Fallback), Icon (Lucide name), and
 *              up to 4 Text columns as label/value details.
 *   Table:     up to 5 columns of text cells; Image and Icon columns are skipped.
 *
 * Every name in the config is checked against describe before it reaches SOQL, filter values are
 * bind variables, and records are read USER_MODE. A list that doesn't validate, or whose query
 * fails, is hidden rather than breaking the card. Provider_Class__c swaps the query for custom code
 * (de_HXL_RelatedListProvider).
 *
 * Output always has every flag set and all visible text non-null; empty lists go out as null.
 */
public with sharing class de_HXL_RelatedList {

    public static final Integer MAX_ROWS = 5;
    public static final Integer CARD_DETAIL_SLOTS = 4;
    public static final Integer TABLE_COLUMNS = 5;
    public static final String DEFAULT_ICON = 'list';

    /** Lucide names tile/icon accepts (hxl-reference/references/icons.md); any other name breaks the widget. */
    public static final Set<String> ICONS = new Set<String>(
        ('activity, alert-circle, alert-triangle, align-center, align-horizontal-space-between, align-left, '
            + 'align-right, align-vertical-space-between, arrow-bottom-left, arrow-bottom-right, arrow-collapse-all, '
            + 'arrow-collapse-down, arrow-collapse-left, arrow-collapse-right, arrow-collapse-up, arrow-down, '
            + 'arrow-expand-all, arrow-expand-down, arrow-expand-left, arrow-expand-right, arrow-expand-up, arrow-left, '
            + 'arrow-right, arrow-top-left, arrow-top-right, arrow-up, arrow-up-down, bell, bookmark, box, braces, '
            + 'briefcase, building, calculator, calendar, caret-down, caret-left, caret-right, caret-up, check, '
            + 'check-circle, chevron-down, chevron-left, chevron-right, chevron-up, circle, circle-dot, clock, cloud, '
            + 'code, component, copy, credit-card, crown, database, dashboard, divide, dollar-sign, dot, download, '
            + 'edit, equal, equal-not, eye, eye-off, file, file-check, file-edit, file-text, filter, folder, gauge, '
            + 'git-branch, git-compare, globe, grid, hash, headset, heart, help-circle, home, image, inbox, info, '
            + 'layers, layout, lightbulb, lightning, link, list, list-checks, list-checks-rtl, loader, lock, mail, map, '
            + 'map-pin, maximize, megaphone, message, microphone, minus, minus-circle, mouse-pointer-click, '
            + 'open-in-new, package, palette, pencil, phone, plane, plus, plus-circle, plug, refresh, repeat, '
            + 'rotate-ccw, rotate-cw, search, send, server, settings, share, shield, shield-alert, shield-check, '
            + 'shopping-cart, space, sparkle, sparkles, square, square-dashed, star, sticky-note, table, tag, target, '
            + 'television, thumb-down, thumb-up, ticket, toggle-left, trash, trending-down, trending-up, upload, user, '
            + 'user-circle, users, video, wifi, x, x-circle').split(', ')
    );

    /** tile/badge variants. */
    public static final Set<String> BADGE_VARIANTS = new Set<String>{
        'primary', 'secondary', 'outline', 'info', 'success', 'warning', 'error'
    };

    private static final Pattern IMG_SRC = Pattern.compile('(?i)src\\s*=\\s*["\'](https://[^"\']+)["\']');

    /** Lists used instead of the deployed records (editor preview, tests). */
    private static List<HXL_Related_List__mdt> listsOverride;

    /** Use `lists` instead of the deployed records for the rest of this transaction (like de_HXL_FieldConfig.useRows). */
    public static void useLists(List<HXL_Related_List__mdt> lists) {
        listsOverride = lists;
    }

    /** One slot as the widget shows it. */
    public class Output {
        public Boolean hasList = false;
        public Boolean isCard = false;
        public Boolean isTable = false;
        public Boolean isEmpty = false;
        public String title = '';
        public String icon = DEFAULT_ICON;
        public String summary = '';
        public String emptyText = '';
        public List<de_HXL_GetAccount360.ListRow> rows;
        public List<de_HXL_GetAccount360.TableColumn> columns;
        public List<de_HXL_GetAccount360.TableRow> tableRows;
    }

    /** One configured column. `field` is null for an Image/Icon column that only uses its Fallback. */
    public class Column implements Comparable {
        public de_HXL_FieldConfig.Field field;
        public String type;
        public String label;
        public Boolean labelSet;
        public Map<String, String> valueMap;
        public String fallback;
        public Decimal sortOrder;

        public Integer compareTo(Object o) {
            Decimal a = sortOrder == null ? 0 : sortOrder;
            Decimal b = ((Column) o).sortOrder == null ? 0 : ((Column) o).sortOrder;
            return a == b ? 0 : (a < b ? -1 : 1);
        }
    }

    /** Fill the list1 and list2 fields on `r` for `widget` (PersonAccount360 / BusinessAccount360). */
    public static void apply(de_HXL_GetAccount360.Result r, String widget, Id accountId) {
        Output one = build(widget, 1, accountId);
        r.hasList1 = one.hasList;
        r.list1IsCard = one.isCard;
        r.list1IsTable = one.isTable;
        r.list1IsEmpty = one.isEmpty;
        r.list1Title = one.title;
        r.list1Icon = one.icon;
        r.list1Summary = one.summary;
        r.list1EmptyText = one.emptyText;
        r.list1Rows = one.rows;
        r.list1Columns = one.columns;
        r.list1TableRows = one.tableRows;

        Output two = build(widget, 2, accountId);
        r.hasList2 = two.hasList;
        r.list2IsCard = two.isCard;
        r.list2IsTable = two.isTable;
        r.list2IsEmpty = two.isEmpty;
        r.list2Title = two.title;
        r.list2Icon = two.icon;
        r.list2Summary = two.summary;
        r.list2EmptyText = two.emptyText;
        r.list2Rows = two.rows;
        r.list2Columns = two.columns;
        r.list2TableRows = two.tableRows;
    }

    /** Set every list flag/text on `r` to the hidden state (meta.if inputs must always be set). */
    public static void hideAll(de_HXL_GetAccount360.Result r) {
        Output none = new Output();
        r.hasList1 = none.hasList;
        r.list1IsCard = none.isCard;
        r.list1IsTable = none.isTable;
        r.list1IsEmpty = none.isEmpty;
        r.list1Title = none.title;
        r.list1Icon = none.icon;
        r.list1Summary = none.summary;
        r.list1EmptyText = none.emptyText;
        r.hasList2 = none.hasList;
        r.list2IsCard = none.isCard;
        r.list2IsTable = none.isTable;
        r.list2IsEmpty = none.isEmpty;
        r.list2Title = none.title;
        r.list2Icon = none.icon;
        r.list2Summary = none.summary;
        r.list2EmptyText = none.emptyText;
    }

    /** The slot's list for `parentId`; a hidden Output when nothing valid is configured. */
    public static Output build(String widget, Integer slot, Id parentId) {
        HXL_Related_List__mdt cfg = config(widget, slot);
        if (cfg == null || parentId == null) {
            return new Output();
        }
        try {
            if (String.isNotBlank(cfg.Provider_Class__c)) {
                return normalize(fromProvider(cfg, parentId));
            }
            return normalize(fromQuery(cfg, columns(widget, slot, cfg), parentId));
        } catch (Exception e) {
            // A bad provider, a filter value of the wrong type, or no access: hide this list, keep the card.
            System.debug(LoggingLevel.WARN, 'de_HXL_RelatedList ' + widget + ' slot ' + slot + ': ' + e.getMessage());
            return new Output();
        }
    }

    /** The active list for the slot (first by DeveloperName if several are active). */
    public static HXL_Related_List__mdt config(String widget, Integer slot) {
        HXL_Related_List__mdt found;
        for (HXL_Related_List__mdt l : lists()) {
            if (l.Active__c == true && l.Widget__c == widget && l.Slot__c == slot
                    && (found == null || l.DeveloperName < found.DeveloperName)) {
                found = l;
            }
        }
        return found;
    }

    /** The slot's object, or null when it isn't in this org or the user can't query it. */
    public static Schema.SObjectType objectType(HXL_Related_List__mdt cfg) {
        if (String.isBlank(cfg.Object__c)) {
            return null;
        }
        Schema.SObjectType t = Schema.getGlobalDescribe().get(cfg.Object__c.trim());
        if (t == null) {
            return null;
        }
        Schema.DescribeSObjectResult d = t.getDescribe();
        return d.isAccessible() && d.isQueryable() ? t : null;
    }

    /** Configured, readable columns for the slot, in sort order. */
    public static List<Column> columns(String widget, Integer slot, HXL_Related_List__mdt cfg) {
        List<Column> out = new List<Column>();
        Schema.SObjectType objType = objectType(cfg);
        if (objType == null) {
            return out;
        }
        String section = 'List' + slot + 'Column';
        for (HXL_Widget_Field__mdt row : de_HXL_FieldConfig.configRows()) {
            if (row.Active__c != true || row.Widget__c != widget || row.Section__c != section) {
                continue;
            }
            Column c = new Column();
            c.type = String.isBlank(row.Column_Type__c) ? 'Text' : row.Column_Type__c;
            c.field = de_HXL_FieldConfig.toField(row, objType);
            c.fallback = String.isBlank(row.Fallback__c) ? null : row.Fallback__c.trim();
            Boolean visual = c.type == 'Image' || c.type == 'Icon';
            if (c.field == null && !(visual && c.fallback != null)) {
                continue; // Unreadable or missing field, and nothing to show instead.
            }
            c.labelSet = String.isNotBlank(row.Label__c);
            c.label = c.labelSet ? row.Label__c : (c.field != null ? c.field.label : '');
            c.valueMap = parseMap(row.Value_Map__c);
            c.sortOrder = row.Sort_Order__c;
            out.add(c);
        }
        out.sort();
        return out;
    }

    @TestVisible
    private static Output fromQuery(HXL_Related_List__mdt cfg, List<Column> cols, Id parentId) {
        Schema.SObjectType objType = objectType(cfg);
        if (objType == null) {
            return new Output();
        }
        Schema.DescribeSObjectResult od = objType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = od.fields.getMap();
        String parentField = parentField(cfg, fieldMap);
        if (parentField == null) {
            return new Output();
        }
        Boolean isTable = cfg.Layout__c == 'Table';

        Map<String, Object> binds = new Map<String, Object>{ 'parentId' => parentId };
        List<String> whereParts = new List<String>{ parentField + ' = :parentId' };
        if (cfg.Filter__c == 'Open') {
            Schema.SObjectField closed = fieldMap.get('IsClosed');
            if (closed != null && closed.getDescribe().isAccessible()) {
                whereParts.add('IsClosed = false');
            }
        } else if (cfg.Filter__c == 'FieldEquals') {
            String clause = fieldEquals(cfg, objType, binds);
            if (clause == null) {
                return new Output(); // A filter we can't apply would show the wrong records.
            }
            whereParts.add(clause);
        }
        String whereClause = ' FROM ' + od.getName() + ' WHERE ' + String.join(whereParts, ' AND ');

        Set<String> selectList = new Set<String>{ 'id' };
        Boolean hasName = de_HXL_FieldConfig.resolve(objType, 'Name') != null;
        if (hasName) {
            selectList.add('name');
        }
        for (Column c : cols) {
            if (c.field != null) {
                selectList.add(c.field.path.toLowerCase());
            }
        }
        Integer lim = cfg.Row_Limit__c == null ? MAX_ROWS : Math.max(1, Math.min(MAX_ROWS, cfg.Row_Limit__c.intValue()));
        binds.put('lim', lim);

        List<SObject> records = Database.queryWithBinds(
            'SELECT ' + String.join(new List<String>(selectList), ', ') + whereClause
                + orderBy(cfg, objType) + ' LIMIT :lim',
            binds,
            AccessLevel.USER_MODE
        );
        Integer total = Database.countQueryWithBinds('SELECT COUNT()' + whereClause, binds, AccessLevel.USER_MODE);

        Output out = new Output();
        out.hasList = true;
        out.title = String.isNotBlank(cfg.Title__c) ? cfg.Title__c : od.getLabelPlural();
        out.icon = iconOrNull(cfg.Icon__c) != null ? iconOrNull(cfg.Icon__c) : DEFAULT_ICON;
        String noun = (total == 1 ? od.getLabel() : od.getLabelPlural()).toLowerCase();
        out.summary = total > records.size()
            ? 'Showing ' + records.size() + ' of ' + total
            : total + ' ' + noun;
        if (records.isEmpty()) {
            out.isEmpty = true;
            out.emptyText = 'No ' + out.title.toLowerCase();
            return out;
        }
        if (isTable) {
            out.isTable = true;
            table(out, records, cols);
        } else {
            out.isCard = true;
            out.rows = new List<de_HXL_GetAccount360.ListRow>();
            for (SObject rec : records) {
                out.rows.add(card(rec, cols, od.getName(), hasName));
            }
        }
        return out;
    }

    /** The parent field: a readable, filterable lookup on the list's object that points at Account. */
    private static String parentField(HXL_Related_List__mdt cfg, Map<String, Schema.SObjectField> fieldMap) {
        if (String.isBlank(cfg.Parent_Field__c)) {
            return null;
        }
        Schema.SObjectField f = fieldMap.get(cfg.Parent_Field__c.trim());
        if (f == null) {
            return null;
        }
        Schema.DescribeFieldResult d = f.getDescribe();
        Boolean pointsAtAccount = d.getType() == Schema.DisplayType.REFERENCE
            && d.getReferenceTo().contains(Account.SObjectType);
        return pointsAtAccount && d.isAccessible() && d.isFilterable() ? d.getName() : null;
    }

    /** `Field = :value` / `Field IN :values` for a FieldEquals filter, typed to the field; null when invalid. */
    public static String fieldEquals(HXL_Related_List__mdt cfg, Schema.SObjectType objType, Map<String, Object> binds) {
        if (String.isBlank(cfg.Filter_Field__c) || cfg.Filter_Value__c == null) {
            return null;
        }
        String path = cfg.Filter_Field__c.trim();
        Schema.DescribeFieldResult d = de_HXL_FieldConfig.resolve(objType, path);
        if (d == null || !d.isFilterable()) {
            return null;
        }
        List<String> raw = new List<String>();
        for (String v : cfg.Filter_Value__c.split(',')) {
            if (String.isNotBlank(v)) {
                raw.add(v.trim());
            }
        }
        if (raw.isEmpty()) {
            return null;
        }
        switch on d.getType() {
            when BOOLEAN {
                binds.put('filterValue', Boolean.valueOf(raw[0]));
                return path + ' = :filterValue';
            }
            when DOUBLE, INTEGER, LONG, CURRENCY, PERCENT {
                List<Decimal> values = new List<Decimal>();
                for (String v : raw) {
                    values.add(Decimal.valueOf(v));
                }
                binds.put('filterValues', values);
            }
            when DATE {
                List<Date> values = new List<Date>();
                for (String v : raw) {
                    values.add(Date.valueOf(v));
                }
                binds.put('filterValues', values);
            }
            when DATETIME, TEXTAREA, ENCRYPTEDSTRING, BASE64, LOCATION, ADDRESS {
                return null; // Not an equality filter we support.
            }
            when else {
                binds.put('filterValues', raw);
            }
        }
        return path + ' IN :filterValues';
    }

    /** ORDER BY the configured sortable field, else CreatedDate, else nothing. */
    private static String orderBy(HXL_Related_List__mdt cfg, Schema.SObjectType objType) {
        String dir = cfg.Sort_Descending__c == false ? ' ASC NULLS LAST' : ' DESC NULLS LAST';
        if (String.isNotBlank(cfg.Sort_Field__c)) {
            String path = cfg.Sort_Field__c.trim();
            Schema.DescribeFieldResult d = de_HXL_FieldConfig.resolve(objType, path);
            if (d != null && d.isSortable()) {
                return ' ORDER BY ' + path + dir;
            }
        }
        return de_HXL_FieldConfig.resolve(objType, 'CreatedDate') != null ? ' ORDER BY CreatedDate DESC' : '';
    }

    @TestVisible
    private static de_HXL_GetAccount360.ListRow card(SObject rec, List<Column> cols, String objectName, Boolean hasName) {
        de_HXL_GetAccount360.ListRow row = new de_HXL_GetAccount360.ListRow();
        row.title = '';
        row.subtitle = '';
        row.hasSubtitle = false;
        row.badgeLabel = '';
        row.badgeVariant = 'secondary';
        row.hasBadge = false;
        row.imageUrl = '';
        row.hasImage = false;
        row.iconName = DEFAULT_ICON;
        row.hasIcon = false;
        row.salesforceUrl = de_HXL_Format.recordUrl(rec.Id, objectName);

        List<String> labels = new List<String>();
        List<String> values = new List<String>();
        for (Column c : cols) {
            String value = c.field != null ? de_HXL_FieldConfig.display(rec, c.field) : '';
            switch on c.type {
                when 'Link' {
                    if (String.isBlank(row.title)) {
                        row.title = value;
                    }
                }
                when 'Subtitle' {
                    if (!row.hasSubtitle && String.isNotBlank(value)) {
                        row.subtitle = c.labelSet ? c.label + ': ' + value : value;
                        row.hasSubtitle = true;
                    }
                }
                when 'Badge' {
                    if (!row.hasBadge && String.isNotBlank(value)) {
                        row.badgeLabel = value;
                        row.badgeVariant = badgeVariant(c, value);
                        row.hasBadge = true;
                    }
                }
                when 'Image' {
                    if (!row.hasImage) {
                        String url = imageUrl(c, c.field != null ? de_HXL_FieldConfig.valueAt(rec, c.field.path) : null);
                        row.hasImage = url != null;
                        row.imageUrl = url != null ? url : '';
                    }
                }
                when 'Icon' {
                    if (!row.hasIcon) {
                        String icon = iconFor(c, value);
                        row.hasIcon = icon != null;
                        row.iconName = icon != null ? icon : DEFAULT_ICON;
                    }
                }
                when else {
                    if (labels.size() < CARD_DETAIL_SLOTS && !(String.isBlank(value) && c.field.hideWhenBlank)) {
                        labels.add(c.label);
                        values.add(String.isBlank(value) ? '—' : value);
                    }
                }
            }
        }
        // An image wins over an icon: the row has one leading visual.
        row.hasIcon = row.hasIcon && !row.hasImage;
        if (String.isBlank(row.title)) {
            row.title = hasName && rec.get('Name') != null ? String.valueOf(rec.get('Name')) : String.valueOf(rec.Id);
        }
        while (labels.size() < CARD_DETAIL_SLOTS) {
            labels.add(null);
            values.add(null);
        }
        row.detail1Label = labels[0];
        row.detail1Value = values[0];
        row.hasDetail1 = labels[0] != null;
        row.detail2Label = labels[1];
        row.detail2Value = values[1];
        row.hasDetail2 = labels[1] != null;
        row.detail3Label = labels[2];
        row.detail3Value = values[2];
        row.hasDetail3 = labels[2] != null;
        row.detail4Label = labels[3];
        row.detail4Value = values[3];
        row.hasDetail4 = labels[3] != null;
        return row;
    }

    /** Table columns c1..c5 (Image/Icon skipped) and their cells, already formatted. */
    @TestVisible
    private static void table(Output out, List<SObject> records, List<Column> cols) {
        List<Column> shown = new List<Column>();
        for (Column c : cols) {
            if (c.field != null && c.type != 'Image' && c.type != 'Icon' && shown.size() < TABLE_COLUMNS) {
                shown.add(c);
            }
        }
        out.columns = new List<de_HXL_GetAccount360.TableColumn>();
        for (Integer i = 0; i < shown.size(); i++) {
            de_HXL_GetAccount360.TableColumn col = new de_HXL_GetAccount360.TableColumn();
            col.key = 'c' + (i + 1);
            col.header = shown[i].label;
            out.columns.add(col);
        }
        out.tableRows = new List<de_HXL_GetAccount360.TableRow>();
        for (SObject rec : records) {
            List<String> cells = new List<String>();
            for (Column c : shown) {
                String v = de_HXL_FieldConfig.display(rec, c.field);
                cells.add(String.isBlank(v) ? '—' : v);
            }
            while (cells.size() < TABLE_COLUMNS) {
                cells.add('');
            }
            de_HXL_GetAccount360.TableRow tr = new de_HXL_GetAccount360.TableRow();
            tr.c1 = cells[0];
            tr.c2 = cells[1];
            tr.c3 = cells[2];
            tr.c4 = cells[3];
            tr.c5 = cells[4];
            out.tableRows.add(tr);
        }
        if (out.columns.isEmpty()) {
            // No readable columns: show it as empty rather than a headerless table.
            out.isTable = false;
            out.isEmpty = true;
            out.emptyText = 'No columns to show';
            out.columns = null;
            out.tableRows = null;
        }
    }

    /** Value Map colour for `value` (case-insensitive), else a valid Fallback, else secondary. */
    @TestVisible
    private static String badgeVariant(Column c, String value) {
        return badgeVariant(c.valueMap, c.fallback, value);
    }

    /** Badge colour for `value` from a parsed Value Map and Fallback (also used by Badge tiles). */
    public static String badgeVariant(Map<String, String> valueMap, String fallback, String value) {
        String mapped = value == null ? null : valueMap.get(value.trim().toLowerCase());
        if (mapped != null && BADGE_VARIANTS.contains(mapped.toLowerCase())) {
            return mapped.toLowerCase();
        }
        if (fallback != null && BADGE_VARIANTS.contains(fallback.toLowerCase())) {
            return fallback.toLowerCase();
        }
        return 'secondary';
    }

    /**
     * Image URL for a raw field value: the first https src of rich text, or the value itself; through
     * the Value Map when one is set (keyed by the value); else the Fallback. Only https URLs are
     * returned (Slack loads the image itself, so it must be public https); null for none.
     */
    @TestVisible
    private static String imageUrl(Column c, Object raw) {
        String v = raw == null ? null : String.valueOf(raw).trim();
        if (v != null && v.contains('<')) {
            Matcher m = IMG_SRC.matcher(v);
            v = m.find() ? m.group(1) : null;
        }
        if (!c.valueMap.isEmpty()) {
            v = v == null ? null : c.valueMap.get(v.toLowerCase());
        }
        if (!isHttps(v)) {
            v = c.fallback;
        }
        return isHttps(v) ? v.unescapeHtml4() : null;
    }

    /** Icon for `value`: through the Value Map when set, else the value; Fallback when not a known icon. */
    @TestVisible
    private static String iconFor(Column c, String value) {
        String v = String.isBlank(value) ? null : value.trim();
        if (!c.valueMap.isEmpty()) {
            v = v == null ? null : c.valueMap.get(v.toLowerCase());
        }
        String icon = iconOrNull(v);
        return icon != null ? icon : iconOrNull(c.fallback);
    }

    public static Boolean isHttps(String v) {
        return v != null && v.startsWithIgnoreCase('https://') && !v.containsWhitespace() && v.length() > 8;
    }

    public static String iconOrNull(String name) {
        if (String.isBlank(name)) {
            return null;
        }
        String n = name.trim().toLowerCase();
        return ICONS.contains(n) ? n : null;
    }

    /** `Installed=success; Registered=info` → lowercased key → value. Splits on the first '=' only. */
    public static Map<String, String> parseMap(String spec) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(spec)) {
            return out;
        }
        for (String pair : spec.split(';')) {
            Integer eq = pair.indexOf('=');
            if (eq > 0) {
                String key = pair.left(eq).trim().toLowerCase();
                String value = pair.substring(eq + 1).trim();
                if (String.isNotBlank(key) && String.isNotBlank(value)) {
                    out.put(key, value);
                }
            }
        }
        return out;
    }

    private static Output fromProvider(HXL_Related_List__mdt cfg, Id parentId) {
        Type t = Type.forName(cfg.Provider_Class__c.trim());
        if (t == null) {
            return new Output();
        }
        Object instance = t.newInstance();
        if (!(instance instanceof de_HXL_RelatedListProvider)) {
            return new Output();
        }
        return ((de_HXL_RelatedListProvider) instance).build(cfg, parentId);
    }

    /**
     * Enforce the widget's rules on any Output (provider output included): flags set, text non-null,
     * icon valid, one layout, rows/columns capped, and empty lists as null.
     */
    @TestVisible
    private static Output normalize(Output o) {
        if (o == null || o.hasList != true) {
            return new Output();
        }
        o.isCard = o.isCard == true;
        o.isTable = o.isTable == true && !o.isCard;
        o.title = o.title == null ? '' : o.title;
        o.icon = iconOrNull(o.icon) != null ? iconOrNull(o.icon) : DEFAULT_ICON;
        o.summary = o.summary == null ? '' : o.summary;
        if (o.rows != null) {
            while (o.rows.size() > MAX_ROWS) {
                o.rows.remove(o.rows.size() - 1);
            }
            for (de_HXL_GetAccount360.ListRow row : o.rows) {
                normalizeRow(row);
            }
        }
        if (o.tableRows != null) {
            while (o.tableRows.size() > MAX_ROWS) {
                o.tableRows.remove(o.tableRows.size() - 1);
            }
        }
        if (o.columns != null) {
            while (o.columns.size() > TABLE_COLUMNS) {
                o.columns.remove(o.columns.size() - 1);
            }
        }
        Boolean hasRows = o.isCard ? o.rows != null && !o.rows.isEmpty()
            : o.isTable && o.tableRows != null && !o.tableRows.isEmpty() && o.columns != null && !o.columns.isEmpty();
        if (!hasRows) {
            o.isCard = false;
            o.isTable = false;
            o.isEmpty = true;
        } else {
            o.isEmpty = false;
        }
        if (!o.isCard) {
            o.rows = null;
        }
        if (!o.isTable) {
            o.columns = null;
            o.tableRows = null;
        }
        o.emptyText = String.isNotBlank(o.emptyText) ? o.emptyText : (o.isEmpty ? 'No ' + o.title.toLowerCase() : '');
        return o;
    }

    private static void normalizeRow(de_HXL_GetAccount360.ListRow row) {
        row.title = row.title == null ? '' : row.title;
        row.salesforceUrl = row.salesforceUrl == null ? '' : row.salesforceUrl;
        row.subtitle = row.subtitle == null ? '' : row.subtitle;
        row.hasSubtitle = row.hasSubtitle == true && String.isNotBlank(row.subtitle);
        row.badgeLabel = row.badgeLabel == null ? '' : row.badgeLabel;
        row.badgeVariant = row.badgeVariant != null && BADGE_VARIANTS.contains(row.badgeVariant) ? row.badgeVariant : 'secondary';
        row.hasBadge = row.hasBadge == true && String.isNotBlank(row.badgeLabel);
        row.hasImage = row.hasImage == true && isHttps(row.imageUrl);
        row.imageUrl = row.hasImage ? row.imageUrl : '';
        row.hasIcon = row.hasIcon == true && !row.hasImage && iconOrNull(row.iconName) != null;
        row.iconName = row.hasIcon ? iconOrNull(row.iconName) : DEFAULT_ICON;
        row.hasDetail1 = row.hasDetail1 == true && row.detail1Label != null && row.detail1Value != null;
        row.hasDetail2 = row.hasDetail2 == true && row.detail2Label != null && row.detail2Value != null;
        row.hasDetail3 = row.hasDetail3 == true && row.detail3Label != null && row.detail3Value != null;
        row.hasDetail4 = row.hasDetail4 == true && row.detail4Label != null && row.detail4Value != null;
        // Text behind a false meta.if still goes out set, never null.
        row.detail1Label = row.detail1Label == null ? '' : row.detail1Label;
        row.detail1Value = row.detail1Value == null ? '' : row.detail1Value;
        row.detail2Label = row.detail2Label == null ? '' : row.detail2Label;
        row.detail2Value = row.detail2Value == null ? '' : row.detail2Value;
        row.detail3Label = row.detail3Label == null ? '' : row.detail3Label;
        row.detail3Value = row.detail3Value == null ? '' : row.detail3Value;
        row.detail4Label = row.detail4Label == null ? '' : row.detail4Label;
        row.detail4Value = row.detail4Value == null ? '' : row.detail4Value;
    }

    private static List<HXL_Related_List__mdt> lists() {
        return listsOverride != null ? listsOverride : HXL_Related_List__mdt.getAll().values();
    }
}
