@IsTest
private class de_HXL_GetAccount360Test {

    private static de_HXL_GetAccount360.Result run(String ref) {
        de_HXL_GetAccount360.Request req = new de_HXL_GetAccount360.Request();
        req.accountRef = ref;
        return de_HXL_GetAccount360.getSnapshot(new List<de_HXL_GetAccount360.Request>{ req })[0].snapshot;
    }

    @IsTest
    static void buildsSnapshotWithContactsAndOpenPipeline() {
        Account a = new Account(
            Name = 'Omega 360', Industry = 'Energy', AnnualRevenue = 8400000,
            NumberOfEmployees = 4300, BillingCity = 'Denver', BillingState = 'CO'
        );
        insert a;
        insert new Contact(LastName = 'Rivera', Title = 'VP Ops', AccountId = a.Id);
        insert new Opportunity(
            Name = 'Omega Expansion', AccountId = a.Id, Amount = 420000,
            StageName = de_HXL_TestData.openStage(), CloseDate = Date.today().addDays(30)
        );

        de_HXL_GetAccount360.Result r = run(a.Id);

        Assert.areEqual('Omega 360', r.name);
        Assert.areEqual(1, r.contacts.size());
        Assert.areEqual(1, r.opportunities.size());
        Assert.isNotNull(r.healthDisplay);
        // Every meta.if input is set on the business view, or HXL fails to evaluate it.
        Assert.isTrue(r.hasEmployees);
        Assert.isFalse(r.hasArrDelta);
        Assert.isFalse(r.hasDevices);
        Assert.isTrue(r.salesforceUrl.endsWith('/lightning/r/Account/' + a.Id + '/view'));
    }

    @IsTest
    static void unknownAccountReturnsEmptyResult() {
        Assert.isNull(run('no such account').name);
        Assert.isNull(run(null).name);
        Assert.isFalse(run(null).hasDevices, 'Flags are set even with no account');
    }

    @IsTest
    static void standardUserSeesOwnAccount() {
        User rep = de_HXL_TestData.standardUser('hxla360');
        System.runAs(rep) {
            Account a = new Account(Name = 'Rep 360');
            insert a;
            Test.setFixedSearchResults(new List<Id>{ a.Id });
            Assert.areEqual('Rep 360', run('Rep 360').name);
        }
    }
}
