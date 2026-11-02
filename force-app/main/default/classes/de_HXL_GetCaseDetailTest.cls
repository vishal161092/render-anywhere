@IsTest
private class de_HXL_GetCaseDetailTest {

    private static de_HXL_GetCaseDetail.Result run(String ref) {
        de_HXL_GetCaseDetail.Request req = new de_HXL_GetCaseDetail.Request();
        req.caseRef = ref;
        return de_HXL_GetCaseDetail.getDetail(new List<de_HXL_GetCaseDetail.Request>{ req })[0].detail;
    }

    private static HXL_Widget_Field__mdt field(String section, String path, String groupTitle, Decimal order) {
        return new HXL_Widget_Field__mdt(
            Widget__c = de_HXL_GetCaseDetail.WIDGET, Section__c = section, Field_API_Name__c = path,
            Group__c = groupTitle, Active__c = true, Sort_Order__c = order, Format__c = 'Auto'
        );
    }

    @IsTest
    static void configuredDetailsShow() {
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{
            field('Detail', 'Origin', null, 10), field('Detail', 'Not_A_Field__c', null, 20)
        });
        Case cs = new Case(Subject = 'Configured case', Origin = 'Phone', Status = 'New');
        insert cs;

        de_HXL_GetCaseDetail.Result r = run(cs.Id);

        Assert.isTrue(r.hasDetails);
        Assert.areEqual(1, r.details.size(), 'Unknown fields are skipped');
        Assert.areEqual('Phone', r.details[0].valueDisplay);
    }

    @IsTest
    static void buildsDetailWithRelatedRecordsAndSla() {
        Account a = new Account(Name = 'Case Co');
        insert a;
        Contact c = new Contact(FirstName = 'Priya', LastName = 'Nair', AccountId = a.Id);
        insert c;
        Case cs = new Case(
            Subject = 'Billing invoice mismatch', Priority = 'High', Status = 'New',
            Origin = 'Email', AccountId = a.Id, ContactId = c.Id
        );
        insert cs;

        de_HXL_GetCaseDetail.Result r = run(cs.Id);

        Assert.areEqual('Billing invoice mismatch', r.subject);
        Assert.areEqual('Case Co', r.accountName);
        Assert.areEqual('PN', r.contactInitials);
        Assert.areEqual('error', r.priorityVariant);
        Assert.isNotNull(r.slaDueDisplay);
        Assert.isNotNull(r.kbArticles, 'KB list is always initialised (may be empty)');
    }

    @IsTest
    static void unknownCaseReturnsEmptyResult() {
        Assert.isNull(run('no such case').subject);
        Assert.isNull(run(null).subject);
        Assert.isFalse(run('no such case').hasDetails, 'Flags are set even with no match');
    }

    @IsTest
    static void keywordScoringMatchesStemsNotSubstrings() {
        Set<String> terms = de_HXL_GetCaseDetail.keywords('How do I recover my billing account?');
        Assert.isTrue(terms.contains('billing'));
        Assert.isFalse(terms.contains('how'), 'Stopwords dropped');

        Integer score = de_HXL_GetCaseDetail.overlapScore(terms, 'Billing FAQ', 'Account billing help');
        Assert.isTrue(score >= 3, 'Title hit + summary hit: ' + score);
        Assert.areEqual(0, de_HXL_GetCaseDetail.overlapScore(
            new Set<String>{ 'cover' }, 'Recover access', null), '"cover" must not match "recover"');
    }

    private static Knowledge__kav article(String title, String summary, String num, String published) {
        // ArticleNumber and LastPublishedDate are read-only, so build the row from JSON.
        return (Knowledge__kav) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Knowledge__kav' },
            'Title' => title, 'Summary' => summary, 'ArticleNumber' => num, 'LastPublishedDate' => published
        }), Knowledge__kav.class);
    }

    @IsTest
    static void ranksArticlesBestFirstAndKeepsThree() {
        Set<String> terms = de_HXL_GetCaseDetail.keywords('Billing invoice payment mismatch');
        List<Knowledge__kav> arts = new List<Knowledge__kav>{
            article('Billing invoice payment mismatch FAQ', 'Fix an invoice payment mismatch', '000101', '2026-01-02T00:00:00.000Z'),
            article('Billing invoice basics', 'Invoice payment help', '000102', '2026-03-02T00:00:00.000Z'),
            article('Billing invoice basics', 'Invoice payment help', '000103', null),
            article('Invoice payment billing', 'Billing mismatch', null, '2025-03-02T00:00:00.000Z'),
            article('Router reset steps', 'Power-cycle the router', '000105', '2026-03-02T00:00:00.000Z')
        };

        List<de_HXL_GetCaseDetail.KbArticle> top = de_HXL_GetCaseDetail.rankArticles(terms, arts);

        Assert.areEqual(3, top.size(), 'Top three only; the off-topic article never scores');
        Assert.areEqual('Billing invoice payment mismatch FAQ', top[0].title);
        Assert.areEqual('Invoice payment billing', top[1].title);
        Assert.isTrue(top[2].caption.startsWith('000102'), 'Score tie goes to the most recently published: ' + top[2].caption);
        Assert.isTrue(top[0].caption.startsWith('000101 • Updated '), top[0].caption);
        Assert.isTrue(de_HXL_GetCaseDetail.rankArticles(terms, new List<Knowledge__kav>()).isEmpty());
    }

    @IsTest
    static void priorityAndStatusPickBadgeColors() {
        List<Case> cases = new List<Case>{
            new Case(Subject = 'Low one', Priority = 'Low', Status = 'Closed'),
            new Case(Subject = 'Medium one', Priority = 'Medium', Status = 'Working'),
            new Case(Subject = 'No priority', Priority = null, Status = 'New')
        };
        insert cases;

        de_HXL_GetCaseDetail.Result low = run(cases[0].Id);
        de_HXL_GetCaseDetail.Result medium = run(cases[1].Id);
        de_HXL_GetCaseDetail.Result none = run(cases[2].Id);

        Assert.areEqual('info', low.priorityVariant);
        Assert.areEqual('success', low.statusVariant);
        Assert.areEqual('warning', medium.priorityVariant);
        Assert.areEqual('info', medium.statusVariant);
        Assert.areEqual('secondary', none.priorityVariant);
    }
}
