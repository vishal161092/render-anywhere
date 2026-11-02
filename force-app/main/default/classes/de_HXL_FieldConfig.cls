/**
 * de_HXL_FieldConfig — reads the admin-managed HXL_Widget_Field__mdt rows that decide which fields a
 * widget section shows, validates them against the org schema, and formats record values for display.
 *
 * Demo-org behaviour: generated demo records differ from org to org, so field choices live in Custom
 * Metadata (Setup > Custom Metadata Types > HXL Widget Field) instead of code. A row whose field
 * doesn't exist in this org, or that the running user can't read (FLS), is skipped rather than
 * failing the widget — the caller's USER_MODE query then only selects readable fields.
 *
 * Config is read with getAll() (no SOQL, no sharing): it is admin configuration, not user data.
 */
public with sharing class de_HXL_FieldConfig {

    /** Rows used instead of the deployed records (editor preview, tests). */
    private static List<HXL_Widget_Field__mdt> rowsOverride;

    /**
     * Use `rows` instead of the deployed records for the rest of this transaction. The Widget Field
     * Settings preview runs unsaved rows through the real widget code this way; tests use it so
     * coverage doesn't depend on the org's records.
     */
    public static void useRows(List<HXL_Widget_Field__mdt> rows) {
        rowsOverride = rows;
    }

    /** One configured, validated field. */
    public class Field implements Comparable {
        public String path;
        public String label;
        public String groupTitle;
        public String format;
        public String suffix;
        public Boolean hideWhenBlank;
        public Decimal sortOrder;
        public Schema.DisplayType fieldType;
        /** Column Type, Value Map and Fallback as configured (tiles use Gauge/Badge; lists read the rows). */
        public String columnType;
        public String valueMap;
        public String fallback;

        public Integer compareTo(Object o) {
            Field other = (Field) o;
            Decimal a = sortOrder == null ? 0 : sortOrder;
            Decimal b = other.sortOrder == null ? 0 : other.sortOrder;
            return a == b ? 0 : (a < b ? -1 : 1);
        }
    }

    /** Active, valid, user-readable fields for one widget section on `objType`, in sort order. */
    public static List<Field> fields(String widget, String section, Schema.SObjectType objType) {
        List<Field> result = new List<Field>();
        for (HXL_Widget_Field__mdt row : rows()) {
            if (row.Active__c != true || row.Widget__c != widget || row.Section__c != section) {
                continue;
            }
            Field f = toField(row, objType);
            if (f != null) {
                result.add(f);
            }
        }
        result.sort();
        return result;
    }

    /** `row` as a Field on `objType`, or null when its field is blank, not in this org, or not readable. */
    public static Field toField(HXL_Widget_Field__mdt row, Schema.SObjectType objType) {
        if (String.isBlank(row.Field_API_Name__c)) {
            return null;
        }
        String path = row.Field_API_Name__c.trim();
        Schema.DescribeFieldResult d = resolve(objType, path);
        if (d == null) {
            return null;
        }
        Field f = new Field();
        f.path = path;
        f.label = String.isNotBlank(row.Label__c) ? row.Label__c : d.getLabel();
        f.groupTitle = row.Group__c;
        f.format = String.isBlank(row.Format__c) ? 'Auto' : row.Format__c;
        f.suffix = row.Suffix__c;
        f.hideWhenBlank = row.Hide_When_Blank__c == true;
        f.sortOrder = row.Sort_Order__c;
        f.fieldType = d.getType();
        f.columnType = String.isBlank(row.Column_Type__c) ? 'Text' : row.Column_Type__c;
        f.valueMap = row.Value_Map__c;
        f.fallback = String.isBlank(row.Fallback__c) ? null : row.Fallback__c.trim();
        return f;
    }

    /** Every configured row (or the useRows() override), unfiltered. */
    public static List<HXL_Widget_Field__mdt> configRows() {
        return rows();
    }

    /** One field as the widget shows it: label, formatted value, and its group heading. */
    public class Shown {
        public String label;
        public String value;
        public String groupTitle;
        public Boolean isGroupStart;
        /** The configured field and its unformatted value (null when blank). */
        public Field field;
        public Object raw;
    }

    /**
     * `fields` formatted from `rec`, skipping blank hide-when-blank fields. Blank values show as
     * `blank`. A row starts a group when its Group differs from the row before it.
     */
    public static List<Shown> shown(SObject rec, List<Field> fields, String blank) {
        List<Shown> out = new List<Shown>();
        String lastGroup;
        for (Field f : fields) {
            String value = display(rec, f);
            if (String.isBlank(value) && f.hideWhenBlank) {
                continue;
            }
            Shown s = new Shown();
            s.label = f.label;
            s.value = String.isBlank(value) ? blank : value;
            s.groupTitle = f.groupTitle;
            s.isGroupStart = String.isNotBlank(f.groupTitle) && f.groupTitle != lastGroup;
            s.field = f;
            s.raw = String.isBlank(value) ? null : valueAt(rec, f.path);
            lastGroup = f.groupTitle;
            out.add(s);
        }
        return out;
    }

    /**
     * The record `recordId` with `fields` selected (plus Id), read USER_MODE; null when there are no
     * fields or the user can't see the record.
     */
    public static SObject record(Schema.SObjectType objType, Id recordId, List<Field> fields) {
        if (fields.isEmpty() || recordId == null) {
            return null;
        }
        Set<String> selectList = paths(fields);
        selectList.add('id');
        List<SObject> rows = Database.queryWithBinds(
            'SELECT ' + String.join(new List<String>(selectList), ', ')
                + ' FROM ' + objType + ' WHERE Id = :recordId LIMIT 1',
            new Map<String, Object>{ 'recordId' => recordId },
            AccessLevel.USER_MODE
        );
        return rows.isEmpty() ? null : rows[0];
    }

    /** Lowercased select-list paths for the given fields (lowercase avoids duplicate-field errors). */
    public static Set<String> paths(List<Field> fields) {
        Set<String> out = new Set<String>();
        for (Field f : fields) {
            out.add(f.path.toLowerCase());
        }
        return out;
    }

    /** Formatted value of `f` on `rec`, or '' when blank. */
    public static String display(SObject rec, Field f) {
        Object v = valueAt(rec, f.path);
        if (v == null || String.valueOf(v) == '') {
            return '';
        }
        String fmt = f.format == 'Auto' ? autoFormat(f.fieldType) : f.format;
        String out = format(v, fmt);
        if (String.isNotBlank(f.suffix)) {
            String s = f.suffix.trim();
            out += s.left(1).isAlphanumeric() ? ' ' + s : s;
        }
        return out;
    }

    /** Value at a field path such as `Name` or `Product2.Name`; null if any hop is null. */
    public static Object valueAt(SObject rec, String path) {
        List<String> parts = path.split('\\.');
        SObject cur = rec;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            if (cur == null) {
                return null;
            }
            cur = cur.getSObject(parts[i]);
        }
        return cur == null ? null : cur.get(parts[parts.size() - 1]);
    }

    /**
     * Describe for the leaf of `path` on `objType`, or null when any hop is missing or the running
     * user can't read it. Relationship hops use the relationship name (Product2, Account, My_Obj__r).
     */
    public static Schema.DescribeFieldResult resolve(Schema.SObjectType objType, String path) {
        List<String> parts = path.split('\\.');
        Schema.SObjectType cur = objType;
        for (Integer i = 0; i < parts.size(); i++) {
            Map<String, Schema.SObjectField> fieldMap = cur.getDescribe().fields.getMap();
            if (i == parts.size() - 1) {
                Schema.SObjectField leaf = fieldMap.get(parts[i]);
                if (leaf == null) {
                    return null;
                }
                Schema.DescribeFieldResult d = leaf.getDescribe();
                return d.isAccessible() ? d : null;
            }
            Schema.DescribeFieldResult ref = relationship(fieldMap, parts[i]);
            if (ref == null || !ref.isAccessible() || ref.getReferenceTo().isEmpty()) {
                return null;
            }
            cur = ref.getReferenceTo()[0];
        }
        return null;
    }

    /** The lookup field behind a relationship name: tries Foo -> FooId and Foo__r -> Foo__c first. */
    private static Schema.DescribeFieldResult relationship(Map<String, Schema.SObjectField> fieldMap, String name) {
        String guess = name.endsWithIgnoreCase('__r') ? name.left(name.length() - 3) + '__c' : name + 'Id';
        Schema.SObjectField f = fieldMap.get(guess);
        if (f != null && name.equalsIgnoreCase(f.getDescribe().getRelationshipName())) {
            return f.getDescribe();
        }
        for (Schema.SObjectField candidate : fieldMap.values()) {
            Schema.DescribeFieldResult d = candidate.getDescribe();
            if (name.equalsIgnoreCase(d.getRelationshipName())) {
                return d;
            }
        }
        return null;
    }

    private static List<HXL_Widget_Field__mdt> rows() {
        return rowsOverride != null ? rowsOverride : HXL_Widget_Field__mdt.getAll().values();
    }

    @TestVisible
    private static String autoFormat(Schema.DisplayType t) {
        switch on t {
            when PERCENT {
                return 'Percent';
            }
            when CURRENCY {
                return 'Currency';
            }
            when DOUBLE, INTEGER, LONG {
                return 'Number';
            }
            when DATE, DATETIME {
                return 'Date';
            }
            when else {
                return 'Text';
            }
        }
    }

    @TestVisible
    private static String format(Object v, String fmt) {
        if (v instanceof Boolean) {
            return (Boolean) v ? 'Yes' : 'No';
        }
        if (fmt == 'Date' && v instanceof Datetime) {
            // A Date also passes `instanceof Datetime` (only a real Date passes `instanceof Date`);
            // treated as GMT midnight it shows a day early in US time zones, so pin it to local midnight.
            Datetime dt = v instanceof Date
                ? Datetime.newInstance((Date) v, Time.newInstance(0, 0, 0, 0))
                : (Datetime) v;
            return dt.format('MMM d, yyyy');
        }
        Decimal num = toDecimal(v);
        if (num != null) {
            if (fmt == 'Percent') {
                return de_HXL_Format.number(num) + '%';
            }
            if (fmt == 'Currency') {
                return Math.abs(num) >= 1000 ? de_HXL_Format.currencyCompact(num) : '$' + String.valueOf(num.setScale(2));
            }
            if (fmt == 'Number') {
                // Keep one decimal for small fractional values (e.g. 2.4), otherwise thousands-separate.
                return (num.scale() > 0 && Math.abs(num) < 100)
                    ? String.valueOf(num.setScale(1))
                    : de_HXL_Format.number(num);
            }
        }
        return String.valueOf(v);
    }

    private static Decimal toDecimal(Object v) {
        if (v instanceof Decimal) {
            return (Decimal) v;
        }
        if (v instanceof Integer || v instanceof Long || v instanceof Double) {
            return Decimal.valueOf(String.valueOf(v));
        }
        return null;
    }
}
