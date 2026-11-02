import { LightningElement } from 'lwc';
import canEditFields from '@salesforce/customPermission/HXL_Widget_Field_Editor';

/**
 * The HXL Widgets Setup Guide page: the setup guide, plus a Widget Field Settings tab for holders of
 * the HXL_Widget_Field_Editor permission set. Flexipage tabs can't take visibility rules, so the
 * tabs live here. Hiding the tab is cosmetic; de_HXL_WidgetFieldEditor checks the permission itself.
 */
export default class HxlWidgetsSetupPage extends LightningElement {
    get canEditFields() {
        return canEditFields === true;
    }
}
