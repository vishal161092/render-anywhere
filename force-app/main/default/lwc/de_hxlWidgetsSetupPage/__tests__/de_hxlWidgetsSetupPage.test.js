import { createElement } from 'lwc';
import HxlWidgetsSetupPage from 'c/de_hxlWidgetsSetupPage';

let mockCanEdit = false;
jest.mock('@salesforce/customPermission/HXL_Widget_Field_Editor', () => ({
    __esModule: true,
    get default() {
        return mockCanEdit;
    }
}), { virtual: true });
jest.mock('c/de_hxlWidgetFieldEditor', () => {
    const { LightningElement } = require('lwc');
    return { __esModule: true, default: class extends LightningElement {} };
});

function tabLabels() {
    const element = createElement('c-de_hxl-widgets-setup-page', { is: HxlWidgetsSetupPage });
    document.body.appendChild(element);
    return Array.from(element.shadowRoot.querySelectorAll('lightning-tab')).map((t) => t.label);
}

describe('c-de_hxl-widgets-setup-page', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows only the setup guide without the permission', () => {
        mockCanEdit = false;
        expect(tabLabels()).toEqual(['Setup Guide']);
    });

    it('adds Widget Field Settings for editors', () => {
        mockCanEdit = true;
        expect(tabLabels()).toEqual(['Setup Guide', 'Widget Field Settings']);
    });
});
