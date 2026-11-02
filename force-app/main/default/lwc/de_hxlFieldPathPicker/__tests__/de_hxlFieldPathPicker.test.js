import { createElement } from 'lwc';
import HxlFieldPathPicker from 'c/de_hxlFieldPathPicker';

const FIELDS = {
    Asset: [
        { value: 'Name', label: 'Asset Name', type: 'STRING' },
        {
            value: 'Product2Id',
            label: 'Product',
            type: 'REFERENCE',
            relationshipName: 'Product2',
            referenceTo: 'Product2',
            referenceToLabel: 'Product'
        }
    ],
    Product2: [
        { value: 'Name', label: 'Product Name', type: 'STRING' },
        { value: 'ProductCode', label: 'Product Code', type: 'STRING' }
    ]
};

jest.mock(
    '@salesforce/apex/de_HXL_WidgetFieldEditor.describeFields',
    () => ({
        default: jest.fn(({ objectApiName }) => Promise.resolve(FIELDS[objectApiName]))
    }),
    { virtual: true }
);

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount(value) {
    const element = createElement('c-de_hxl-field-path-picker', { is: HxlFieldPathPicker });
    element.objectApiName = 'Asset';
    element.value = value;
    document.body.appendChild(element);
    await flush();
    return element;
}

const combos = (element) => Array.from(element.shadowRoot.querySelectorAll('lightning-combobox'));

describe('c-de_hxl-field-path-picker', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('offers fields and lookup hops', async () => {
        const element = await mount(null);
        const values = combos(element)[0].options.map((o) => o.value);
        expect(values).toEqual(['Name', 'Product2Id', 'Product2.']);
    });

    it('opens one dropdown per hop for a saved path', async () => {
        const element = await mount('Product2.Name');
        const [first, second] = combos(element);
        expect(first.value).toBe('Product2.');
        expect(second.value).toBe('Name');
    });

    it('keeps a missing field visible', async () => {
        const element = await mount('Gone__c');
        const [first] = combos(element);
        expect(first.value).toBe('Gone__c');
        expect(first.options[0].label).toBe('Gone__c (not found)');
    });

    it('fires change with the full path when a field after a hop is picked', async () => {
        const element = await mount('Product2.Name');
        const handler = jest.fn();
        element.addEventListener('change', handler);
        combos(element)[1].dispatchEvent(
            new CustomEvent('change', { detail: { value: 'ProductCode' } })
        );
        await flush();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({
            value: 'Product2.ProductCode',
            fieldType: 'STRING',
            fieldLabel: 'Product Code'
        });
    });
});
