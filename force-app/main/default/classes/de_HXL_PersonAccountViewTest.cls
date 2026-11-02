@IsTest
private class de_HXL_PersonAccountViewTest {

    private static de_HXL_GetAccount360.Result run(String ref) {
        de_HXL_GetAccount360.Request req = new de_HXL_GetAccount360.Request();
        req.accountRef = ref;
        return de_HXL_GetAccount360.getSnapshot(new List<de_HXL_GetAccount360.Request>{ req })[0].snapshot;
    }

    private static HXL_Widget_Field__mdt row(String section, String path, String groupTitle, Decimal order) {
        return new HXL_Widget_Field__mdt(
            Widget__c = de_HXL_PersonAccountView.WIDGET, Section__c = section, Field_API_Name__c = path,
            Group__c = groupTitle, Active__c = true, Sort_Order__c = order, Format__c = 'Auto'
        );
    }

    /** Standard-field config so the test doesn't depend on any org's custom fields. */
    private static void useStandardConfig() {
        HXL_Widget_Field__mdt hiddenBlank = row('Detail', 'Phone', 'Contact Info', 30);
        hiddenBlank.Hide_When_Blank__c = true;
        HXL_Widget_Field__mdt serial = column('Subtitle', 'SerialNumber', null, 20);
        serial.Label__c = 'Serial';
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{
            row('Tile', 'AnnualRevenue', 'Commercial Insights', 10),
            row('Tile', 'NumberOfEmployees', null, 20),
            row('Detail', 'PersonMailingCity', 'Home', 10),
            row('Detail', 'PersonMailingState', 'Home', 20),
            hiddenBlank,
            row('Detail', 'PersonEmail', 'Contact Info', 40),
            column('Link', 'Name', null, 10),
            serial,
            column('Image', 'Product2.Name', 'https://example.com/panel.png', 30),
            column('Text', 'Status', null, 40),
            column('Text', 'InstallDate', null, 50)
        });
        de_HXL_RelatedList.useLists(new List<HXL_Related_List__mdt>{
            new HXL_Related_List__mdt(
                DeveloperName = 'PA_Devices', Widget__c = de_HXL_PersonAccountView.WIDGET, Slot__c = 1, Active__c = true,
                Title__c = 'Devices', Icon__c = 'plug', Layout__c = 'Card', Object__c = 'Asset',
                Parent_Field__c = 'AccountId', Filter__c = 'All', Sort_Field__c = 'InstallDate',
                Sort_Descending__c = true, Row_Limit__c = 5
            )
        });
    }

    private static HXL_Widget_Field__mdt column(String type, String path, String fallback, Decimal order) {
        HXL_Widget_Field__mdt c = row('List1Column', path, null, order);
        c.Column_Type__c = type;
        c.Fallback__c = fallback;
        return c;
    }

    /** A Person Account built via put() so this class compiles in orgs without Person Accounts. */
    private static SObject personAccount() {
        List<SObject> rts = Database.query(
            'SELECT Id FROM RecordType WHERE SobjectType = \'Account\' AND IsPersonType = true AND IsActive = true LIMIT 1'
        );
        if (rts.isEmpty()) {
            return null;
        }
        SObject a = Account.SObjectType.newSObject();
        a.put('RecordTypeId', rts[0].Id);
        a.put('FirstName', 'Demo');
        a.put('LastName', 'Sample Customer');
        a.put('PersonMailingCity', 'San Francisco');
        a.put('PersonMailingState', 'CA');
        a.put('PersonEmail', 'demo.customer@example.com');
        a.put('AnnualRevenue', 126795);
        insert a;
        return a;
    }

    @IsTest
    static void personAccountGetsTilesDetailsAndDeviceList() {
        if (!de_HXL_PersonAccountView.personAccountsEnabled()) {
            return; // Org has no Person Accounts; the business view is covered elsewhere.
        }
        useStandardConfig();
        SObject a = personAccount();
        if (a == null) {
            return;
        }
        Product2 panel = new Product2(Name = 'Sample Router 500');
        insert panel;
        List<Asset> assets = new List<Asset>();
        for (Integer i = 0; i < de_HXL_RelatedList.MAX_ROWS + 1; i++) {
            assets.add(new Asset(
                Name = 'Panel ' + i, AccountId = a.Id, Product2Id = panel.Id,
                SerialNumber = 'SN' + i, Status = 'Installed', InstallDate = Date.today().addDays(-i)
            ));
        }
        insert assets;

        de_HXL_GetAccount360.Result r = run(a.Id);

        Assert.isTrue(r.isPersonAccount);
        Assert.isFalse(r.isBusinessAccount);
        Assert.areEqual('Person Account', r.tier);
        Assert.areEqual('San Francisco, CA', r.headerSubtitle);

        Assert.areEqual('Commercial Insights', r.personTilesTitle);
        Assert.areEqual(2, r.personTiles.size());
        Assert.areEqual('$127K', r.personTiles[0].valueDisplay);
        Assert.areEqual('N/A', r.personTiles[1].valueDisplay, 'Blank tile shows N/A');

        Assert.areEqual(3, r.personDetails.size(), 'Blank Phone row is hidden');
        Assert.isTrue(r.personDetails[0].isGroupStart);
        Assert.isFalse(r.personDetails[1].isGroupStart, 'Same group continues');
        Assert.isTrue(r.personDetails[2].isGroupStart, 'New group starts');
        Assert.areEqual('demo.customer@example.com', r.personDetails[2].valueDisplay);

        Assert.isFalse(r.hasDevices, 'Devices moved to the related list');
        Assert.isTrue(r.hasList1);
        Assert.isTrue(r.list1IsCard);
        Assert.isFalse(r.list1IsTable);
        Assert.areEqual('Devices', r.list1Title);
        Assert.areEqual('plug', r.list1Icon);
        Assert.areEqual(de_HXL_RelatedList.MAX_ROWS, r.list1Rows.size());
        Assert.areEqual('Showing 5 of 6', r.list1Summary);
        de_HXL_GetAccount360.ListRow newest = r.list1Rows[0];
        Assert.areEqual('Panel 0', newest.title, 'Newest install first');
        Assert.areEqual('Serial: SN0', newest.subtitle);
        Assert.isTrue(newest.hasImage, 'Non-URL value falls back to the fixed image');
        Assert.areEqual('https://example.com/panel.png', newest.imageUrl);
        Assert.isTrue(newest.hasDetail1);
        Assert.areEqual('Installed', newest.detail1Value);
        Assert.isTrue(newest.hasDetail2);
        Assert.isFalse(newest.hasDetail3);
        Assert.isFalse(r.hasList2, 'No slot 2 configured');
    }

    @IsTest
    static void businessAccountKeepsBusinessView() {
        useStandardConfig();
        Account a = new Account(Name = 'Business Co');
        insert a;

        de_HXL_GetAccount360.Result r = run(a.Id);

        Assert.isTrue(r.isBusinessAccount);
        Assert.isFalse(r.isPersonAccount);
        Assert.isNull(r.personTiles);
        Assert.isFalse(de_HXL_PersonAccountView.apply(new de_HXL_GetAccount360.Result(), a.Id));
    }

    @IsTest
    static void businessAccountAddsConfiguredTilesAndDetails() {
        HXL_Widget_Field__mdt tile = row('Tile', 'AnnualRevenue', 'Firmographics', 10);
        tile.Widget__c = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        HXL_Widget_Field__mdt detail = row('Detail', 'Industry', 'Profile', 10);
        detail.Widget__c = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        HXL_Widget_Field__mdt personOnly = row('Detail', 'Phone', null, 20);
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{ tile, detail, personOnly });
        Account a = new Account(Name = 'Configured Co', AnnualRevenue = 2500000000.0, Industry = 'Energy');
        insert a;

        de_HXL_GetAccount360.Result r = run(a.Id);

        Assert.isTrue(r.isBusinessAccount);
        Assert.areEqual('Firmographics', r.personTilesTitle);
        Assert.areEqual('$2.5B', r.personTiles[0].valueDisplay);
        Assert.areEqual(1, r.personDetails.size(), 'Person rows stay off the business view');
        Assert.areEqual('Energy', r.personDetails[0].valueDisplay);
        Assert.isTrue(r.hasPersonDetails);
    }

    @IsTest
    static void businessAccountKeepsBuiltInStripWithoutSummaryRows() {
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>());
        Account a = new Account(Name = 'Stock Co', AnnualRevenue = 5000000);
        insert a;

        de_HXL_GetAccount360.Result r = run(a.Id);

        Assert.isTrue(r.hasBuiltInSummary);
        Assert.isFalse(r.hasSummary);
        Assert.isNull(r.summaryTiles);
    }

    @IsTest
    static void summaryRowsReplaceTheBuiltInStrip() {
        List<HXL_Widget_Field__mdt> rows = new List<HXL_Widget_Field__mdt>();
        for (String f : new List<String>{ 'Industry', 'NumberOfEmployees', 'AnnualRevenue', 'Phone', 'Website' }) {
            HXL_Widget_Field__mdt kpi = row('Summary', f, null, (rows.size() + 1) * 10);
            kpi.Widget__c = de_HXL_PersonAccountView.BUSINESS_WIDGET;
            rows.add(kpi);
        }
        de_HXL_FieldConfig.useRows(rows);
        Account a = new Account(
            Name = 'Dealer Co', Industry = 'Energy', NumberOfEmployees = 67, AnnualRevenue = 2500000000.0,
            Phone = '555-0100', Website = 'example.com'
        );
        insert a;

        de_HXL_GetAccount360.Result r = run(a.Id);

        Assert.isFalse(r.hasBuiltInSummary);
        Assert.isTrue(r.hasSummary);
        Assert.areEqual(de_HXL_PersonAccountView.SUMMARY_SLOTS, r.summaryTiles.size(), 'The strip holds 4');
        Assert.areEqual('Energy', r.summaryTiles[0].valueDisplay);
        Assert.areEqual('$2.5B', r.summaryTiles[2].valueDisplay);
    }

    @IsTest
    static void blankSummaryRowsStillHideTheBuiltInStrip() {
        HXL_Widget_Field__mdt kpi = row('Summary', 'Industry', null, 10);
        kpi.Widget__c = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        kpi.Hide_When_Blank__c = true;
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{ kpi });
        Account a = new Account(Name = 'Blank Co');
        insert a;

        de_HXL_GetAccount360.Result r = run(a.Id);

        Assert.isFalse(r.hasBuiltInSummary);
        Assert.isFalse(r.hasSummary);
        Assert.isNull(r.summaryTiles);
    }

    @IsTest
    static void tilesShowAsGaugesAndBadges() {
        HXL_Widget_Field__mdt score = row('Tile', 'NumberOfEmployees', null, 10);
        score.Column_Type__c = 'Gauge';
        HXL_Widget_Field__mdt capped = row('Tile', 'AnnualRevenue', null, 20);
        capped.Column_Type__c = 'Gauge';
        capped.Format__c = 'Number';
        HXL_Widget_Field__mdt textGauge = row('Tile', 'Name', null, 30);
        textGauge.Column_Type__c = 'Gauge';
        HXL_Widget_Field__mdt status = row('Summary', 'Industry', null, 10);
        status.Column_Type__c = 'Badge';
        status.Value_Map__c = 'Energy=warning; Retail=success';
        HXL_Widget_Field__mdt unmapped = row('Summary', 'Rating', null, 20);
        unmapped.Column_Type__c = 'Badge';
        unmapped.Fallback__c = 'Info';
        HXL_Widget_Field__mdt plain = row('Summary', 'Phone', null, 30);
        List<HXL_Widget_Field__mdt> rows = new List<HXL_Widget_Field__mdt>{ score, capped, textGauge, status, unmapped, plain };
        for (HXL_Widget_Field__mdt r : rows) {
            r.Widget__c = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        }
        de_HXL_FieldConfig.useRows(rows);
        Account a = new Account(
            Name = 'Gauge Co', NumberOfEmployees = 62, AnnualRevenue = 250, Industry = 'Energy', Rating = 'Hot'
        );
        insert a;

        de_HXL_GetAccount360.Result r = run(a.Id);

        de_HXL_GetAccount360.Tile gauge = r.personTiles[0];
        Assert.isTrue(gauge.isGauge);
        Assert.isTrue(gauge.showsText, 'A gauge keeps its value above the bar');
        Assert.isFalse(gauge.isBadge);
        Assert.areEqual(62, gauge.gaugeValue);
        Assert.areEqual('warning', gauge.gaugeVariant);
        Assert.areEqual(100, r.personTiles[1].gaugeValue, 'Clamped to 100');
        Assert.areEqual('success', r.personTiles[1].gaugeVariant);
        Assert.isFalse(r.personTiles[2].isGauge, 'A text field shows as text');
        Assert.isTrue(r.personTiles[2].showsText);

        de_HXL_GetAccount360.Tile badge = r.summaryTiles[0];
        Assert.isTrue(badge.isBadge);
        Assert.isFalse(badge.showsText);
        Assert.areEqual('warning', badge.badgeVariant);
        Assert.areEqual('info', r.summaryTiles[1].badgeVariant, 'No match uses the Fallback');
        Assert.isTrue(r.summaryTiles[2].showsText);
        Assert.isFalse(r.summaryTiles[2].isBadge);
        Assert.isFalse(r.summaryTiles[2].isGauge);
        Assert.areEqual('secondary', r.summaryTiles[2].badgeVariant, 'Unused flags are still set');
    }

    @IsTest
    static void blankGaugeAndBadgeTilesShowAsText() {
        HXL_Widget_Field__mdt gauge = row('Tile', 'NumberOfEmployees', null, 10);
        gauge.Column_Type__c = 'Gauge';
        HXL_Widget_Field__mdt badge = row('Tile', 'Industry', null, 20);
        badge.Column_Type__c = 'Badge';
        gauge.Widget__c = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        badge.Widget__c = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{ gauge, badge });
        Account a = new Account(Name = 'Blank Gauge Co');
        insert a;

        de_HXL_GetAccount360.Result r = run(a.Id);

        for (de_HXL_GetAccount360.Tile t : r.personTiles) {
            Assert.areEqual('N/A', t.valueDisplay);
            Assert.isTrue(t.showsText);
            Assert.isFalse(t.isGauge);
            Assert.isFalse(t.isBadge);
        }
    }

    @IsTest
    static void personAccountShowsItsSummaryStrip() {
        if (!de_HXL_PersonAccountView.personAccountsEnabled()) {
            return;
        }
        HXL_Widget_Field__mdt revenue = row('Summary', 'AnnualRevenue', null, 10);
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{ revenue });
        SObject a = personAccount();
        if (a == null) {
            return;
        }

        de_HXL_GetAccount360.Result r = run(a.Id);

        Assert.isTrue(r.isPersonAccount);
        Assert.isFalse(r.hasBuiltInSummary, 'Person accounts have no built-in strip');
        Assert.isTrue(r.hasSummary);
        Assert.areEqual('$127K', r.summaryTiles[0].valueDisplay);
    }

    @IsTest
    static void tileTitleSurvivesItsTileBeingHidden() {
        HXL_Widget_Field__mdt segment = row('Tile', 'Industry', 'Account Insights', 10);
        segment.Widget__c = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        segment.Hide_When_Blank__c = true;
        HXL_Widget_Field__mdt revenue = row('Tile', 'AnnualRevenue', null, 20);
        revenue.Widget__c = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{ segment, revenue });
        Account a = new Account(Name = 'No Industry Co', AnnualRevenue = 5000);
        insert a;

        de_HXL_GetAccount360.Result r = run(a.Id);

        Assert.areEqual(1, r.personTiles.size(), 'Blank Industry is hidden');
        Assert.areEqual('Account Insights', r.personTilesTitle);
    }

    @IsTest
    static void accountWithoutAssetsShowsEmptyList() {
        if (!de_HXL_PersonAccountView.personAccountsEnabled()) {
            return;
        }
        useStandardConfig();
        SObject a = personAccount();
        if (a == null) {
            return;
        }

        de_HXL_GetAccount360.Result r = run(a.Id);

        Assert.isFalse(r.hasDevices);
        Assert.isNull(r.devices);
        Assert.isTrue(r.hasList1);
        Assert.isTrue(r.list1IsEmpty);
        Assert.isFalse(r.list1IsCard);
        Assert.isNull(r.list1Rows, 'Empty lists go out as null so the card still renders');
        Assert.areEqual('No devices', r.list1EmptyText);
        Assert.areEqual('0 assets', r.list1Summary);
        Assert.isTrue(r.hasPersonTiles);
        // Business-only meta.if inputs must still be set, or HXL fails to evaluate them.
        Assert.isFalse(r.hasEmployees);
        Assert.isFalse(r.hasArrDelta);
        Assert.areEqual('', r.openPipelineDisplay);
        Assert.areEqual('—', r.openPipelineAmount);
    }
}
