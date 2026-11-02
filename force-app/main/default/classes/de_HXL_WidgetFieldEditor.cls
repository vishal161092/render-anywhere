/**
 * de_HXL_WidgetFieldEditor — backs the Widget Field Settings tab (c:hxlWidgetFieldEditor). It loads the
 * HXL_Widget_Field__mdt rows for every customizable widget (WIDGETS), describes fields for the
 * pickers, previews unsaved rows against a real record, and saves through an async Metadata API deploy.
 *
 * Access: every method requires the HXL_Widget_Field_Editor custom permission (permission set of the
 * same name). Apex metadata deploys don't check the user's own setup permissions, so this check is
 * the gate. Preview record reads stay USER_MODE (they run through de_HXL_PersonAccountView).
 *
 * Saving is async: the deploy result arrives on the HXL_Widget_Field_Deploy__e platform event, which
 * the editor subscribes to. Custom Metadata can't be deleted from Apex, so rows are switched off
 * (Active__c = false) instead.
 *
 * Account 360 related lists: each slot is an HXL_Related_List__mdt record (ListDef here) and its
 * columns are rows in section List1Column / List2Column, validated against the list's object. Rows
 * and lists save in one deploy.
 */
public with sharing class de_HXL_WidgetFieldEditor {

    public static final String PERMISSION = 'HXL_Widget_Field_Editor';
    private static final String TYPE_NAME = 'HXL_Widget_Field';
    private static final String LIST_TYPE_NAME = 'HXL_Related_List';
    private static final Integer MAX_LISTS = 20;
    private static final Integer MAX_ROWS = 200;
    private static final Integer MAX_HOPS = 3;

    /** Display types that don't render as a single value on the card. */
    private static final Set<Schema.DisplayType> UNSUPPORTED_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.ADDRESS, Schema.DisplayType.LOCATION, Schema.DisplayType.BASE64
    };

    private static final Set<String> FORMATS = new Set<String>{ 'Auto', 'Text', 'Number', 'Currency', 'Percent', 'Date' };
    private static final List<String> COLUMN_TYPES = new List<String>{ 'Text', 'Link', 'Subtitle', 'Badge', 'Image', 'Icon' };
    /** Display types of Summary and Tile rows (Gauge draws a 0-100 bar under the value). */
    private static final List<String> TILE_TYPES = new List<String>{ 'Text', 'Badge', 'Gauge' };
    private static final Set<String> LAYOUTS = new Set<String>{ 'Card', 'Table' };
    private static final Set<String> FILTERS = new Set<String>{ 'All', 'Open', 'FieldEquals' };

    /** Fields saved on each HXL_Widget_Field record. */
    private static final List<String> ROW_FIELDS = new List<String>{
        'Widget__c', 'Section__c', 'Field_API_Name__c', 'Label__c', 'Group__c', 'Format__c', 'Suffix__c',
        'Hide_When_Blank__c', 'Active__c', 'Sort_Order__c', 'Column_Type__c', 'Value_Map__c', 'Fallback__c'
    };

    /** Fields saved on each HXL_Related_List record. */
    private static final List<String> LIST_FIELDS = new List<String>{
        'Widget__c', 'Slot__c', 'Active__c', 'Title__c', 'Icon__c', 'Layout__c', 'Object__c', 'Parent_Field__c',
        'Filter__c', 'Filter_Field__c', 'Filter_Value__c', 'Sort_Field__c', 'Sort_Descending__c', 'Row_Limit__c',
        'Provider_Class__c'
    };

    /** A customizable widget view: one Widget__c value and the sections it reads. */
    public class WidgetDef {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        /** Views that share a card (Person and Business Account 360) share a family. */
        @AuraEnabled public String family;
        @AuraEnabled public String familyLabel;
        @AuraEnabled public String description;
        @AuraEnabled public String iconName;
        /** Object the preview record picker searches. */
        @AuraEnabled public String previewObject;
        @AuraEnabled public List<Section> sections;
        /** DeveloperName prefix for new rows. */
        public String prefix;

        WidgetDef(String name, String label, String family, String familyLabel, String description,
                String iconName, String previewObject, String prefix, List<Section> sections) {
            this.name = name;
            this.label = label;
            this.family = family;
            this.familyLabel = familyLabel;
            this.description = description;
            this.iconName = iconName;
            this.previewObject = previewObject;
            this.prefix = prefix;
            this.sections = sections;
        }
    }

    /** One widget section the editor shows, in card order. */
    public class Section {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String help;
        /** Active rows the widget uses; extra rows are flagged. Null = no limit. */
        @AuraEnabled public Integer maxActive;
        @AuraEnabled public Boolean usesGroup;
        @AuraEnabled public Boolean isImage;
        /** 1 or 2 for the columns of a related list (their object comes from the list); else null. */
        @AuraEnabled public Integer listSlot;
        /** Display types a Summary/Tile row can pick (Column Type); null when the section has none. */
        @AuraEnabled public List<String> tileTypes;
        public SObjectType objType;

        Section(String name, String label, SObjectType objType, String help, Integer maxActive, Boolean usesGroup) {
            this.name = name;
            this.label = label;
            this.objType = objType;
            this.objectApiName = objType == null ? null : String.valueOf(objType);
            this.help = help;
            this.maxActive = maxActive;
            this.usesGroup = usesGroup;
            this.isImage = name == 'DeviceImage';
            this.tileTypes = name == 'Summary' || name == 'Tile' ? TILE_TYPES : null;
        }
    }

    private static final String COLUMN_HELP = 'Columns of this list. The type decides where each shows: '
        + 'Link is the row title, Text a label/value detail (4 on a card, 5 columns in a table).';

    private static Section listColumns(Integer slot) {
        Section s = new Section('List' + slot + 'Column', 'Related List ' + slot + ' Columns', null, COLUMN_HELP, null, false);
        s.listSlot = slot;
        return s;
    }

    private static final String DETAIL_HELP = 'Label/value rows. Rows in a row with the same Group share a heading.';

    public static final List<WidgetDef> WIDGETS = new List<WidgetDef>{
        new WidgetDef(de_HXL_PersonAccountView.WIDGET, 'Person Account', 'Account360', 'Account 360',
            'Account snapshot: KPIs, insight tiles, grouped details, and two related lists.', 'standard:account', 'Account', 'PA_',
            new List<Section>{
                new Section('Summary', 'KPI Strip', Account.SObjectType,
                    'Up to 4 KPIs across the top of the card, under the header.', de_HXL_PersonAccountView.SUMMARY_SLOTS, false),
                new Section('Tile', 'Insight Tiles', Account.SObjectType,
                    'Tiles at the top of the card. The first tile\'s Group becomes the tile heading.', null, true),
                new Section('Detail', 'Details', Account.SObjectType, DETAIL_HELP, null, true),
                listColumns(1),
                listColumns(2)
            }),
        new WidgetDef(de_HXL_PersonAccountView.BUSINESS_WIDGET, 'Business Account', 'Account360', 'Account 360',
            'Account snapshot: KPIs, insight tiles, grouped details, and two related lists.', 'standard:account', 'Account', 'BA_',
            new List<Section>{
                new Section('Summary', 'KPI Strip', Account.SObjectType,
                    'Up to 4 KPIs across the top of the card. Any active row here replaces the built-in strip '
                        + '(ARR, open pipeline, and the demo health score and renewal).',
                    de_HXL_PersonAccountView.SUMMARY_SLOTS, false),
                new Section('Tile', 'Insight Tiles', Account.SObjectType,
                    'Tiles under the KPI strip. The first tile\'s Group becomes the tile heading.', null, true),
                new Section('Detail', 'Details', Account.SObjectType,
                    DETAIL_HELP + ' Shown above the related lists.', null, true),
                listColumns(1),
                listColumns(2)
            }),
        new WidgetDef(de_HXL_GetContactQuickView.WIDGET, 'Contact Quick View', 'ContactQuickView', 'Contact Quick View',
            'Contact card: role, account, contact methods, and recent activity.', 'standard:contact', 'Contact', 'CQV_',
            new List<Section>{
                new Section('Detail', 'Details', Contact.SObjectType,
                    DETAIL_HELP + ' Shown under the email and phone.', null, true)
            }),
        new WidgetDef(de_HXL_GetCaseDetail.WIDGET, 'Case Detail', 'CaseDetail', 'Case Detail',
            'Case with priority, status, SLA, people, description, and related articles.', 'standard:case', 'Case', 'CD_',
            new List<Section>{
                new Section('Detail', 'Details', Case.SObjectType,
                    DETAIL_HELP + ' Shown above the description.', null, true)
            }),
        new WidgetDef(de_HXL_GetOpportunityPipeline.WIDGET, 'Opportunity Pipeline', 'OpportunityPipeline', 'Opportunity Pipeline',
            'A user\'s open pipeline, forecast, quota attainment, and top opportunities.', 'standard:opportunity', 'User', 'OP_',
            new List<Section>{
                new Section('OpportunityDetail', 'Opportunity Details', Opportunity.SObjectType,
                    'Shown under each opportunity\'s name as "Label: value".', 2, false)
            }),
        new WidgetDef(de_HXL_GetAssetDetail.WIDGET, 'Asset Detail', 'AssetDetail', 'Asset Detail',
            'Asset with status, product, lifecycle, account, contact, and description.', 'standard:asset_object', 'Asset', 'AD_',
            new List<Section>{
                new Section('Detail', 'Details', Asset.SObjectType,
                    DETAIL_HELP + ' Shown above the description.', null, true)
            })
    };

    /** One HXL_Widget_Field__mdt row as the editor sees it. */
    public class Row {
        /** Blank for rows added in the editor. */
        @AuraEnabled public String developerName { get; set; }
        /** Widget__c; blank means the Person Account view. */
        @AuraEnabled public String widget { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public String section { get; set; }
        @AuraEnabled public String fieldPath { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String groupTitle { get; set; }
        @AuraEnabled public String format { get; set; }
        @AuraEnabled public String suffix { get; set; }
        @AuraEnabled public Boolean hideWhenBlank { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Decimal sortOrder { get; set; }
        /** Related-list columns only: Text, Link, Subtitle, Badge, Image or Icon. */
        @AuraEnabled public String columnType { get; set; }
        /** `value=result; …` — a badge colour, image URL or icon per field value. */
        @AuraEnabled public String valueMap { get; set; }
        /** Badge colour, image URL or icon used when the field is blank or not in the map. */
        @AuraEnabled public String fallback { get; set; }
        // Read-only, filled by load(): the resolved field and why it can't be used, if it can't.
        @AuraEnabled public String fieldLabel { get; set; }
        @AuraEnabled public String fieldType { get; set; }
        @AuraEnabled public String issue { get; set; }
    }

    /** One HXL_Related_List__mdt record: an Account 360 related list slot. */
    public class ListDef {
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String widget { get; set; }
        @AuraEnabled public Integer slot { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String icon { get; set; }
        @AuraEnabled public String layout { get; set; }
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String parentField { get; set; }
        @AuraEnabled public String filter { get; set; }
        @AuraEnabled public String filterField { get; set; }
        @AuraEnabled public String filterValue { get; set; }
        @AuraEnabled public String sortField { get; set; }
        @AuraEnabled public Boolean sortDescending { get; set; }
        @AuraEnabled public Integer rowLimit { get; set; }
        @AuraEnabled public String providerClass { get; set; }
        /** Read-only, filled by load(): why the widget can't show this list, if it can't. */
        @AuraEnabled public String issue { get; set; }
    }

    /** An object a related list can show: it has a lookup to Account. */
    public class ListObject implements Comparable {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public List<String> parentFields;
        @AuraEnabled public Boolean hasIsClosed;

        public Integer compareTo(Object o) {
            return label.compareTo(((ListObject) o).label);
        }
    }

    public class EditorState {
        @AuraEnabled public List<WidgetDef> widgets;
        @AuraEnabled public List<Row> rows;
        @AuraEnabled public List<String> formats;
        @AuraEnabled public Boolean personAccountsEnabled;
        @AuraEnabled public List<ListDef> lists;
        @AuraEnabled public List<ListObject> listObjects;
        @AuraEnabled public List<String> columnTypes;
        @AuraEnabled public List<String> icons;
    }

    /** A field the picker offers. Lookups also carry their relationship so the picker can hop. */
    public class FieldOption implements Comparable {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public String relationshipName;
        @AuraEnabled public String referenceTo;
        @AuraEnabled public String referenceToLabel;

        public Integer compareTo(Object o) {
            return label.compareTo(((FieldOption) o).label);
        }
    }

    @AuraEnabled
    public static EditorState load() {
        requireAccess();
        EditorState s = new EditorState();
        s.widgets = WIDGETS;
        s.formats = new List<String>{ 'Auto', 'Text', 'Number', 'Currency', 'Percent', 'Date' };
        s.personAccountsEnabled = de_HXL_PersonAccountView.personAccountsEnabled();
        s.columnTypes = COLUMN_TYPES;
        s.icons = new List<String>(de_HXL_RelatedList.ICONS);
        s.icons.sort();
        s.lists = new List<ListDef>();
        for (HXL_Related_List__mdt m : HXL_Related_List__mdt.getAll().values()) {
            if (widget(m.Widget__c) != null) {
                ListDef l = toListDef(m);
                l.issue = listProblem(l, false);
                s.lists.add(l);
            }
        }
        s.listObjects = listObjects();
        Map<String, SObjectType> listTypes = listTypes(s.lists);
        s.rows = new List<Row>();
        for (HXL_Widget_Field__mdt m : HXL_Widget_Field__mdt.getAll().values()) {
            Row r = toRow(m);
            // Rows of retired sections (the old Device* ones) aren't read by any widget any more.
            if (widget(m.Widget__c) != null && section(r) != null) {
                s.rows.add(check(r, listTypes));
            }
        }
        return s;
    }

    /** Readable, queryable objects with a lookup to Account (the related lists' candidates). */
    private static List<ListObject> listObjects() {
        Map<String, ListObject> byName = new Map<String, ListObject>();
        for (Schema.ChildRelationship rel : Account.SObjectType.getDescribe().getChildRelationships()) {
            Schema.DescribeSObjectResult child = rel.getChildSObject().getDescribe();
            Schema.DescribeFieldResult f = rel.getField().getDescribe();
            String name = child.getName();
            if (!child.isAccessible() || !child.isQueryable() || child.isDeprecatedAndHidden()
                    || !f.isAccessible() || !f.isFilterable()
                    || name.endsWith('History') || name.endsWith('Share') || name.endsWith('Feed')
                    || name.endsWith('ChangeEvent')) {
                continue;
            }
            ListObject o = byName.get(name);
            if (o == null) {
                o = new ListObject();
                o.value = name;
                o.label = child.getLabelPlural();
                o.parentFields = new List<String>();
                Schema.SObjectField closed = child.fields.getMap().get('IsClosed');
                o.hasIsClosed = closed != null && closed.getDescribe().isAccessible();
                byName.put(name, o);
            }
            if (!o.parentFields.contains(f.getName())) {
                o.parentFields.add(f.getName());
            }
        }
        List<ListObject> out = byName.values();
        out.sort();
        return out;
    }

    /** Readable fields on `objectApiName`, sorted by label. */
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> describeFields(String objectApiName) {
        requireAccess();
        Schema.DescribeSObjectResult obj = describe(objectApiName);
        if (obj == null || !obj.isAccessible()) {
            throw error('Unknown object: ' + objectApiName);
        }
        List<FieldOption> out = new List<FieldOption>();
        for (Schema.SObjectField f : obj.fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (!d.isAccessible() || UNSUPPORTED_TYPES.contains(d.getType())) {
                continue;
            }
            FieldOption o = new FieldOption();
            o.value = d.getName();
            o.label = d.getLabel();
            o.type = d.getType().name();
            List<Schema.SObjectType> targets = d.getReferenceTo();
            // Polymorphic lookups (e.g. WhatId) can't be walked by a single path, so they stay leaf-only.
            if (String.isNotBlank(d.getRelationshipName()) && targets.size() == 1
                    && targets[0].getDescribe().isAccessible()) {
                o.relationshipName = d.getRelationshipName();
                o.referenceTo = String.valueOf(targets[0]);
                o.referenceToLabel = targets[0].getDescribe().getLabel();
            }
            out.add(o);
        }
        out.sort();
        return out;
    }

    /**
     * Run unsaved `rows` and `lists` through the real code of widget `widgetName` for `recordId`. Returns the
     * widget's Result as JSON (its fields aren't @AuraEnabled), or null when an Account 360 record
     * is the other kind of account (Person vs Business).
     */
    @AuraEnabled
    public static String preview(List<Row> rows, List<ListDef> lists, String widgetName, Id recordId) {
        requireAccess();
        WidgetDef w = widget(widgetName);
        if (w == null) {
            throw error('Unknown widget "' + widgetName + '".');
        }
        if (recordId == null || String.valueOf(recordId.getSObjectType()) != w.previewObject) {
            throw error('Pick a ' + w.previewObject + ' to preview.');
        }
        List<HXL_Widget_Field__mdt> config = new List<HXL_Widget_Field__mdt>();
        for (Row r : rows == null ? new List<Row>() : rows) {
            config.add(toMdt(r));
        }
        de_HXL_FieldConfig.useRows(config);
        List<HXL_Related_List__mdt> listConfig = new List<HXL_Related_List__mdt>();
        for (ListDef l : lists == null ? new List<ListDef>() : lists) {
            listConfig.add(toListMdt(l));
        }
        de_HXL_RelatedList.useLists(listConfig);
        try {
            return previewJson(w.name, recordId);
        } catch (Exception e) {
            throw error('Preview failed: ' + e.getMessage());
        }
    }

    private static String previewJson(String widgetName, Id recordId) {
        String ref = String.valueOf(recordId);
        if (widgetName == de_HXL_PersonAccountView.WIDGET) {
            de_HXL_GetAccount360.Result result = new de_HXL_GetAccount360.Result();
            return de_HXL_PersonAccountView.apply(result, recordId) ? JSON.serialize(result) : null;
        }
        if (widgetName == de_HXL_PersonAccountView.BUSINESS_WIDGET) {
            de_HXL_GetAccount360.Request req = new de_HXL_GetAccount360.Request();
            req.accountRef = ref;
            de_HXL_GetAccount360.Result result = de_HXL_GetAccount360.getSnapshot(
                new List<de_HXL_GetAccount360.Request>{ req })[0].snapshot;
            return result.isBusinessAccount == true ? JSON.serialize(result) : null;
        }
        if (widgetName == de_HXL_GetContactQuickView.WIDGET) {
            de_HXL_GetContactQuickView.Request req = new de_HXL_GetContactQuickView.Request();
            req.contactRef = ref;
            return JSON.serialize(de_HXL_GetContactQuickView.getView(
                new List<de_HXL_GetContactQuickView.Request>{ req })[0].view);
        }
        if (widgetName == de_HXL_GetCaseDetail.WIDGET) {
            de_HXL_GetCaseDetail.Request req = new de_HXL_GetCaseDetail.Request();
            req.caseRef = ref;
            return JSON.serialize(de_HXL_GetCaseDetail.getDetail(
                new List<de_HXL_GetCaseDetail.Request>{ req })[0].detail);
        }
        if (widgetName == de_HXL_GetAssetDetail.WIDGET) {
            de_HXL_GetAssetDetail.Request req = new de_HXL_GetAssetDetail.Request();
            req.assetRef = ref;
            return JSON.serialize(de_HXL_GetAssetDetail.getDetail(
                new List<de_HXL_GetAssetDetail.Request>{ req })[0].detail);
        }
        de_HXL_GetOpportunityPipeline.Request req = new de_HXL_GetOpportunityPipeline.Request();
        req.userRef = ref;
        return JSON.serialize(de_HXL_GetOpportunityPipeline.getPipeline(
            new List<de_HXL_GetOpportunityPipeline.Request>{ req })[0].pipeline);
    }

    /**
     * Validate `rows` and `lists` and deploy the ones that differ from what's saved, in one deploy.
     * Returns the deploy request Id to match against HXL_Widget_Field_Deploy__e, or null when nothing
     * changed.
     */
    @AuraEnabled
    public static Id save(List<Row> rows, List<ListDef> lists) {
        requireAccess();
        rows = rows == null ? new List<Row>() : rows;
        lists = lists == null ? new List<ListDef>() : lists;
        if (rows.size() > MAX_ROWS) {
            throw error('Too many rows (' + rows.size() + '); the limit is ' + MAX_ROWS + '.');
        }
        if (lists.size() > MAX_LISTS) {
            throw error('Too many lists (' + lists.size() + '); the limit is ' + MAX_LISTS + '.');
        }
        // A list slot the user never filled in isn't worth a record.
        List<ListDef> keep = new List<ListDef>();
        for (ListDef l : lists) {
            if (String.isNotBlank(l.developerName) || l.active == true) {
                keep.add(l);
            }
        }
        lists = keep;
        List<String> problems = new List<String>();
        for (ListDef l : lists) {
            String p = listProblem(l, true);
            if (p != null) {
                problems.add(p);
            }
        }
        // Columns check against the incoming lists, falling back to the saved ones.
        List<ListDef> saved = new List<ListDef>();
        for (HXL_Related_List__mdt m : HXL_Related_List__mdt.getAll().values()) {
            saved.add(toListDef(m));
        }
        Map<String, SObjectType> listTypes = listTypes(saved);
        listTypes.putAll(listTypes(lists));
        for (Row r : rows) {
            String p = problem(r, listTypes);
            if (p != null) {
                problems.add(p);
            }
        }
        if (!problems.isEmpty()) {
            throw error(String.join(problems, '\n'));
        }
        Metadata.DeployContainer container = buildContainer(rows, HXL_Widget_Field__mdt.getAll());
        addLists(container, lists, HXL_Related_List__mdt.getAll());
        if (container.getMetadata().isEmpty()) {
            return null;
        }
        return Test.isRunningTest() ? null : Metadata.Operations.enqueueDeployment(container, new DeployHandler());
    }

    /** Custom Metadata for each new or changed row; unchanged rows are left out of the deploy. */
    @TestVisible
    private static Metadata.DeployContainer buildContainer(List<Row> rows, Map<String, HXL_Widget_Field__mdt> saved) {
        Metadata.DeployContainer container = new Metadata.DeployContainer();
        Set<String> taken = new Set<String>();
        for (String name : saved.keySet()) {
            taken.add(name.toLowerCase());
        }
        for (Row r : rows) {
            HXL_Widget_Field__mdt existing = String.isBlank(r.developerName) ? null : saved.get(r.developerName);
            if (existing != null && same(existing, r)) {
                continue;
            }
            String devName = existing != null ? existing.DeveloperName : uniqueName(r, taken);
            Metadata.CustomMetadata md = new Metadata.CustomMetadata();
            md.fullName = TYPE_NAME + '.' + devName;
            // Keep the saved label unless the row moved to another section (it names the section).
            md.label = existing != null && existing.Section__c == r.section ? existing.MasterLabel : masterLabel(r);
            md.protected_x = false;
            addValues(md, toMdt(r), ROW_FIELDS);
            container.addMetadata(md);
        }
        return container;
    }

    /** Add each new or changed list to `container`. */
    @TestVisible
    private static void addLists(Metadata.DeployContainer container, List<ListDef> lists, Map<String, HXL_Related_List__mdt> saved) {
        Set<String> taken = new Set<String>();
        for (String name : saved.keySet()) {
            taken.add(name.toLowerCase());
        }
        for (ListDef l : lists) {
            HXL_Related_List__mdt existing = String.isBlank(l.developerName) ? null : saved.get(l.developerName);
            HXL_Related_List__mdt m = toListMdt(l);
            if (existing != null && same(existing, m, LIST_FIELDS)) {
                continue;
            }
            Metadata.CustomMetadata md = new Metadata.CustomMetadata();
            md.fullName = LIST_TYPE_NAME + '.' + (existing != null ? existing.DeveloperName : uniqueListName(l, taken));
            md.label = listLabel(l);
            md.protected_x = false;
            addValues(md, m, LIST_FIELDS);
            container.addMetadata(md);
        }
    }

    private static void addValues(Metadata.CustomMetadata md, SObject m, List<String> fields) {
        for (String field : fields) {
            Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
            v.field = field;
            v.value = m.get(field);
            md.values.add(v);
        }
    }

    /** Publishes the deploy outcome for the editor's empApi subscription. */
    public class DeployHandler implements Metadata.DeployCallback {
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
            EventBus.publish(toEvent(result));
        }
    }

    @TestVisible
    private static HXL_Widget_Field_Deploy__e toEvent(Metadata.DeployResult result) {
        Boolean ok = result.status == Metadata.DeployStatus.Succeeded;
        List<String> messages = new List<String>();
        if (!ok) {
            if (String.isNotBlank(result.errorMessage)) {
                messages.add(result.errorMessage);
            }
            if (result.details != null && result.details.componentFailures != null) {
                for (Metadata.DeployMessage m : result.details.componentFailures) {
                    messages.add(m.fullName + ': ' + m.problem);
                }
            }
            if (messages.isEmpty()) {
                messages.add('Deploy ended with status ' + result.status);
            }
        }
        return new HXL_Widget_Field_Deploy__e(
            Job_Id__c = result.id,
            Success__c = ok,
            Message__c = String.join(messages, '; ').left(255)
        );
    }

    // ---------------------------------------------------------------------------------------------

    private static void requireAccess() {
        if (!FeatureManagement.checkPermission(PERMISSION)) {
            throw error('Widget Field Settings needs the HXL Widget Field Editor permission set.');
        }
    }

    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message); // Otherwise getMessage() returns "Script-thrown exception".
        return e;
    }

    private static WidgetDef widget(String name) {
        String n = String.isBlank(name) ? de_HXL_PersonAccountView.WIDGET : name;
        for (WidgetDef w : WIDGETS) {
            if (w.name == n) {
                return w;
            }
        }
        return null;
    }

    private static Section section(Row r) {
        WidgetDef w = widget(r.widget);
        for (Section s : w == null ? new List<Section>() : w.sections) {
            if (s.name == r.section) {
                return s;
            }
        }
        return null;
    }

    private static Schema.DescribeSObjectResult describe(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return null;
        }
        try {
            return Schema.describeSObjects(new List<String>{ objectApiName })[0];
        } catch (Exception e) {
            return null;
        }
    }

    /** Object of each list slot, keyed "<widget>:<slot>" (an active list wins over an inactive one). */
    private static Map<String, SObjectType> listTypes(List<ListDef> lists) {
        Map<String, SObjectType> out = new Map<String, SObjectType>();
        Set<String> fromActive = new Set<String>();
        for (ListDef l : lists) {
            String key = widget(l.widget)?.name + ':' + l.slot;
            if (fromActive.contains(key)) {
                continue;
            }
            Schema.DescribeSObjectResult d = describe(l.objectApiName);
            if (d != null && d.isAccessible()) {
                out.put(key, d.getSObjectType());
                if (l.active == true) {
                    fromActive.add(key);
                }
            }
        }
        return out;
    }

    /** The object a row's fields are read from: its section's, or its related list's. */
    private static SObjectType objectFor(Row r, Section s, Map<String, SObjectType> listTypes) {
        return s.listSlot == null ? s.objType : listTypes.get(widget(r.widget).name + ':' + s.listSlot);
    }

    /** A column that shows only its Fallback (a fixed image or icon) needs no field. */
    private static Boolean fallbackOnly(Row r, Section s) {
        return s.listSlot != null && String.isBlank(r.fieldPath) && String.isNotBlank(r.fallback)
            && (r.columnType == 'Image' || r.columnType == 'Icon');
    }

    /** Fill the resolved field label/type, or the reason the row's field can't be used. */
    private static Row check(Row r, Map<String, SObjectType> listTypes) {
        Section s = section(r);
        if (s == null) {
            r.issue = 'Unknown section "' + r.section + '".';
            return r;
        }
        SObjectType objType = objectFor(r, s, listTypes);
        if (objType == null) {
            r.issue = 'Set up the related list (its object) first. The widget skips this column.';
            return r;
        }
        if (fallbackOnly(r, s)) {
            return r;
        }
        Schema.DescribeFieldResult d = String.isBlank(r.fieldPath)
            ? null
            : de_HXL_FieldConfig.resolve(objType, r.fieldPath.trim());
        if (d == null) {
            r.issue = 'Field not found in this org, or you can\'t read it. The widget skips this row.';
            return r;
        }
        r.fieldLabel = d.getLabel();
        r.fieldType = d.getType().name();
        return r;
    }

    /** Why `r` can't be saved, or null. */
    private static String problem(Row r, Map<String, SObjectType> listTypes) {
        String name = String.isNotBlank(r.label) ? r.label : (String.isNotBlank(r.fieldPath) ? r.fieldPath : 'New row');
        if (widget(r.widget) == null) {
            return name + ': unknown widget "' + r.widget + '".';
        }
        Section s = section(r);
        if (s == null) {
            return name + ': unknown section "' + r.section + '".';
        }
        List<String> types = s.listSlot != null ? COLUMN_TYPES : s.tileTypes;
        String columnProblem = types == null ? null : columnProblem(r, types);
        if (columnProblem != null) {
            return name + ' (' + s.label + '): ' + columnProblem;
        }
        if (fallbackOnly(r, s)) {
            return null;
        }
        if (String.isBlank(r.fieldPath)) {
            return name + ' (' + s.label + '): pick a field.';
        }
        if (r.fieldPath.split('\\.').size() > MAX_HOPS + 1) {
            return name + ': field paths can follow at most ' + MAX_HOPS + ' lookups.';
        }
        if (r.active == true && check(r, listTypes).issue != null) {
            SObjectType objType = objectFor(r, s, listTypes);
            return name + ' (' + s.label + '): ' + r.fieldPath + ' isn\'t a readable field on '
                + (objType == null ? 'the list\'s object' : String.valueOf(objType)) + '.';
        }
        if (String.isNotBlank(r.format) && !FORMATS.contains(r.format)) {
            return name + ': unknown format "' + r.format + '".';
        }
        if (tooLong(r.fieldPath, 255) || tooLong(r.label, 80) || tooLong(r.groupTitle, 80) || tooLong(r.suffix, 20)) {
            return name + ': a value is too long (Label and Group 80, Suffix 20 characters).';
        }
        if (r.sortOrder != null && (r.sortOrder < 0 || r.sortOrder > 99999)) {
            return name + ': sort order must be between 0 and 99999.';
        }
        return null;
    }

    /** Column type, value map and fallback checks for a list column or a Summary/Tile row, or null. */
    private static String columnProblem(Row r, List<String> types) {
        String type = String.isBlank(r.columnType) ? 'Text' : r.columnType;
        if (!types.contains(type)) {
            return 'unknown column type "' + r.columnType + '".';
        }
        if (tooLong(r.valueMap, 255) || tooLong(r.fallback, 255)) {
            return 'Value map and Fallback are limited to 255 characters.';
        }
        if (String.isNotBlank(r.fallback)) {
            String f = r.fallback.trim();
            if (type == 'Image' && !de_HXL_RelatedList.isHttps(f)) {
                return 'the fallback image must be an https:// URL.';
            }
            if (type == 'Icon' && de_HXL_RelatedList.iconOrNull(f) == null) {
                return '"' + f + '" isn\'t an icon the widget knows.';
            }
            if (type == 'Badge' && !de_HXL_RelatedList.BADGE_VARIANTS.contains(f.toLowerCase())) {
                return 'the fallback badge colour must be one of ' + String.join(new List<String>(de_HXL_RelatedList.BADGE_VARIANTS), ', ') + '.';
            }
        }
        if (String.isNotBlank(r.valueMap) && (type == 'Badge' || type == 'Image' || type == 'Icon')) {
            for (String v : de_HXL_RelatedList.parseMap(r.valueMap).values()) {
                if (type == 'Image' && !de_HXL_RelatedList.isHttps(v)) {
                    return 'value map image "' + v + '" must be an https:// URL.';
                }
                if (type == 'Icon' && de_HXL_RelatedList.iconOrNull(v) == null) {
                    return 'value map icon "' + v + '" isn\'t an icon the widget knows.';
                }
                if (type == 'Badge' && !de_HXL_RelatedList.BADGE_VARIANTS.contains(v.toLowerCase())) {
                    return 'value map colour "' + v + '" must be one of '
                        + String.join(new List<String>(de_HXL_RelatedList.BADGE_VARIANTS), ', ') + '.';
                }
            }
        }
        return null;
    }

    /**
     * Why list `l` can't be used, or null. With `forSave`, also the problems that block saving
     * (an inactive list may stay half set up).
     */
    private static String listProblem(ListDef l, Boolean forSave) {
        WidgetDef w = widget(l.widget);
        String name = String.isNotBlank(l.title) ? l.title : 'Related list ' + l.slot;
        if (w == null || w.family != 'Account360') {
            return name + ': related lists are only on Account 360.';
        }
        if (l.slot != 1 && l.slot != 2) {
            return name + ': slot must be 1 or 2.';
        }
        if (forSave) {
            if (String.isNotBlank(l.layout) && !LAYOUTS.contains(l.layout)
                    || String.isNotBlank(l.filter) && !FILTERS.contains(l.filter)) {
                return name + ': unknown layout or filter.';
            }
            if (tooLong(l.title, 80) || tooLong(l.icon, 40) || tooLong(l.objectApiName, 80) || tooLong(l.parentField, 80)
                    || tooLong(l.filterField, 255) || tooLong(l.filterValue, 255) || tooLong(l.sortField, 80)
                    || tooLong(l.providerClass, 255)) {
                return name + ': a value is too long.';
            }
            if (l.rowLimit != null && (l.rowLimit < 1 || l.rowLimit > de_HXL_RelatedList.MAX_ROWS)) {
                return name + ': show 1 to ' + de_HXL_RelatedList.MAX_ROWS + ' rows.';
            }
            if (String.isNotBlank(l.icon) && de_HXL_RelatedList.iconOrNull(l.icon) == null) {
                return name + ': "' + l.icon + '" isn\'t an icon the widget knows.';
            }
            if (l.active != true) {
                return null;
            }
        }
        if (String.isNotBlank(l.providerClass)) {
            Type t = Type.forName(l.providerClass.trim());
            Boolean ok = false;
            try {
                ok = t != null && t.newInstance() instanceof de_HXL_RelatedListProvider;
            } catch (Exception e) {
                ok = false;
            }
            return ok ? null : name + ': ' + l.providerClass + ' isn\'t a class implementing de_HXL_RelatedListProvider.';
        }
        HXL_Related_List__mdt m = toListMdt(l);
        Schema.SObjectType objType = de_HXL_RelatedList.objectType(m);
        if (objType == null) {
            return name + ': pick an object you can read.';
        }
        Schema.SObjectField parent = String.isBlank(l.parentField) ? null : objType.getDescribe().fields.getMap().get(l.parentField.trim());
        Schema.DescribeFieldResult pd = parent?.getDescribe();
        if (pd == null || pd.getType() != Schema.DisplayType.REFERENCE || !pd.getReferenceTo().contains(Account.SObjectType)) {
            return name + ': the parent field must be a lookup from ' + objType + ' to Account.';
        }
        if (l.filter == 'FieldEquals' && de_HXL_RelatedList.fieldEquals(m, objType, new Map<String, Object>()) == null) {
            return name + ': the filter needs a filterable field and at least one value.';
        }
        if (String.isNotBlank(l.sortField)) {
            Schema.DescribeFieldResult sd = de_HXL_FieldConfig.resolve(objType, l.sortField.trim());
            if (sd == null || !sd.isSortable()) {
                return name + ': ' + l.sortField + ' isn\'t a sortable field on ' + objType + '.';
            }
        }
        return null;
    }

    private static Boolean tooLong(String v, Integer max) {
        return v != null && v.length() > max;
    }

    private static Row toRow(HXL_Widget_Field__mdt m) {
        Row r = new Row();
        r.developerName = m.DeveloperName;
        r.widget = m.Widget__c;
        r.masterLabel = m.MasterLabel;
        r.section = m.Section__c;
        r.fieldPath = m.Field_API_Name__c;
        r.label = m.Label__c;
        r.groupTitle = m.Group__c;
        r.format = String.isBlank(m.Format__c) ? 'Auto' : m.Format__c;
        r.suffix = m.Suffix__c;
        r.hideWhenBlank = m.Hide_When_Blank__c == true;
        r.active = m.Active__c == true;
        r.sortOrder = m.Sort_Order__c;
        r.columnType = m.Column_Type__c;
        r.valueMap = m.Value_Map__c;
        r.fallback = m.Fallback__c;
        return r;
    }

    private static ListDef toListDef(HXL_Related_List__mdt m) {
        ListDef l = new ListDef();
        l.developerName = m.DeveloperName;
        l.widget = m.Widget__c;
        l.slot = m.Slot__c == null ? null : m.Slot__c.intValue();
        l.active = m.Active__c == true;
        l.title = m.Title__c;
        l.icon = m.Icon__c;
        l.layout = String.isBlank(m.Layout__c) ? 'Card' : m.Layout__c;
        l.objectApiName = m.Object__c;
        l.parentField = m.Parent_Field__c;
        l.filter = String.isBlank(m.Filter__c) ? 'All' : m.Filter__c;
        l.filterField = m.Filter_Field__c;
        l.filterValue = m.Filter_Value__c;
        l.sortField = m.Sort_Field__c;
        l.sortDescending = m.Sort_Descending__c != false;
        l.rowLimit = m.Row_Limit__c == null ? null : m.Row_Limit__c.intValue();
        l.providerClass = m.Provider_Class__c;
        return l;
    }

    private static HXL_Related_List__mdt toListMdt(ListDef l) {
        return new HXL_Related_List__mdt(
            DeveloperName = l.developerName,
            Widget__c = widget(l.widget) != null ? widget(l.widget).name : l.widget,
            Slot__c = l.slot,
            Active__c = l.active == true,
            Title__c = blankToNull(l.title),
            Icon__c = blankToNull(l.icon),
            Layout__c = String.isBlank(l.layout) ? 'Card' : l.layout,
            Object__c = blankToNull(l.objectApiName),
            Parent_Field__c = blankToNull(l.parentField),
            Filter__c = String.isBlank(l.filter) ? 'All' : l.filter,
            Filter_Field__c = blankToNull(l.filterField),
            Filter_Value__c = blankToNull(l.filterValue),
            Sort_Field__c = blankToNull(l.sortField),
            Sort_Descending__c = l.sortDescending != false,
            Row_Limit__c = l.rowLimit,
            Provider_Class__c = blankToNull(l.providerClass)
        );
    }

    private static HXL_Widget_Field__mdt toMdt(Row r) {
        return new HXL_Widget_Field__mdt(
            Widget__c = widget(r.widget) != null ? widget(r.widget).name : r.widget,
            Section__c = r.section,
            Field_API_Name__c = blankToNull(r.fieldPath),
            Label__c = blankToNull(r.label),
            Group__c = blankToNull(r.groupTitle),
            Format__c = String.isBlank(r.format) ? 'Auto' : r.format,
            Suffix__c = blankToNull(r.suffix),
            Hide_When_Blank__c = r.hideWhenBlank == true,
            Active__c = r.active == true,
            Sort_Order__c = r.sortOrder,
            Column_Type__c = blankToNull(r.columnType),
            Value_Map__c = blankToNull(r.valueMap),
            Fallback__c = blankToNull(r.fallback)
        );
    }

    private static String blankToNull(String v) {
        return String.isBlank(v) ? null : v.trim();
    }

    private static Boolean same(HXL_Widget_Field__mdt m, Row r) {
        return same(m, toMdt(r), ROW_FIELDS);
    }

    private static Boolean same(SObject m, SObject incoming, List<String> fields) {
        for (String field : fields) {
            // equals() rather than ==, which ignores case on Strings and would hide a case-only edit.
            if (norm(m.get(field)) != null ? !norm(m.get(field)).equals(norm(incoming.get(field)))
                    : norm(incoming.get(field)) != null) {
                return false;
            }
        }
        return true;
    }

    private static String norm(Object v) {
        if (v instanceof Decimal) {
            return ((Decimal) v).stripTrailingZeros().toPlainString();
        }
        String s = v == null ? null : String.valueOf(v);
        return String.isBlank(s) ? null : s;
    }

    /** e.g. "Details: Annual Revenue" (MasterLabel max 40). */
    private static String masterLabel(Row r) {
        Section s = section(r);
        String name = String.isNotBlank(r.label) ? r.label : r.fieldPath;
        return (s.label + ': ' + name).left(40);
    }

    /** e.g. "Person Account 1: Devices" (MasterLabel max 40). */
    private static String listLabel(ListDef l) {
        String title = String.isNotBlank(l.title) ? l.title : (String.isNotBlank(l.objectApiName) ? l.objectApiName : 'List');
        return (widget(l.widget).label + ' ' + l.slot + ': ' + title).left(40);
    }

    /** <Widget prefix>List<slot>_<Title or object>, made a valid unique DeveloperName (max 40). */
    @TestVisible
    private static String uniqueListName(ListDef l, Set<String> taken) {
        String raw = widget(l.widget).prefix + 'List' + l.slot + '_'
            + (String.isNotBlank(l.title) ? l.title : String.valueOf(l.objectApiName));
        String base = raw.replaceAll('[^A-Za-z0-9]', '_').replaceAll('_+', '_').left(36).removeEnd('_');
        String name = base;
        for (Integer i = 2; taken.contains(name.toLowerCase()); i++) {
            name = base + '_' + i;
        }
        taken.add(name.toLowerCase());
        return name;
    }

    /** <Widget prefix><Section>_<Label or field>, made a valid unique DeveloperName (max 40). */
    @TestVisible
    private static String uniqueName(Row r, Set<String> taken) {
        String raw = widget(r.widget).prefix + r.section + '_' + (String.isNotBlank(r.label) ? r.label : r.fieldPath);
        String base = raw.replaceAll('[^A-Za-z0-9]', '_').replaceAll('_+', '_').left(36).removeEnd('_');
        String name = base;
        for (Integer i = 2; taken.contains(name.toLowerCase()); i++) {
            name = base + '_' + i;
        }
        taken.add(name.toLowerCase());
        return name;
    }
}
