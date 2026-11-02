import { createElement } from 'lwc';
import HxlWidgetFieldPreview from 'c/de_hxlWidgetFieldPreview';

function mount(result) {
    const element = createElement('c-de_hxl-widget-field-preview', { is: HxlWidgetFieldPreview });
    element.result = result;
    document.body.appendChild(element);
    return element;
}

describe('c-de_hxl-widget-field-preview', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('draws tiles, details, and card list pairs from the result', () => {
        const element = mount({
            name: 'Jane Doe',
            tier: 'Gold',
            personTilesTitle: 'Energy',
            personTiles: [{ label: 'Capacity', valueDisplay: '7.2 kW' }],
            personDetails: [{ label: 'Phone', valueDisplay: '555', isGroupStart: true, groupTitle: 'Contact' }],
            hasList1: true,
            list1IsCard: true,
            list1Title: 'Assets',
            list1Summary: '1 asset',
            list1Rows: [
                {
                    title: 'Router',
                    hasBadge: true,
                    badgeLabel: 'Installed',
                    badgeVariant: 'success',
                    hasDetail1: true,
                    detail1Label: 'Serial',
                    detail1Value: 'X1'
                }
            ]
        });
        const root = element.shadowRoot;
        expect(root.querySelectorAll('.container_emphasis')).toHaveLength(1);
        expect(root.querySelector('.container_emphasis .text_h3').textContent).toBe('7.2 kW');
        expect(root.querySelectorAll('.row_lg > .column')).toHaveLength(1);
        expect(root.textContent).toContain('Contact');
        expect(root.querySelector('.badge_success').textContent).toBe('Installed');
        expect(root.textContent).not.toContain('No tiles');
    });

    it('draws the configured KPI strip above the tiles', () => {
        const element = mount({
            name: 'Acme Motors',
            isBusinessAccount: true,
            hasSummary: true,
            summaryTiles: [
                { label: 'Warranty Health', valueDisplay: '97' },
                { label: 'Dealer Status', valueDisplay: 'Active - Flagship' }
            ],
            personTiles: [{ label: 'Priority', valueDisplay: 'Low' }]
        });
        const kpis = element.shadowRoot.querySelectorAll('.container_stretch');
        expect(Array.from(kpis).map((k) => k.querySelector('.text_h3').textContent)).toEqual([
            '97',
            'Active - Flagship'
        ]);
        expect(element.shadowRoot.querySelectorAll('.container_emphasis')).toHaveLength(3);
    });

    it('draws badge and gauge tiles', () => {
        const element = mount({
            name: 'Acme Motors',
            hasSummary: true,
            summaryTiles: [
                { label: 'Health', valueDisplay: '62', showsText: true, isGauge: true, gaugeValue: 62, gaugeVariant: 'warning' },
                { label: 'Status', valueDisplay: 'Flagship', showsText: false, isBadge: true, badgeVariant: 'success' }
            ]
        });
        const [gauge, badge] = element.shadowRoot.querySelectorAll('.container_stretch');
        expect(gauge.querySelector('.text_h3').textContent).toBe('62');
        const bar = gauge.querySelector('.progress-bar');
        expect(bar.className).toContain('progress-bar_warning');
        expect(bar.style.width).toBe('62%');
        expect(badge.querySelector('.text_h3')).toBeNull();
        expect(badge.querySelector('.badge_success').textContent).toBe('Flagship');
        expect(badge.querySelector('.progress')).toBeNull();
    });

    it('draws a table list and an empty list', () => {
        const element = mount({
            name: 'Acme',
            hasList1: true,
            list1IsTable: true,
            list1Title: 'Open Cases',
            list1Columns: [
                { key: 'c1', header: 'Subject' },
                { key: 'c2', header: 'Status' }
            ],
            list1TableRows: [{ c1: 'Broken panel', c2: 'New', c3: '' }],
            hasList2: true,
            list2IsEmpty: true,
            list2Title: 'Contacts',
            list2EmptyText: 'No contacts'
        });
        const root = element.shadowRoot;
        expect(Array.from(root.querySelectorAll('.table th')).map((th) => th.textContent)).toEqual([
            'Subject',
            'Status'
        ]);
        expect(Array.from(root.querySelectorAll('.table td')).map((td) => td.textContent)).toEqual([
            'Broken panel',
            'New'
        ]);
        expect(root.textContent).toContain('No contacts');
    });

    it('wraps long and rich text values under their label', () => {
        const element = mount({
            name: 'Jane Doe',
            personDetails: [
                { label: 'Insights', valueDisplay: '<p>Homeowner.</p><p>Second note.</p>' },
                { label: 'Phone', valueDisplay: '555' }
            ]
        });
        const rich = element.shadowRoot.querySelectorAll('lightning-formatted-rich-text.rich');
        expect(rich).toHaveLength(1);
        expect(rich[0].value).toBe('<p>Homeowner.</p><p>Second note.</p>');
        expect(element.shadowRoot.querySelectorAll('.row_between .value')).toHaveLength(1);
    });

    it('says so when nothing is configured', () => {
        const element = mount({ name: 'Jane Doe' });
        expect(element.shadowRoot.textContent).toContain('No tiles, details, or lists');
    });
});
