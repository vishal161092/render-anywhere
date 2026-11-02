/**
 * de_HXL_RelatedListProvider — custom code for one Account 360 related list (the advanced,
 * use-at-your-own-risk option). Name the implementing class in HXL_Related_List__mdt.Provider_Class__c
 * and it replaces the configured query for that slot.
 *
 * Implementations must keep to the widget's rules: read data USER_MODE, and return text that is
 * never null. de_HXL_RelatedList fills unset flags and text after the call, caps rows/columns to the
 * widget's slots, and drops the list if the provider throws.
 */
public interface de_HXL_RelatedListProvider {
    /** The list to show for `config` on the account `parentId`; null hides the slot. */
    de_HXL_RelatedList.Output build(HXL_Related_List__mdt config, Id parentId);
}
