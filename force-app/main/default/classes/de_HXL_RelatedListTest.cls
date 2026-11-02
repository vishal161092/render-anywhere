@IsTest
private class de_HXL_RelatedListTest {

    private static final String WIDGET = 'BusinessAccount360';

    private static HXL_Related_List__mdt relatedList(Integer slot, String layout, String obj, String filter) {
        return new HXL_Related_List__mdt(
            DeveloperName = 'BA_List_' + slot, Widget__c = WIDGET, Slot__c = slot, Active__c = true,
            Title__c = 'Things', Icon__c = 'target', Layout__c = layout, Object__c = obj,
            Parent_Field__c = 'AccountId', Filter__c = filter, Sort_Descending__c = true
        );
    }

    private static HXL_Widget_Field__mdt column(Integer slot, String type, String path, Decimal order) {
        return new HXL_Widget_Field__mdt(
            Widget__c = WIDGET, Section__c = 'List' + slot + 'Column', Field_API_Name__c = path,
            Column_Type__c = type, Active__c = true, Sort_Order__c = order, Format__c = 'Auto'
        );
    }

    private static Account account() {
        Account a = new Account(Name = 'Related Co');
        insert a;
        return a;
    }

    @IsTest
    static void tableShowsOpenRecordsOnly() {
        Account a = account();
        insert new List<Opportunity>{
            new Opportunity(Name = 'Big', AccountId = a.Id, StageName = 'Prospecting', Amount = 900000, CloseDate = Date.today()),
            new Opportunity(Name = 'Small', AccountId = a.Id, StageName = 'Prospecting', Amount = 100, CloseDate = Date.today()),
            new Opportunity(Name = 'Won', AccountId = a.Id, StageName = 'Closed Won', Amount = 5, CloseDate = Date.today())
        };
        HXL_Related_List__mdt cfg = relatedList(1, 'Table', 'Opportunity', 'Open');
        cfg.Sort_Field__c = 'Amount';
        de_HXL_RelatedList.useLists(new List<HXL_Related_List__mdt>{ cfg });
        HXL_Widget_Field__mdt amount = column(1, 'Text', 'Amount', 20);
        amount.Label__c = 'Value';
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{
            column(1, 'Link', 'Name', 10), amount, column(1, 'Image', 'Name', 30), column(1, 'Text', 'Bogus__x', 40)
        });

        de_HXL_RelatedList.Output o = de_HXL_RelatedList.build(WIDGET, 1, a.Id);

        Assert.isTrue(o.hasList);
        Assert.isTrue(o.isTable);
        Assert.isFalse(o.isCard);
        Assert.isNull(o.rows);
        Assert.areEqual(2, o.columns.size(), 'Image and unknown fields are skipped in tables');
        Assert.areEqual('c2', o.columns[1].key);
        Assert.areEqual('Value', o.columns[1].header);
        Assert.areEqual(2, o.tableRows.size(), 'Closed opportunity is filtered out');
        Assert.areEqual('Big', o.tableRows[0].c1, 'Sorted by amount desc');
        Assert.areEqual('$900K', o.tableRows[0].c2);
        Assert.areEqual('', o.tableRows[0].c3);
        Assert.areEqual('2 opportunities', o.summary);
        Assert.areEqual('target', o.icon);
    }

    @IsTest
    static void cardMapsBadgeIconAndDetails() {
        Account a = account();
        insert new Contact(LastName = 'Lee', Title = 'CFO', AccountId = a.Id, Department = 'Finance');
        de_HXL_RelatedList.useLists(new List<HXL_Related_List__mdt>{ relatedList(2, 'Card', 'Contact', 'All') });
        HXL_Widget_Field__mdt badge = column(2, 'Badge', 'Department', 30);
        badge.Value_Map__c = 'finance=success; sales = warning';
        HXL_Widget_Field__mdt icon = column(2, 'Icon', 'Title', 40);
        icon.Value_Map__c = 'CFO=dollar-sign';
        HXL_Widget_Field__mdt hidden = column(2, 'Text', 'Phone', 50);
        hidden.Hide_When_Blank__c = true;
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{
            column(2, 'Subtitle', 'Title', 20), badge, icon, hidden, column(2, 'Text', 'Email', 60)
        });

        de_HXL_RelatedList.Output o = de_HXL_RelatedList.build(WIDGET, 2, a.Id);

        Assert.isTrue(o.isCard);
        de_HXL_GetAccount360.ListRow row = o.rows[0];
        Assert.areEqual('Lee', row.title, 'No Link column: the Name is the title');
        Assert.areEqual('CFO', row.subtitle, 'No label set: value only');
        Assert.areEqual('Finance', row.badgeLabel);
        Assert.areEqual('success', row.badgeVariant);
        Assert.isTrue(row.hasIcon);
        Assert.areEqual('dollar-sign', row.iconName);
        Assert.isTrue(row.hasDetail1, 'Blank Email shows a dash');
        Assert.areEqual('—', row.detail1Value);
        Assert.isFalse(row.hasDetail2, 'Blank hide-when-blank Phone is skipped');
        Assert.isTrue(String.isNotBlank(row.salesforceUrl));
        Assert.areEqual('1 contact', o.summary);
    }

    @IsTest
    static void fieldEqualsFiltersWithTypedValues() {
        Account a = account();
        insert new List<Contact>{
            new Contact(LastName = 'A', AccountId = a.Id, Department = 'Sales'),
            new Contact(LastName = 'B', AccountId = a.Id, Department = 'Legal'),
            new Contact(LastName = 'C', AccountId = a.Id, Department = 'Support')
        };
        HXL_Related_List__mdt cfg = relatedList(1, 'Card', 'Contact', 'FieldEquals');
        cfg.Filter_Field__c = 'Department';
        cfg.Filter_Value__c = 'Sales, Support';
        cfg.Sort_Field__c = 'LastName';
        cfg.Sort_Descending__c = false;
        de_HXL_RelatedList.useLists(new List<HXL_Related_List__mdt>{ cfg });
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{ column(1, 'Link', 'LastName', 10) });

        de_HXL_RelatedList.Output o = de_HXL_RelatedList.build(WIDGET, 1, a.Id);

        Assert.areEqual(2, o.rows.size());
        Assert.areEqual('A', o.rows[0].title, 'Ascending sort');
        Assert.areEqual('C', o.rows[1].title);

        Map<String, Object> binds = new Map<String, Object>();
        HXL_Related_List__mdt flag = relatedList(1, 'Card', 'Contact', 'FieldEquals');
        flag.Filter_Field__c = 'DoNotCall';
        flag.Filter_Value__c = 'true';
        Assert.areEqual('DoNotCall = :filterValue', de_HXL_RelatedList.fieldEquals(flag, Contact.SObjectType, binds));
        Assert.areEqual(true, binds.get('filterValue'));
        flag.Filter_Field__c = 'Not_A_Field__c';
        Assert.isNull(de_HXL_RelatedList.fieldEquals(flag, Contact.SObjectType, binds));
    }

    @IsTest
    static void emptyAndInvalidLists() {
        Account a = account();
        HXL_Related_List__mdt empty = relatedList(1, 'Card', 'Contact', 'All');
        HXL_Related_List__mdt badParent = relatedList(2, 'Card', 'Contact', 'All');
        badParent.Parent_Field__c = 'ReportsToId'; // Points at Contact, not Account.
        de_HXL_RelatedList.useLists(new List<HXL_Related_List__mdt>{ empty, badParent });
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>());

        de_HXL_RelatedList.Output o = de_HXL_RelatedList.build(WIDGET, 1, a.Id);
        Assert.isTrue(o.hasList);
        Assert.isTrue(o.isEmpty);
        Assert.isFalse(o.isCard);
        Assert.isFalse(o.isTable);
        Assert.isNull(o.rows);
        Assert.areEqual('No things', o.emptyText);
        Assert.areEqual('0 contacts', o.summary);

        Assert.isFalse(de_HXL_RelatedList.build(WIDGET, 2, a.Id).hasList, 'Non-Account parent field is rejected');

        badParent.Parent_Field__c = 'AccountId';
        badParent.Object__c = 'No_Such_Object__c';
        Assert.isFalse(de_HXL_RelatedList.build(WIDGET, 2, a.Id).hasList);
        empty.Active__c = false;
        Assert.isFalse(de_HXL_RelatedList.build(WIDGET, 1, a.Id).hasList, 'Inactive list is hidden');
    }

    @IsTest
    static void applySetsEveryFlag() {
        de_HXL_RelatedList.useLists(new List<HXL_Related_List__mdt>());
        de_HXL_GetAccount360.Result r = new de_HXL_GetAccount360.Result();
        de_HXL_RelatedList.hideAll(r);
        Assert.isFalse(r.hasList1);
        Assert.isFalse(r.list2IsTable);
        Assert.areEqual('', r.list2EmptyText);

        de_HXL_RelatedList.apply(r, WIDGET, account().Id);
        Assert.isFalse(r.hasList2);
        Assert.areEqual(de_HXL_RelatedList.DEFAULT_ICON, r.list1Icon);
    }

    @IsTest
    static void imageUrlsMustBeHttps() {
        de_HXL_RelatedList.Column c = new de_HXL_RelatedList.Column();
        c.valueMap = new Map<String, String>();
        Assert.areEqual('https://x.example/a.png', de_HXL_RelatedList.imageUrl(c, 'https://x.example/a.png'));
        Assert.isNull(de_HXL_RelatedList.imageUrl(c, 'http://x.example/a.png'));
        Assert.isNull(de_HXL_RelatedList.imageUrl(c, '/servlet/img.png'));
        Assert.isNull(de_HXL_RelatedList.imageUrl(c, null));
        Assert.areEqual('https://x.example/b.png',
            de_HXL_RelatedList.imageUrl(c, '<p><img alt="b" src="https://x.example/b.png"></img></p>'));

        c.fallback = 'https://x.example/default.png';
        Assert.areEqual(c.fallback, de_HXL_RelatedList.imageUrl(c, ''));
        c.valueMap = de_HXL_RelatedList.parseMap('Mono=https://x.example/mono.png?w=1&h=2;Bad');
        Assert.areEqual('https://x.example/mono.png?w=1&h=2', de_HXL_RelatedList.imageUrl(c, 'MONO'), 'Splits on the first =');
        Assert.areEqual(c.fallback, de_HXL_RelatedList.imageUrl(c, 'Other'), 'Map miss uses the fallback');
    }

    @IsTest
    static void iconsAndBadgesAreWhitelisted() {
        de_HXL_RelatedList.Column c = new de_HXL_RelatedList.Column();
        c.valueMap = new Map<String, String>();
        Assert.areEqual('users', de_HXL_RelatedList.iconFor(c, ' Users '));
        Assert.isNull(de_HXL_RelatedList.iconFor(c, 'not-an-icon'));
        c.fallback = 'star';
        Assert.areEqual('star', de_HXL_RelatedList.iconFor(c, 'not-an-icon'));

        c.valueMap = de_HXL_RelatedList.parseMap('hot=purple');
        Assert.areEqual('secondary', de_HXL_RelatedList.badgeVariant(c, 'Hot'), 'Unknown variant ignored');
        c.fallback = 'Warning';
        Assert.areEqual('warning', de_HXL_RelatedList.badgeVariant(c, 'cold'));
    }

    @IsTest
    static void providerOutputIsNormalized() {
        HXL_Related_List__mdt cfg = relatedList(1, 'Card', 'Contact', 'All');
        cfg.Provider_Class__c = 'de_HXL_RelatedListTest.FakeProvider';
        HXL_Related_List__mdt bad = relatedList(2, 'Card', 'Contact', 'All');
        bad.Provider_Class__c = 'de_HXL_RelatedListTest';
        de_HXL_RelatedList.useLists(new List<HXL_Related_List__mdt>{ cfg, bad });
        Id accountId = account().Id;

        de_HXL_RelatedList.Output o = de_HXL_RelatedList.build(WIDGET, 1, accountId);

        Assert.isTrue(o.isCard);
        Assert.areEqual(de_HXL_RelatedList.MAX_ROWS, o.rows.size(), 'Rows capped');
        Assert.areEqual(de_HXL_RelatedList.DEFAULT_ICON, o.icon, 'Invalid icon replaced');
        Assert.areEqual('', o.summary);
        de_HXL_GetAccount360.ListRow row = o.rows[0];
        Assert.areEqual('', row.subtitle);
        Assert.isFalse(row.hasImage, 'http image dropped');
        Assert.areEqual('secondary', row.badgeVariant);
        Assert.isFalse(row.hasDetail1);
        Assert.isFalse(de_HXL_RelatedList.build(WIDGET, 2, accountId).hasList, 'Not a provider: hidden');
        Assert.isFalse(de_HXL_RelatedList.normalize(null).hasList);
    }

    public class FakeProvider implements de_HXL_RelatedListProvider {
        public de_HXL_RelatedList.Output build(HXL_Related_List__mdt config, Id parentId) {
            de_HXL_RelatedList.Output o = new de_HXL_RelatedList.Output();
            o.hasList = true;
            o.isCard = true;
            o.icon = 'nope';
            o.summary = null;
            o.rows = new List<de_HXL_GetAccount360.ListRow>();
            for (Integer i = 0; i < de_HXL_RelatedList.MAX_ROWS + 2; i++) {
                de_HXL_GetAccount360.ListRow row = new de_HXL_GetAccount360.ListRow();
                row.title = 'Row ' + i;
                row.hasImage = true;
                row.imageUrl = 'http://insecure.example/x.png';
                row.badgeVariant = 'purple';
                o.rows.add(row);
            }
            return o;
        }
    }
}
