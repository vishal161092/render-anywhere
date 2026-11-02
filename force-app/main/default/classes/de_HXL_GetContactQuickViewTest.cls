@IsTest
private class de_HXL_GetContactQuickViewTest {

    private static de_HXL_GetContactQuickView.Result run(String ref) {
        de_HXL_GetContactQuickView.Request req = new de_HXL_GetContactQuickView.Request();
        req.contactRef = ref;
        return de_HXL_GetContactQuickView.getView(new List<de_HXL_GetContactQuickView.Request>{ req })[0].view;
    }

    @IsTest
    static void buildsViewWithRecentActivities() {
        Account a = new Account(Name = 'Quick View Co');
        insert a;
        Contact c = new Contact(
            FirstName = 'Mark', LastName = 'Kingston', Title = 'Director',
            Email = 'mark@example.com', Phone = '(555) 010-2000', AccountId = a.Id
        );
        insert c;
        // Description is set because some demo org triggers dereference it on Call tasks.
        insert new Task(
            Subject = 'Follow-up call', WhoId = c.Id, ActivityDate = Date.today().addDays(-2),
            Description = 'Follow-up on renewal'
        );
        insert new Event(
            Subject = 'QBR', WhoId = c.Id, ActivityDateTime = Datetime.now().addDays(-10),
            DurationInMinutes = 30
        );
        Test.setFixedSearchResults(new List<Id>{ c.Id });

        de_HXL_GetContactQuickView.Result r = run('Jane Doe');

        Assert.areEqual('Jane Doe', r.name);
        Assert.areEqual('MK', r.initials);
        Assert.areEqual('Quick View Co', r.accountName);
        Assert.areEqual('mailto:mark@example.com', r.emailHref);
        Assert.areEqual('tel:5550102000', r.phoneHref);
        Assert.areEqual(2, r.recentActivities.size());
        Assert.areEqual('Follow-up call', r.recentActivities[0].subject, 'Newest first');
    }

    private static HXL_Widget_Field__mdt field(String section, String path, String groupTitle, Decimal order) {
        return new HXL_Widget_Field__mdt(
            Widget__c = de_HXL_GetContactQuickView.WIDGET, Section__c = section, Field_API_Name__c = path,
            Group__c = groupTitle, Active__c = true, Sort_Order__c = order, Format__c = 'Auto'
        );
    }

    @IsTest
    static void configuredDetailsShowUnderContactMethods() {
        HXL_Widget_Field__mdt department = field('Detail', 'Department', 'Role', 20);
        department.Hide_When_Blank__c = true;
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{
            field('Detail', 'Title', 'Role', 10), department, field('Detail', 'LeadSource', 'Source', 30)
        });
        Contact c = new Contact(FirstName = 'Ana', LastName = 'Lopez', Title = 'CFO');
        insert c;

        de_HXL_GetContactQuickView.Result r = run(c.Id);

        Assert.isTrue(r.hasDetails);
        Assert.areEqual(2, r.details.size(), 'Blank Department is hidden');
        Assert.areEqual('CFO', r.details[0].valueDisplay);
        Assert.isTrue(r.details[0].isGroupStart);
        Assert.areEqual('—', r.details[1].valueDisplay, 'Blank LeadSource shows a dash');
        Assert.isTrue(r.details[1].isGroupStart, 'New group starts');
    }

    @IsTest
    static void unknownContactReturnsEmptyResult() {
        Assert.isNull(run('nobody here').name);
        Assert.isFalse(run('nobody here').hasDetails, 'Flags are set even with no match');
    }
}
