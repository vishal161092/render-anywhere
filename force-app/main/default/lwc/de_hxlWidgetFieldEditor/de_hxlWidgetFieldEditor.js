import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import load from '@salesforce/apex/de_HXL_WidgetFieldEditor.load';
import preview from '@salesforce/apex/de_HXL_WidgetFieldEditor.preview';
import save from '@salesforce/apex/de_HXL_WidgetFieldEditor.save';

const DEPLOY_CHANNEL = '/event/HXL_Widget_Field_Deploy__e';
const SAVE_TIMEOUT_MS = 120000;
const ORDER_STEP = 10;
const PERSON_WIDGET = 'PersonAccount360';
const BUSINESS_WIDGET = 'BusinessAccount360';

/** Row properties sent back to Apex (de_HXL_WidgetFieldEditor.Row). */
const PAYLOAD_FIELDS = [
    'developerName',
    'widget',
    'masterLabel',
    'section',
    'fieldPath',
    'label',
    'groupTitle',
    'format',
    'suffix',
    'hideWhenBlank',
    'active',
    'sortOrder',
    'columnType',
    'valueMap',
    'fallback'
];

/** Related list properties sent back to Apex (de_HXL_WidgetFieldEditor.ListDef). */
const LIST_PAYLOAD_FIELDS = [
    'developerName',
    'widget',
    'slot',
    'active',
    'title',
    'icon',
    'layout',
    'objectApiName',
    'parentField',
    'filter',
    'filterField',
    'filterValue',
    'sortField',
    'sortDescending',
    'rowLimit',
    'providerClass'
];

const NUMERIC_TYPES = new Set(['DOUBLE', 'INTEGER', 'LONG', 'CURRENCY', 'PERCENT']);
const DATE_TYPES = new Set(['DATE', 'DATETIME']);
const TEXT_TYPES = new Set(['STRING', 'URL', 'TEXTAREA']);

/** Column types a table can show (as text cells); cards show every type. Matches de_HXL_RelatedList. */
const TABLE_TYPES = new Set(['Text', 'Link', 'Subtitle', 'Badge']);
const VISUAL_TYPES = new Set(['Image', 'Icon']);
const CARD_DETAIL_SLOTS = 4;
const TABLE_COLUMNS = 5;
const MAX_LIST_ROWS = 5;

const LAYOUT_OPTIONS = [
    { label: 'Card list', value: 'Card' },
    { label: 'Table', value: 'Table' }
];
const SORT_OPTIONS = [
    { label: 'Descending', value: 'desc' },
    { label: 'Ascending', value: 'asc' }
];
const LIMIT_OPTIONS = Array.from({ length: MAX_LIST_ROWS }, (_, i) => ({
    label: String(i + 1),
    value: String(i + 1)
}));

/** What Value Map and Fallback hold for each column type. */
const COLUMN_HINTS = {
    Badge: { map: 'Installed=success; Obsolete=error', fallback: 'secondary' },
    Image: { map: 'Panel=https://…/panel.png', fallback: 'https://…/default.png' },
    Icon: { map: 'Server=server; Phone=phone', fallback: 'box' }
};

/** Column header and list setting help. Keep in step with de_HXL_FieldConfig and de_HXL_RelatedList. */
const HELP = {
    tileType: 'How the value shows: Text as a large value, Badge as a coloured pill (Value map and Fallback pick the colour), Gauge as the value with a 0-100 bar under it.',
    type: 'What the column does on a card row: Link is the row title, Subtitle the line under it, Badge a coloured pill, Image or Icon the leading visual, Text a label/value detail.',
    field: 'A field on this object, or a lookup path such as Owner.Name or Product2.Name. Fields the viewing user can\'t read are skipped without an error.',
    format: 'Auto picks from the field type. Currency shows $8.4M style above 1,000, Date shows Oct 14, 2026, and checkboxes show Yes or No.',
    suffix: 'Added after the value. A suffix that starts with a letter or digit gets a space (kW gives 8.7 kW); a symbol doesn\'t (% gives 25%).',
    valueMap: 'value=result pairs separated by semicolons. Badge: a colour. Image: an https URL. Icon: an icon name. Matching ignores case.',
    fallback: 'Used when the field is blank or its value isn\'t in the Value map. Badge: a colour. Image: an https URL. Icon: an icon name.',
    hide: 'On: a blank value drops the row. Off: it shows a dash.',
    group: 'Group heading. A new heading starts whenever the Group differs from the row above.',
    parentField: 'The lookup on this object that points at the account. The list shows the records whose lookup is the account on the card.',
    filter: 'Open only drops closed records (offered for objects with IsClosed). Field equals value keeps records whose field matches.',
    filterValue: 'Comma-separate several values. Picklists compare their API value, not the label.',
    headerIcon: 'Shown next to the list title. Only these names render in the widget.'
};

const FIELD_TIPS = [
    {
        key: 'paths',
        title: 'Field paths',
        text: 'Follow a lookup with its relationship name: Owner.Name, Product2.Name, or My_Object__r.My_Field__c. Person account fields end in __pc on Account.'
    },
    {
        key: 'access',
        title: 'Missing in Slack?',
        text: 'The widgets read records as the viewing user, so a field they can\'t read is skipped without an error. Give users read access to every custom field you add here, for example with a permission set.'
    },
    {
        key: 'blank',
        title: 'Blank values',
        text: 'Hide if blank drops the row when the value is empty; otherwise it shows a dash. Turn it on for fields that are often empty in demo data.'
    }
];

const GROUP_TIP = {
    key: 'groups',
    title: 'Groups',
    text: 'A heading starts whenever the Group differs from the row above, so keep a group\'s rows next to each other in Order.'
};

const TILE_TIP = {
    key: 'tileTypes',
    title: 'Badges and gauges',
    text: 'Badge colours the value through the Value map (Gold=success; Silver=info) and the Fallback colour, else secondary. Gauge needs a number field and draws a 0-100 bar: green from 75, amber from 55, red below. Blank values show as plain text.'
};

const LIST_TIPS = [
    {
        key: 'card',
        title: 'Card rows',
        text: 'The first non-blank Link is the row title and opens the record (no Link: the record Name). The first non-blank Subtitle goes under it; with a Label it reads "Label: value". Up to 4 Text columns show as details.'
    },
    {
        key: 'badge',
        title: 'Status badges',
        text: 'Value map: Installed=success; Shipped=warning. Colours: primary, secondary, outline, info, success, warning, error. The match uses the value as shown: picklists use their API value, and Format and Suffix apply first (with Suffix kW, map 8 kW). No match: the Fallback colour, else secondary.'
    },
    {
        key: 'image',
        title: 'Images',
        text: 'Slack loads the image itself, so it needs a public https URL. Point at a URL or rich text field (its first image), for example Product2.Image_URL__c, or map values to URLs. An image wins over an icon on the same row.'
    },
    {
        key: 'icon',
        title: 'Icons',
        text: 'The value, or its Value map result, must be an icon name from the Header icon list (Server=server). Anything else uses the Fallback icon, then none.'
    },
    {
        key: 'table',
        title: 'Tables',
        text: 'A table shows up to 5 text columns; Image and Icon columns are skipped. Every list shows at most 5 rows.'
    },
    FIELD_TIPS[1]
];

let keySeq = 0;

function pick(item, fields) {
    const out = {};
    fields.forEach((f) => {
        out[f] = item[f] === undefined || item[f] === '' ? null : item[f];
    });
    return out;
}

function payload(row) {
    return pick(row, PAYLOAD_FIELDS);
}

function snapshot(row) {
    return JSON.stringify(payload(row));
}

function listPayload(list) {
    return pick(list, LIST_PAYLOAD_FIELDS);
}

function listSnapshot(list) {
    return JSON.stringify(listPayload(list));
}

/** A row has a value to show: a field, or (Image/Icon columns) just a Fallback. */
function hasSource(row) {
    return !!row.fieldPath || (VISUAL_TYPES.has(row.columnType) && !!row.fallback);
}

function isDirty(item, snap) {
    return item.original === null || snap(item) !== item.original;
}

/** A slot with no saved list yet: off until the admin switches it on. */
function blankList(widget, slot) {
    const list = {
        key: `${widget}-list-${slot}`,
        developerName: null,
        widget,
        slot,
        active: false,
        title: null,
        icon: 'list',
        layout: 'Card',
        objectApiName: null,
        parentField: null,
        filter: 'All',
        filterField: null,
        filterValue: null,
        sortField: null,
        sortDescending: true,
        rowLimit: MAX_LIST_ROWS,
        providerClass: null
    };
    return { ...list, original: listSnapshot(list) };
}

/** The list a slot shows: the active one, like de_HXL_RelatedList.config. */
function slotList(lists, widget, slot) {
    const inSlot = lists.filter((l) => l.widget === widget && l.slot === slot);
    return inSlot.find((l) => l.active) || inSlot[0];
}

/**
 * Why an active list column won't show, or null. `counts` tracks the columns before it. Repeats of
 * the other card types are fine: the first one with a value wins, so later ones are backups.
 */
function columnWarning(row, layout, counts) {
    const type = row.columnType || 'Text';
    if (layout === 'Table') {
        if (VISUAL_TYPES.has(type)) {
            return "Tables don't show images or icons; this column is skipped.";
        }
        counts.shown++;
        return counts.shown > TABLE_COLUMNS ? `A table shows ${TABLE_COLUMNS} columns; this one is ignored.` : null;
    }
    if (type !== 'Text') {
        return null;
    }
    counts.text++;
    return counts.text > CARD_DETAIL_SLOTS ? `A card shows ${CARD_DETAIL_SLOTS} Text details; this one is ignored.` : null;
}

function byOrder(a, b) {
    const diff = (a.sortOrder ?? 0) - (b.sortOrder ?? 0);
    return diff !== 0 ? diff : (a.label || a.fieldPath || '').localeCompare(b.label || b.fieldPath || '');
}

function reduceError(e) {
    return e?.body?.message || e?.message || 'Something went wrong.';
}

/** Why the chosen format or field type won't render well, or null. */
function formatWarning(row, section) {
    const type = row.fieldType;
    if (!type) {
        return null;
    }
    const isImage = section.isImage || (section.listSlot && row.columnType === 'Image');
    if (isImage && !row.valueMap && !TEXT_TYPES.has(type)) {
        return 'The image needs a text or URL field that holds the image address.';
    }
    if (['Number', 'Currency', 'Percent'].includes(row.format) && !NUMERIC_TYPES.has(type)) {
        return `${row.format} format needs a number field; this one is ${type.toLowerCase()}.`;
    }
    if (row.format === 'Date' && !DATE_TYPES.has(type)) {
        return `Date format needs a date field; this one is ${type.toLowerCase()}.`;
    }
    return null;
}

/**
 * Widget Field Settings: a guarded editor for HXL_Widget_Field__mdt. It opens on a gallery of the
 * customizable widgets; a card opens that widget's sections (Account 360 switches between its Person
 * and Business views). Pickers come from describe data, the preview runs unsaved rows through the
 * real widget Apex, and Save deploys every changed row, across widgets. Gated by the
 * HXL_Widget_Field_Editor custom permission (on the tab and in Apex).
 */
export default class HxlWidgetFieldEditor extends LightningElement {
    loading = true;
    loadError;
    widgetDefs = [];
    /** Widget__c of the open widget; undefined shows the gallery. */
    activeWidgetName;
    formatOptions = [];
    help = HELP;
    personAccountsEnabled = false;
    rows = [];
    /** HXL_Related_List records, plus a blank one for each empty Account 360 slot. */
    lists = [];
    listObjects = [];
    columnTypes = [];
    iconOptions = [];

    saving = false;
    saveJobId;
    saveTimer;
    deployEvents = new Map();
    subscription;

    previewAccountId;
    previewResult;
    previewMessage;
    previewLoading = false;
    previewCollapsed = false;

    dragKey;
    dropSection;

    connectedCallback() {
        this.reload();
        this.subscribeToDeploys();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {});
        }
        clearTimeout(this.saveTimer);
    }

    // ----- loading ---------------------------------------------------------------------------

    async reload() {
        this.loading = true;
        try {
            const state = await load();
            this.widgetDefs = state.widgets;
            this.formatOptions = state.formats.map((f) => ({ label: f, value: f }));
            this.personAccountsEnabled = state.personAccountsEnabled;
            this.rows = state.rows.map((r) => {
                const row = { ...r, widget: r.widget || PERSON_WIDGET };
                return { ...row, key: r.developerName, original: snapshot(row) };
            });
            this.listObjects = state.listObjects || [];
            this.columnTypes = state.columnTypes || [];
            this.iconOptions = (state.icons || []).map((i) => ({ label: i, value: i }));
            const lists = (state.lists || []).map((l) => ({
                ...l,
                key: l.developerName,
                original: listSnapshot(l)
            }));
            state.widgets.forEach((w) => {
                (w.sections || [])
                    .filter((s) => s.listSlot)
                    .forEach((s) => {
                        if (!slotList(lists, w.name, s.listSlot)) {
                            lists.push(blankList(w.name, s.listSlot));
                        }
                    });
            });
            this.lists = lists;
            this.loadError = undefined;
        } catch (e) {
            this.loadError = reduceError(e);
        } finally {
            this.loading = false;
        }
    }

    subscribeToDeploys() {
        onError(() => {
            // Without the channel the save still completes; the timeout message covers it.
        });
        Promise.resolve(subscribe(DEPLOY_CHANNEL, -1, (message) => this.handleDeployEvent(message)))
            .then((sub) => {
                this.subscription = sub;
            })
            .catch(() => {});
    }

    // ----- view model ------------------------------------------------------------------------

    layoutOptions = LAYOUT_OPTIONS;
    sortOptions = SORT_OPTIONS;
    limitOptions = LIMIT_OPTIONS;

    get ready() {
        return !this.loading && !this.loadError;
    }

    get dirtyRows() {
        return this.rows.filter((r) => isDirty(r, snapshot));
    }

    get dirtyLists() {
        return this.lists.filter((l) => isDirty(l, listSnapshot));
    }

    get dirtyCount() {
        return this.dirtyRows.length + this.dirtyLists.length;
    }

    get hasChanges() {
        return this.dirtyCount > 0;
    }

    get saveLabel() {
        return this.hasChanges ? `Save (${this.dirtyCount})` : 'Save';
    }

    get saveDisabled() {
        return !this.hasChanges || this.saving;
    }

    get discardDisabled() {
        return !this.hasChanges || this.saving;
    }

    // ----- preview panel ---------------------------------------------------------------------

    get editorBodyClass() {
        return this.previewCollapsed ? 'editor-body editor-body--collapsed' : 'editor-body';
    }

    get previewExpanded() {
        return String(!this.previewCollapsed);
    }

    get previewToggleIcon() {
        return this.previewCollapsed ? 'utility:chevronleft' : 'utility:chevronright';
    }

    get previewToggleLabel() {
        return this.previewCollapsed ? 'Show preview' : 'Hide preview';
    }

    handleTogglePreview() {
        this.previewCollapsed = !this.previewCollapsed;
    }

    // ----- gallery ---------------------------------------------------------------------------

    get showGallery() {
        return !this.activeWidgetName;
    }

    /** One card per widget family, in WIDGETS order. */
    get cards() {
        const cards = [];
        this.widgetDefs.forEach((def) => {
            let card = cards.find((c) => c.family === def.family);
            if (!card) {
                card = {
                    family: def.family,
                    label: def.familyLabel,
                    description: def.description,
                    iconName: def.iconName,
                    widgets: [],
                    activeCount: 0,
                    dirtyCount: 0
                };
                cards.push(card);
            }
            const rows = this.rows.filter((r) => r.widget === def.name);
            card.widgets.push(def.label);
            card.activeCount += rows.filter((r) => r.active).length;
            card.dirtyCount += rows.filter((r) => isDirty(r, snapshot)).length;
            card.dirtyCount += this.lists.filter((l) => l.widget === def.name && isDirty(l, listSnapshot)).length;
        });
        return cards.map((c) => ({
            ...c,
            hasVariants: c.widgets.length > 1,
            variantText: c.widgets.join(' · '),
            activeText:
                c.activeCount === 0
                    ? 'Not customized yet'
                    : `${c.activeCount} active field${c.activeCount === 1 ? '' : 's'}`,
            hasDirty: c.dirtyCount > 0,
            dirtyText: `${c.dirtyCount} unsaved`
        }));
    }

    handleOpenCard(event) {
        const family = event.currentTarget.dataset.family;
        const first = this.widgetDefs.find((w) => w.family === family);
        if (first) {
            this.openWidget(first.name);
        }
    }

    handleCardKey(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleOpenCard(event);
        }
    }

    handleBack() {
        this.openWidget(undefined);
    }

    handleVariantChange(event) {
        this.openWidget(event.detail.value);
    }

    openWidget(name) {
        this.activeWidgetName = name;
        this.previewAccountId = undefined;
        this.previewResult = undefined;
        this.previewMessage = undefined;
    }

    get activeWidget() {
        return this.widgetDefs.find((w) => w.name === this.activeWidgetName);
    }

    get activeSections() {
        return this.activeWidget?.sections || [];
    }

    get variantOptions() {
        const family = this.activeWidget?.family;
        return this.widgetDefs
            .filter((w) => w.family === family)
            .map((w) => ({ label: w.label, value: w.name }));
    }

    get hasVariants() {
        return this.variantOptions.length > 1;
    }

    get editorTitle() {
        const w = this.activeWidget;
        return w ? w.familyLabel : '';
    }

    // ----- preview picker --------------------------------------------------------------------

    get isPersonView() {
        return this.activeWidgetName === PERSON_WIDGET;
    }

    get previewUnavailable() {
        return this.isPersonView && !this.personAccountsEnabled;
    }

    get previewObject() {
        return this.activeWidget?.previewObject;
    }

    get previewLabel() {
        if (this.isPersonView) {
            return 'Person Account';
        }
        if (this.activeWidgetName === BUSINESS_WIDGET) {
            return 'Business Account';
        }
        return this.previewObject;
    }

    get previewPlaceholder() {
        return `Search ${this.previewLabel}s…`;
    }

    get previewFilter() {
        if (this.previewObject !== 'Account' || !this.personAccountsEnabled) {
            return undefined;
        }
        return {
            criteria: [{ fieldPath: 'IsPersonAccount', operator: 'eq', value: this.isPersonView }]
        };
    }

    /** Keyed by widget so the picker is rebuilt when the object changes. */
    get pickerKeys() {
        return [{ key: this.activeWidgetName }];
    }

    get previewDisabled() {
        return !this.previewAccountId || this.previewLoading;
    }

    /** The related list behind a list-column section, or undefined for other sections. */
    sectionList(def) {
        return def.listSlot ? slotList(this.lists, this.activeWidgetName, def.listSlot) : undefined;
    }

    /** The object a section's fields come from: a list section uses its list's object. */
    sectionObject(def) {
        return def.listSlot ? this.sectionList(def)?.objectApiName : def.objectApiName;
    }

    listView(list) {
        const obj = this.listObjects.find((o) => o.value === list.objectApiName);
        const isNew = list.developerName === null;
        const dirty = isDirty(list, listSnapshot);
        const filterOptions = [{ label: 'All records', value: 'All' }];
        if (!obj || obj.hasIsClosed) {
            filterOptions.push({ label: 'Open only', value: 'Open' });
        }
        filterOptions.push({ label: 'Field equals value', value: 'FieldEquals' });
        return {
            ...list,
            settingsKey: `${list.key}-${list.objectApiName || 'none'}`,
            objectOptions: this.listObjects.map((o) => ({ label: `${o.label} (${o.value})`, value: o.value })),
            parentOptions: (obj?.parentFields || []).map((f) => ({ label: f, value: f })),
            filterOptions,
            isFieldEquals: list.filter === 'FieldEquals',
            sortValue: list.sortDescending === false ? 'asc' : 'desc',
            limitValue: String(list.rowLimit || MAX_LIST_ROWS),
            hasObject: !!list.objectApiName,
            stateLabel: dirty ? (isNew && list.active ? 'New' : 'Changed') : '',
            hasIssue: !!list.issue,
            bodyClass: list.active ? 'list-settings' : 'list-settings list-settings--off'
        };
    }

    get sections() {
        return this.activeSections.map((def) => {
            const list = this.sectionList(def);
            const objectApiName = this.sectionObject(def);
            const sorted = this.rows
                .filter((r) => r.widget === this.activeWidgetName && r.section === def.name)
                .sort(byOrder);
            let activeIndex = 0;
            const counts = { text: 0, shown: 0 };
            const typeOptions = (def.tileTypes || this.columnTypes)
                .filter((t) => list?.layout !== 'Table' || TABLE_TYPES.has(t))
                .map((t) => ({ label: t, value: t }));
            const rows = sorted.map((row, i) => {
                const isNew = row.original === null;
                const dirty = isDirty(row, snapshot);
                const warnings = [];
                if (row.issue) {
                    warnings.push(row.issue);
                }
                const fmt = formatWarning(row, def);
                if (fmt) {
                    warnings.push(fmt);
                }
                if (def.tileTypes && row.columnType === 'Gauge' && row.fieldType && !NUMERIC_TYPES.has(row.fieldType)) {
                    warnings.push('A gauge needs a number field (0-100); this value shows as text.');
                }
                if (row.active) {
                    activeIndex++;
                    if (def.maxActive && activeIndex > def.maxActive) {
                        warnings.push(
                            def.maxActive === 1
                                ? 'Only the first active row is used; this one is ignored.'
                                : `Only the first ${def.maxActive} active rows are used; this one is ignored.`
                        );
                    }
                    const col = list ? columnWarning(row, list.layout, counts) : null;
                    if (col) {
                        warnings.push(col);
                    }
                }
                const hints = COLUMN_HINTS[row.columnType];
                // A blank type is Text (tile rows saved before tiles had types).
                const shownType = row.columnType || 'Text';
                return {
                    ...row,
                    columnType: list || def.tileTypes ? shownType : row.columnType,
                    typeOptions: typeOptions.some((o) => o.value === shownType)
                        ? typeOptions
                        : [...typeOptions, { label: shownType, value: shownType }],
                    noMap: !hints,
                    mapPlaceholder: hints?.map,
                    fallbackPlaceholder: hints?.fallback,
                    isNew,
                    isFirst: i === 0,
                    isLast: i === sorted.length - 1,
                    stateLabel: isNew ? 'New' : dirty ? 'Changed' : '',
                    hasWarnings: warnings.length > 0,
                    warningText: warnings.join(' '),
                    warningKey: `${row.key}-warning`,
                    rowClass: [
                        row.active ? '' : 'row--inactive',
                        row.key === this.dragKey ? 'row--dragging' : ''
                    ].join(' ')
                };
            });
            return {
                ...def,
                objectApiName,
                isList: !!list,
                hasTypes: !!list || !!def.tileTypes,
                typeHelp: list ? HELP.type : HELP.tileType,
                list: list ? this.listView(list) : undefined,
                // Keyed by object so the field pickers rebuild when the list's object changes.
                objectKeys: objectApiName
                    ? [
                          {
                              key: objectApiName,
                              filterKey: `${objectApiName}-filter`,
                              valueKey: `${objectApiName}-value`,
                              sortKey: `${objectApiName}-sort`
                          }
                      ]
                    : [],
                needsObject: !!list && !objectApiName,
                addDisabled: this.saving || (!!list && !objectApiName),
                rows,
                hasRows: rows.length > 0,
                tips: list
                    ? LIST_TIPS
                    : [...FIELD_TIPS, ...(def.usesGroup ? [GROUP_TIP] : []), ...(def.tileTypes ? [TILE_TIP] : [])],
                columnCount: list ? 11 : (def.usesGroup ? 9 : 8) + (def.tileTypes ? 3 : 0),
                sectionClass: `section slds-var-m-bottom_large${
                    def.name === this.dropSection ? ' section--drop' : ''
                }`
            };
        });
    }

    // ----- editing ---------------------------------------------------------------------------

    updateRow(key, changes) {
        this.rows = this.rows.map((r) => (r.key === key ? { ...r, ...changes } : r));
    }

    handleFieldChange(event) {
        const { value, fieldType, fieldLabel } = event.detail;
        this.updateRow(event.target.dataset.key, {
            fieldPath: value,
            fieldType,
            fieldLabel,
            issue: null
        });
    }

    handleInput(event) {
        const { key, field } = event.target.dataset;
        const value = event.target.type === 'checkbox' || event.target.type === 'toggle'
            ? event.target.checked
            : event.detail.value;
        this.updateRow(key, { [field]: value });
    }

    updateList(key, changes) {
        this.lists = this.lists.map((l) => (l.key === key ? { ...l, ...changes, issue: null } : l));
    }

    handleListInput(event) {
        const { key, field } = event.target.dataset;
        const target = event.target;
        let value = target.type === 'toggle' || target.type === 'checkbox' ? target.checked : event.detail.value;
        if (field === 'rowLimit') {
            value = Number(value);
        }
        if (field === 'sortDescending') {
            value = value === 'desc';
        }
        const changes = { [field]: value };
        if (field === 'objectApiName') {
            // A new object means new fields: default the lookup and drop filters on the old object's fields.
            const obj = this.listObjects.find((o) => o.value === value);
            const parents = obj?.parentFields || [];
            const list = this.lists.find((l) => l.key === key);
            changes.parentField = parents.includes('AccountId') ? 'AccountId' : parents.length === 1 ? parents[0] : null;
            changes.filterField = null;
            changes.sortField = null;
            if (list.filter === 'FieldEquals' || (list.filter === 'Open' && obj && !obj.hasIsClosed)) {
                changes.filter = 'All';
            }
        }
        this.updateList(key, changes);
    }

    handleListFieldChange(event) {
        const { key, field } = event.target.dataset;
        this.updateList(key, { [field]: event.detail.value });
    }

    handleMove(event) {
        const { key, direction } = event.currentTarget.dataset;
        const row = this.rows.find((r) => r.key === key);
        const sorted = this.rows
            .filter((r) => r.widget === row.widget && r.section === row.section)
            .sort(byOrder);
        const from = sorted.findIndex((r) => r.key === key);
        const to = direction === 'up' ? from - 1 : from + 1;
        if (to < 0 || to >= sorted.length) {
            return;
        }
        [sorted[from], sorted[to]] = [sorted[to], sorted[from]];
        // Renumber the section so ties and gaps in the shipped values can't break the order.
        const order = new Map(sorted.map((r, i) => [r.key, (i + 1) * ORDER_STEP]));
        this.rows = this.rows.map((r) => (order.has(r.key) ? { ...r, sortOrder: order.get(r.key) } : r));
    }

    // Drag a row onto another row (lands before it) or onto a section (lands at the end). Rows can
    // move between sections on the same object; an Account field means nothing on an Asset section.

    handleDragStart(event) {
        this.dragKey = event.currentTarget.dataset.key;
        if (event.dataTransfer) {
            event.dataTransfer.effectAllowed = 'move';
            event.dataTransfer.setData('text/plain', this.dragKey);
        }
    }

    handleDragOver(event) {
        if (!this.dragKey) {
            return;
        }
        event.preventDefault();
        this.dropSection = event.currentTarget.dataset.section;
    }

    handleDragEnd() {
        this.dragKey = undefined;
        this.dropSection = undefined;
    }

    handleRowDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        const { section, key } = event.currentTarget.dataset;
        this.dropRow(section, key);
    }

    handleSectionDrop(event) {
        event.preventDefault();
        this.dropRow(event.currentTarget.dataset.section, null);
    }

    dropRow(targetSection, beforeKey) {
        const key = this.dragKey;
        this.handleDragEnd();
        const row = this.rows.find((r) => r.key === key);
        if (!row || key === beforeKey) {
            return;
        }
        const from = this.activeSections.find((s) => s.name === row.section);
        const to = this.activeSections.find((s) => s.name === targetSection);
        if (!to) {
            return;
        }
        const fromObject = from ? this.sectionObject(from) : undefined;
        const toObject = this.sectionObject(to);
        if (from && (fromObject !== toObject || !!from.listSlot !== !!to.listSlot)) {
            this.toast(
                "Can't move there",
                `${from.label} uses ${fromObject || 'no'} fields; ${to.label} uses ${toObject || 'no'} fields. Add a new row instead.`,
                'warning'
            );
            return;
        }
        const others = this.rows
            .filter((r) => r.widget === row.widget && r.section === targetSection && r.key !== key)
            .sort(byOrder);
        const at = beforeKey ? others.findIndex((r) => r.key === beforeKey) : -1;
        const ordered = [...others];
        ordered.splice(at < 0 ? ordered.length : at, 0, row);
        const order = new Map(ordered.map((r, i) => [r.key, (i + 1) * ORDER_STEP]));
        // A section without display types (Details) doesn't keep a tile's Badge/Gauge settings.
        const keepsType = !!to.listSlot || !!to.tileTypes;
        this.rows = this.rows.map((r) => {
            if (!order.has(r.key)) {
                return r;
            }
            const moved = { ...r, section: targetSection, sortOrder: order.get(r.key) };
            return r.key !== key || keepsType ? moved : { ...moved, columnType: null, valueMap: null, fallback: null };
        });
    }

    handleAddRow(event) {
        const section = event.currentTarget.dataset.section;
        const widget = this.activeWidgetName;
        const def = this.activeSections.find((s) => s.name === section);
        const hasTypes = !!def?.listSlot || !!def?.tileTypes;
        const max = Math.max(
            0,
            ...this.rows
                .filter((r) => r.widget === widget && r.section === section)
                .map((r) => r.sortOrder ?? 0)
        );
        keySeq++;
        this.rows = [
            ...this.rows,
            {
                key: `new-${keySeq}`,
                developerName: null,
                widget,
                section,
                fieldPath: null,
                label: null,
                groupTitle: null,
                format: 'Auto',
                suffix: null,
                hideWhenBlank: false,
                active: true,
                sortOrder: max + ORDER_STEP,
                columnType: hasTypes ? 'Text' : null,
                valueMap: null,
                fallback: null,
                original: null
            }
        ];
    }

    handleRemoveNew(event) {
        const key = event.currentTarget.dataset.key;
        this.rows = this.rows.filter((r) => r.key !== key);
    }

    handleDiscard() {
        this.reload();
    }

    // ----- saving ----------------------------------------------------------------------------

    async handleSave() {
        const dirty = this.dirtyRows;
        const blank = dirty.find((r) => !hasSource(r));
        if (blank) {
            this.toast(
                'Pick a field',
                'Every new row needs a field before you save (an Image or Icon column can use just a Fallback).',
                'error'
            );
            return;
        }
        this.saving = true;
        try {
            const jobId = await save({ rows: dirty.map(payload), lists: this.dirtyLists.map(listPayload) });
            if (!jobId) {
                this.saving = false;
                this.toast('Nothing to save', 'These rows already match what is saved.', 'info');
                this.reload();
                return;
            }
            this.saveJobId = jobId.substring(0, 15);
            const early = this.deployEvents.get(this.saveJobId);
            if (early) {
                this.finishSave(early);
                return;
            }
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this.saveTimer = setTimeout(() => this.handleSaveTimeout(), SAVE_TIMEOUT_MS);
        } catch (e) {
            this.saving = false;
            this.toast('Could not save', reduceError(e), 'error');
        }
    }

    handleDeployEvent(message) {
        const payloadData = message?.data?.payload || {};
        const jobId = (payloadData.Job_Id__c || '').substring(0, 15);
        const outcome = { success: payloadData.Success__c === true, message: payloadData.Message__c };
        if (this.saving && jobId === this.saveJobId) {
            this.finishSave(outcome);
        } else {
            // The event can beat save()'s response; keep it until the job Id is known.
            this.deployEvents.set(jobId, outcome);
        }
    }

    finishSave(outcome) {
        clearTimeout(this.saveTimer);
        this.saving = false;
        this.saveJobId = undefined;
        if (outcome.success) {
            this.toast('Saved', 'Widget fields and lists are updated for every user.', 'success');
            this.reload().then(() => {
                if (this.previewAccountId) {
                    this.runPreview();
                }
            });
        } else {
            this.toast('Save failed', outcome.message || 'The deploy failed.', 'error');
        }
    }

    handleSaveTimeout() {
        this.saving = false;
        this.saveJobId = undefined;
        this.toast(
            'Still saving',
            'The deploy is taking a while. Check Setup > Deployment Status, then reload this tab.',
            'warning'
        );
    }

    // ----- preview ---------------------------------------------------------------------------

    handleAccountChange(event) {
        this.previewAccountId = event.detail.recordId;
        if (this.previewAccountId) {
            this.runPreview();
        } else {
            this.previewResult = undefined;
            this.previewMessage = undefined;
        }
    }

    handleRefreshPreview() {
        this.runPreview();
    }

    async runPreview() {
        this.previewLoading = true;
        try {
            const json = await preview({
                rows: this.rows.filter(hasSource).map(payload),
                lists: this.lists.filter((l) => l.developerName || l.active).map(listPayload),
                widgetName: this.activeWidgetName,
                recordId: this.previewAccountId
            });
            this.previewResult = json ? JSON.parse(json) : undefined;
            this.previewMessage = json
                ? undefined
                : this.isPersonView
                  ? "That account isn't a Person Account. Switch to Business Account to preview it."
                  : 'That account is a Person Account. Switch to Person Account to preview it.';
        } catch (e) {
            this.previewResult = undefined;
            this.previewMessage = reduceError(e);
        } finally {
            this.previewLoading = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
