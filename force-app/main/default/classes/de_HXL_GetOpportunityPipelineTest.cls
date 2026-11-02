@IsTest
private class de_HXL_GetOpportunityPipelineTest {

    private static de_HXL_GetOpportunityPipeline.Result run(String userRef) {
        de_HXL_GetOpportunityPipeline.Request req = new de_HXL_GetOpportunityPipeline.Request();
        req.userRef = userRef;
        return de_HXL_GetOpportunityPipeline.getPipeline(
            new List<de_HXL_GetOpportunityPipeline.Request>{ req })[0].pipeline;
    }

    @IsTest
    static void blankUserRefReturnsMyPipeline() {
        Account a = new Account(Name = 'Pipeline Co');
        insert a;
        insert new List<Opportunity>{
            new Opportunity(Name = 'Open Deal', AccountId = a.Id, Amount = 100000, Probability = 50,
                StageName = de_HXL_TestData.openStage(), CloseDate = Date.today().addDays(10)),
            new Opportunity(Name = 'Won Deal', AccountId = a.Id, Amount = 50000,
                StageName = de_HXL_TestData.wonStage(), CloseDate = Date.today())
        };

        de_HXL_GetOpportunityPipeline.Result r = run(null);

        Assert.areEqual(UserInfo.getName(), r.userName);
        Assert.areEqual(1, r.opportunities.size());
        Assert.areEqual('$100K', r.openAmountDisplay);
        Assert.isNotNull(r.quotaAttainmentDisplay);
    }

    private static HXL_Widget_Field__mdt field(String section, String path, String groupTitle, Decimal order) {
        return new HXL_Widget_Field__mdt(
            Widget__c = de_HXL_GetOpportunityPipeline.WIDGET, Section__c = section, Field_API_Name__c = path,
            Group__c = groupTitle, Active__c = true, Sort_Order__c = order, Format__c = 'Auto'
        );
    }

    @IsTest
    static void opportunityRowsShowTwoConfiguredDetails() {
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{
            field('OpportunityDetail', 'Probability', null, 10),
            field('OpportunityDetail', 'Account.Name', null, 20),
            field('OpportunityDetail', 'Type', null, 30)
        });
        Account a = new Account(Name = 'Detail Co');
        insert a;
        insert new Opportunity(Name = 'Detail Deal', AccountId = a.Id, Amount = 1000, Probability = 25,
            StageName = de_HXL_TestData.openStage(), CloseDate = Date.today().addDays(5));

        de_HXL_GetOpportunityPipeline.OpportunityRow row = run(null).opportunities[0];

        Assert.isTrue(row.hasDetail1);
        Assert.areEqual('25%', row.detail1Value);
        Assert.isTrue(row.hasDetail2);
        Assert.areEqual('Detail Co', row.detail2Value, 'Lookup paths work; the third row is ignored');
    }

    @IsTest
    static void namedUserAndUnknownUser() {
        User rep = de_HXL_TestData.standardUser('hxlpipe');
        Test.setFixedSearchResults(new List<Id>{ rep.Id });
        Assert.areEqual(rep.Id, de_HXL_Resolve.toUserId('HXL hxlpipe'));
        Assert.areEqual('HXL hxlpipe', run('HXL hxlpipe').userName);

        Test.setFixedSearchResults(new List<Id>());
        Assert.isNull(run('Nobody Atall').userName);
    }
}
