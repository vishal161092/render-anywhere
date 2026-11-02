import { createElement } from 'lwc';
import HxlWidgetFieldEditor from 'c/de_hxlWidgetFieldEditor';
import load from '@salesforce/apex/de_HXL_WidgetFieldEditor.load';
import save from '@salesforce/apex/de_HXL_WidgetFieldEditor.save';
import { subscribe } from 'lightning/empApi';

jest.mock('@salesforce/apex/de_HXL_WidgetFieldEditor.load', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/de_HXL_WidgetFieldEditor.save', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/de_HXL_WidgetFieldEditor.preview', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock(
    '@salesforce/apex/de_HXL_WidgetFieldEditor.describeFields',
    () => ({ default: jest.fn().mockResolvedValue([]) }),
    { virtual: true }
);
jest.mock('lightning/empApi', () => ({
    subscribe: jest.fn().mockResolvedValue({ id: 'sub' }),
    unsubscribe: jest.fn(),
    onError: jest.fn()
}));

const SECTIONS = [
    {
        name: 'Tile',
        label: 'Insight Tiles',
        objectApiName: 'Account',
        usesGroup: true,
        tileTypes: ['Text', 'Badge', 'Gauge']
    },
    { name: 'Detail', label: 'Details', objectApiName: 'Account', usesGroup: true },
    { name: 'List1Column', label: 'Related List 1 Columns', objectApiName: null, listSlot: 1 },
    { name: 'List2Column', label: 'Related List 2 Columns', objectApiName: null, listSlot: 2 }
];

const WIDGETS = [
    {
        name: 'PersonAccount360',
        label: 'Person Account',
        family: 'Account360',
        familyLabel: 'Account 360',
        iconName: 'standard:account',
        previewObject: 'Account',
        sections: SECTIONS
    },
    {
        name: 'BusinessAccount360',
        label: 'Business Account',
        family: 'Account360',
        familyLabel: 'Account 360',
        iconName: 'standard:account',
        previewObject: 'Account',
        sections: SECTIONS.slice(0, 2)
    },
    {
        name: 'ContactQuickView',
        label: 'Contact Quick View',
        family: 'ContactQuickView',
        familyLabel: 'Contact Quick View',
        iconName: 'standard:contact',
        previewObject: 'Contact',
        sections: [{ name: 'Detail', label: 'Details', objectApiName: 'Contact', usesGroup: true }]
    }
];

function savedRow(developerName, section, fieldPath, sortOrder, extra = {}) {
    return {
        developerName,
        masterLabel: developerName,
        section,
        fieldPath,
        label: null,
        groupTitle: null,
        format: 'Auto',
        suffix: null,
        hideWhenBlank: false,
        active: true,
        sortOrder,
        fieldLabel: fieldPath,
        fieldType: 'STRING',
        ...extra
    };
}

const STATE = {
    widgets: WIDGETS,
    formats: ['Auto', 'Text', 'Number', 'Currency', 'Percent', 'Date'],
    personAccountsEnabled: true,
    rows: [
        savedRow('PA_Tile_A', 'Tile', 'Name', 10),
        savedRow('PA_Tile_B', 'Tile', 'Phone', 20),
        savedRow('PA_Title_1', 'List1Column', 'Name', 10, { columnType: 'Link' }),
        savedRow('PA_Title_2', 'List1Column', 'Product2.DisplayUrl', 20, { columnType: 'Image' }),
        savedRow('CQV_Detail_Title', 'Detail', 'Title', 10, { widget: 'ContactQuickView' })
    ],
    lists: [
        {
            developerName: 'PA_Devices',
            widget: 'PersonAccount360',
            slot: 1,
            active: true,
            title: 'Devices',
            icon: 'plug',
            layout: 'Card',
            objectApiName: 'Asset',
            parentField: 'AccountId',
            filter: 'All',
            sortField: 'InstallDate',
            sortDescending: true,
            rowLimit: 5
        }
    ],
    listObjects: [
        { value: 'Asset', label: 'Assets', parentFields: ['AccountId', 'AssetProvidedById'], hasIsClosed: false },
        { value: 'Case', label: 'Cases', parentFields: ['AccountId'], hasIsClosed: true }
    ],
    columnTypes: ['Text', 'Link', 'Subtitle', 'Badge', 'Image', 'Icon'],
    icons: ['list', 'plug', 'headset']
};

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function openCard(element, family) {
    element.shadowRoot.querySelector(`article[data-family="${family}"]`).click();
    await flush();
}

/** Mounts the editor and opens the Account 360 card (Person view). */
async function mount() {
    const element = await mountGallery();
    await openCard(element, 'Account360');
    return element;
}

async function mountGallery() {
    const element = createElement('c-de_hxl-widget-field-editor', { is: HxlWidgetFieldEditor });
    document.body.appendChild(element);
    await flush();
    return element;
}

function button(element, label) {
    return Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
        (b) => b.label === label
    );
}

function rowKeys(element) {
    return Array.from(element.shadowRoot.querySelectorAll('tr[data-row]')).map(
        (tr) => tr.dataset.row
    );
}

describe('c-de_hxl-widget-field-editor', () => {
    beforeEach(() => {
        load.mockResolvedValue(JSON.parse(JSON.stringify(STATE)));
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows one card per widget family', async () => {
        const element = await mountGallery();
        const cards = Array.from(element.shadowRoot.querySelectorAll('article.widget-card'));
        expect(cards.map((c) => c.dataset.family)).toEqual(['Account360', 'ContactQuickView']);
        expect(cards[0].textContent).toContain('Person Account · Business Account');
        expect(cards[0].textContent).toContain('4 active fields');
        expect(cards[1].textContent).toContain('1 active field');
    });

    it('scopes rows to the open widget and switches Person/Business', async () => {
        const element = await mountGallery();
        await openCard(element, 'ContactQuickView');
        expect(rowKeys(element)).toEqual(['CQV_Detail_Title']);

        button(element, 'All widgets').click();
        await flush();
        await openCard(element, 'Account360');
        const toggle = element.shadowRoot.querySelector('lightning-radio-group');
        toggle.dispatchEvent(new CustomEvent('change', { detail: { value: 'BusinessAccount360' } }));
        await flush();
        expect(rowKeys(element)).toEqual([]);
        expect(element.shadowRoot.querySelectorAll('div[data-section] h3')).toHaveLength(2);
    });

    it('renders each section with its rows in sort order', async () => {
        const element = await mount();
        const headings = Array.from(element.shadowRoot.querySelectorAll('h3.slds-text-heading_small'));
        expect(headings[0].textContent).toContain('Insight Tiles');
        expect(rowKeys(element)).toEqual(['PA_Tile_A', 'PA_Tile_B', 'PA_Title_1', 'PA_Title_2']);
        expect(button(element, 'Save').disabled).toBe(true);
    });

    it('shows field tips on field sections and column-type tips on lists', async () => {
        const element = await mount();
        const tips = Array.from(element.shadowRoot.querySelectorAll('div[data-section]')).map((s) => ({
            isList: !!s.querySelector('lightning-radio-group[data-field="layout"]'),
            text: s.querySelector('details.tips').textContent
        }));
        const fields = tips.filter((t) => !t.isList);
        const lists = tips.filter((t) => t.isList);
        expect(fields.length).toBeGreaterThan(0);
        expect(lists.length).toBeGreaterThan(0);
        fields.forEach((t) => {
            expect(t.text).toContain('Field paths');
            expect(t.text).not.toContain('Status badges');
        });
        lists.forEach((t) => {
            expect(t.text).toContain('Status badges');
            expect(t.text).toContain('Missing in Slack?');
        });
    });

    function warnings(element) {
        return Array.from(element.shadowRoot.querySelectorAll('.warning-text')).map((w) => w.textContent);
    }

    function listInput(element, tag, key, field, detail) {
        const input = element.shadowRoot.querySelector(`${tag}[data-key="${key}"][data-field="${field}"]`);
        input.dispatchEvent(new CustomEvent('change', { detail }));
    }

    it('limits a table to the column types it can show', async () => {
        const element = await mount();
        expect(warnings(element)).toEqual([]);

        listInput(element, 'lightning-radio-group', 'PA_Devices', 'layout', { value: 'Table' });
        await flush();
        expect(warnings(element)).toEqual(["Tables don't show images or icons; this column is skipped."]);
        const type = element.shadowRoot.querySelector('lightning-combobox[data-key="PA_Title_1"][data-field="columnType"]');
        expect(type.options.map((o) => o.value)).toEqual(['Text', 'Link', 'Subtitle', 'Badge']);
        expect(button(element, 'Save (1)')).toBeTruthy();
    });

    it('offers badge and gauge types on tiles only', async () => {
        const element = await mount();
        const type = element.shadowRoot.querySelector('lightning-combobox[data-key="PA_Tile_A"][data-field="columnType"]');
        expect(type.options.map((o) => o.value)).toEqual(['Text', 'Badge', 'Gauge']);
        const detail = element.shadowRoot.querySelector('div[data-section="Detail"]');
        expect(detail.querySelector('lightning-combobox[data-field="columnType"]')).toBeNull();
        const tips = element.shadowRoot.querySelector('div[data-section="Tile"] details.tips').textContent;
        expect(tips).toContain('Badges and gauges');

        type.dispatchEvent(new CustomEvent('change', { detail: { value: 'Gauge' } }));
        await flush();
        expect(warnings(element)).toEqual(['A gauge needs a number field (0-100); this value shows as text.']);
    });

    it('clears a tile type when the row moves to Details', async () => {
        save.mockResolvedValue('0AfXXXXXXXXXXXXXXX');
        const element = await mount();
        listInput(element, 'lightning-combobox', 'PA_Tile_A', 'columnType', { value: 'Badge' });
        await flush();
        drag(element, 'PA_Tile_A');
        element.shadowRoot.querySelector('div[data-section="Detail"]').dispatchEvent(new CustomEvent('drop'));
        await flush();
        button(element, 'Save (1)').click();
        await flush();
        expect(save.mock.calls[0][0].rows[0]).toMatchObject({ section: 'Detail', columnType: null });
    });

    it('saves a changed list without its unchanged rows', async () => {
        save.mockResolvedValue('0AfXXXXXXXXXXXXXXX');
        const element = await mount();
        listInput(element, 'lightning-input', 'PA_Devices', 'title', { value: 'Gadgets' });
        await flush();
        button(element, 'Save (1)').click();
        await flush();

        const { rows, lists } = save.mock.calls[0][0];
        expect(rows).toEqual([]);
        expect(lists).toHaveLength(1);
        expect(lists[0]).toMatchObject({ developerName: 'PA_Devices', title: 'Gadgets', slot: 1 });
        expect(lists[0].key).toBeUndefined();
    });

    it('sets up an empty slot once an object is picked', async () => {
        save.mockResolvedValue('0AfXXXXXXXXXXXXXXX');
        const element = await mount();
        const key = 'PersonAccount360-list-2';
        expect(element.shadowRoot.textContent).toContain("Pick the list's object above");
        expect(element.shadowRoot.querySelector('lightning-button[data-section="List2Column"]').disabled).toBe(true);
        expect(button(element, 'Save').disabled).toBe(true);

        element.shadowRoot.querySelector(`lightning-input[data-key="${key}"][data-field="active"]`).checked = true;
        listInput(element, 'lightning-input', key, 'active', {});
        listInput(element, 'lightning-combobox', key, 'objectApiName', { value: 'Case' });
        await flush();
        expect(element.shadowRoot.querySelector('lightning-button[data-section="List2Column"]').disabled).toBe(false);

        button(element, 'Save (1)').click();
        await flush();
        expect(save.mock.calls[0][0].lists[0]).toMatchObject({
            developerName: null,
            widget: 'PersonAccount360',
            slot: 2,
            active: true,
            objectApiName: 'Case',
            parentField: 'AccountId',
            layout: 'Card'
        });
    });

    it('marks an added row as a change', async () => {
        const element = await mount();
        element.shadowRoot.querySelector('lightning-button[data-section="Tile"]').click();
        await flush();
        expect(rowKeys(element)).toHaveLength(5);
        expect(button(element, 'Save (1)')).toBeTruthy();
    });

    it('moves a row down by swapping sort order', async () => {
        const element = await mount();
        element.shadowRoot
            .querySelector('lightning-button-icon[data-key="PA_Tile_A"][data-direction="down"]')
            .click();
        await flush();
        expect(rowKeys(element).slice(0, 2)).toEqual(['PA_Tile_B', 'PA_Tile_A']);
        expect(button(element, 'Save (2)')).toBeTruthy();
    });

    it('saves only changed rows and finishes on the deploy event', async () => {
        save.mockResolvedValue('0AfXXXXXXXXXXXXXXX');
        const element = await mount();
        const input = element.shadowRoot.querySelector(
            'lightning-input[data-key="PA_Tile_B"][data-field="label"]'
        );
        input.dispatchEvent(new CustomEvent('change', { detail: { value: 'Mobile' } }));
        await flush();

        button(element, 'Save (1)').click();
        await flush();

        expect(save).toHaveBeenCalledTimes(1);
        const sent = save.mock.calls[0][0].rows;
        expect(sent).toHaveLength(1);
        expect(sent[0]).toMatchObject({ developerName: 'PA_Tile_B', label: 'Mobile' });
        expect(sent[0].key).toBeUndefined();

        const onMessage = subscribe.mock.calls[0][2];
        onMessage({ data: { payload: { Job_Id__c: '0AfXXXXXXXXXXXXXXX', Success__c: true } } });
        await flush();
        expect(load).toHaveBeenCalledTimes(2);
    });

    function drag(element, key) {
        element.shadowRoot.querySelector(`.grip[data-key="${key}"]`).dispatchEvent(new CustomEvent('dragstart'));
    }

    it('drags a row into another section on the same object', async () => {
        const element = await mount();
        drag(element, 'PA_Tile_A');
        const detail = element.shadowRoot.querySelector('div[data-section="Detail"]');
        detail.dispatchEvent(new CustomEvent('dragover'));
        detail.dispatchEvent(new CustomEvent('drop'));
        await flush();

        const tables = element.shadowRoot.querySelectorAll('table');
        expect(tables).toHaveLength(3);
        expect(tables[1].querySelector('tr[data-row]').dataset.row).toBe('PA_Tile_A');
        expect(button(element, 'Save (1)')).toBeTruthy();
    });

    it('drops a row before the row it lands on', async () => {
        const element = await mount();
        drag(element, 'PA_Tile_B');
        element.shadowRoot.querySelector('tr[data-row="PA_Tile_A"]').dispatchEvent(new CustomEvent('drop'));
        await flush();
        expect(rowKeys(element).slice(0, 2)).toEqual(['PA_Tile_B', 'PA_Tile_A']);
    });

    it('refuses to move an Account field into a list of Assets', async () => {
        const element = await mount();
        const toasts = jest.fn();
        element.addEventListener('lightning__showtoast', toasts);
        drag(element, 'PA_Tile_A');
        element.shadowRoot.querySelector('div[data-section="List1Column"]').dispatchEvent(new CustomEvent('drop'));
        await flush();
        expect(rowKeys(element)[0]).toBe('PA_Tile_A');
        expect(button(element, 'Save').disabled).toBe(true);
        expect(toasts).toHaveBeenCalledTimes(1);
    });

    it('does not save a new row without a field', async () => {
        const element = await mount();
        element.shadowRoot.querySelector('lightning-button[data-section="Tile"]').click();
        await flush();
        button(element, 'Save (1)').click();
        await flush();
        expect(save).not.toHaveBeenCalled();
    });
});
