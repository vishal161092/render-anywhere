@IsTest
private class de_HXL_GetAssetDetailTest {

    private static de_HXL_GetAssetDetail.Result run(String ref) {
        de_HXL_GetAssetDetail.Request req = new de_HXL_GetAssetDetail.Request();
        req.assetRef = ref;
        return de_HXL_GetAssetDetail.getDetail(new List<de_HXL_GetAssetDetail.Request>{ req })[0].detail;
    }

    private static HXL_Widget_Field__mdt field(String section, String path, String groupTitle, Decimal order) {
        return new HXL_Widget_Field__mdt(
            Widget__c = de_HXL_GetAssetDetail.WIDGET, Section__c = section, Field_API_Name__c = path,
            Group__c = groupTitle, Active__c = true, Sort_Order__c = order, Format__c = 'Auto'
        );
    }

    private static Asset newAsset(String name, Id accountId, Date install, Date usageEnd, String status) {
        return new Asset(
            Name = name, AccountId = accountId, Status = status, SerialNumber = 'SN-' + name,
            Quantity = 2, Price = 1250, InstallDate = install, PurchaseDate = install,
            UsageEndDate = usageEnd, Description = 'Field unit for testing.'
        );
    }

    @IsTest
    static void buildsDetailWithRelatedRecordsAndActiveLifecycle() {
        Account a = new Account(Name = 'Asset Co');
        insert a;
        Contact c = new Contact(FirstName = 'Priya', LastName = 'Nair', AccountId = a.Id);
        insert c;
        Asset asset = newAsset('Turbine A', a.Id, Date.today().addDays(-100), Date.today().addDays(200), 'Installed');
        asset.ContactId = c.Id;
        insert asset;

        de_HXL_GetAssetDetail.Result r = run(asset.Id);

        Assert.areEqual('Turbine A', r.assetName);
        Assert.areEqual('Asset Co', r.accountName);
        Assert.areEqual('PN', r.contactInitials);
        Assert.areEqual('success', r.statusVariant);
        Assert.areEqual('$1,250', r.priceDisplay);
        Assert.isTrue(r.hasLifecycle);
        Assert.areEqual('Active', r.lifecycleStatus);
        Assert.areEqual('success', r.lifecycleColor);
        Assert.isTrue(r.salesforceUrl.contains('/Asset/'));
    }

    @IsTest
    static void lifecycleFlagsExpiringAndExpired() {
        Account a = new Account(Name = 'Asset Co');
        insert a;
        List<Asset> assets = new List<Asset>{
            newAsset('Expiring', a.Id, Date.today().addDays(-100), Date.today().addDays(30), 'Registered'),
            newAsset('Expired', a.Id, Date.today().addDays(-400), Date.today().addDays(-10), 'Obsolete'),
            newAsset('NoEnd', a.Id, Date.today().addDays(-10), null, 'Shipped')
        };
        insert assets;

        de_HXL_GetAssetDetail.Result expiring = run(assets[0].Id);
        de_HXL_GetAssetDetail.Result expired = run(assets[1].Id);
        de_HXL_GetAssetDetail.Result noEnd = run(assets[2].Id);

        Assert.areEqual('Expiring soon', expiring.lifecycleStatus);
        Assert.areEqual('warning', expiring.lifecycleVariant);
        Assert.areEqual('Expired', expired.lifecycleStatus);
        Assert.areEqual('error', expired.lifecycleColor);
        Assert.isFalse(noEnd.hasLifecycle, 'No usage-end date hides the lifecycle section');
    }

    @IsTest
    static void configuredDetailsShow() {
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{
            field('Detail', 'SerialNumber', null, 10), field('Detail', 'Not_A_Field__c', null, 20)
        });
        Account a = new Account(Name = 'Asset Co');
        insert a;
        Asset asset = newAsset('Configured', a.Id, Date.today().addDays(-10), Date.today().addDays(10), 'Installed');
        insert asset;

        de_HXL_GetAssetDetail.Result r = run(asset.Id);

        Assert.isTrue(r.hasDetails);
        Assert.areEqual(1, r.details.size(), 'Unknown fields are skipped');
        Assert.areEqual('SN-Configured', r.details[0].valueDisplay);
    }

    @IsTest
    static void resolvesByNameViaSearch() {
        Account a = new Account(Name = 'Asset Co');
        insert a;
        Asset asset = newAsset('Findable Turbine', a.Id, Date.today().addDays(-5), Date.today().addDays(5), 'Installed');
        insert asset;
        Test.setFixedSearchResults(new List<Id>{ asset.Id });

        de_HXL_GetAssetDetail.Result r = run('Findable Turbine');

        Assert.areEqual('Findable Turbine', r.assetName);
    }

    @IsTest
    static void unknownAssetReturnsEmptyResult() {
        Assert.isNull(run('no such asset').assetName);
        Assert.isNull(run(null).assetName);
        de_HXL_GetAssetDetail.Result empty = run('no such asset');
        Assert.isFalse(empty.hasDetails, 'Flags are set even with no match');
        Assert.isFalse(empty.hasLifecycle, 'Flags are set even with no match');
    }

    @IsTest
    static void statusVariantCoversPicklist() {
        Assert.areEqual('success', de_HXL_GetAssetDetail.statusVariant('Installed'));
        Assert.areEqual('success', de_HXL_GetAssetDetail.statusVariant('Registered'));
        Assert.areEqual('error', de_HXL_GetAssetDetail.statusVariant('Obsolete'));
        Assert.areEqual('info', de_HXL_GetAssetDetail.statusVariant('Shipped'));
        Assert.areEqual('secondary', de_HXL_GetAssetDetail.statusVariant(null));
    }
}
