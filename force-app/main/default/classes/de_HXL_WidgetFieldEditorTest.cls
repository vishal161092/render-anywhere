@IsTest
private class de_HXL_WidgetFieldEditorTest {

    /** A Standard User holding the HXL_Widget_Field_Editor permission set. */
    private static User editor() {
        User u = de_HXL_TestData.standardUser('hxledit');
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :de_HXL_WidgetFieldEditor.PERMISSION LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    private static de_HXL_WidgetFieldEditor.Row row(String section, String path, Decimal order) {
        de_HXL_WidgetFieldEditor.Row r = new de_HXL_WidgetFieldEditor.Row();
        r.section = section;
        r.fieldPath = path;
        r.format = 'Auto';
        r.active = true;
        r.hideWhenBlank = false;
        r.sortOrder = order;
        return r;
    }

    private static String messageOf(Exception e) {
        return e == null ? '' : e.getMessage();
    }

    @IsTest
    static void everyMethodNeedsThePermission() {
        User plain = de_HXL_TestData.standardUser('hxlnone');
        System.runAs(plain) {
            Exception caught;
            try {
                de_HXL_WidgetFieldEditor.load();
            } catch (AuraHandledException e) {
                caught = e;
            }
            Assert.isTrue(messageOf(caught).contains('HXL Widget Field Editor'), 'Load is gated: ' + messageOf(caught));
            caught = null;
            try {
                de_HXL_WidgetFieldEditor.save(new List<de_HXL_WidgetFieldEditor.Row>{ row('Tile', 'Name', 10) }, null);
            } catch (AuraHandledException e) {
                caught = e;
            }
            Assert.isNotNull(caught, 'Save is gated');
        }
    }

    @IsTest
    static void loadReturnsWidgetsAndCheckedRows() {
        System.runAs(editor()) {
            de_HXL_WidgetFieldEditor.EditorState s = de_HXL_WidgetFieldEditor.load();

            Assert.areEqual(6, s.widgets.size());
            List<de_HXL_WidgetFieldEditor.Section> person = s.widgets[0].sections;
            Assert.areEqual(5, person.size());
            Assert.areEqual('Summary', person[0].name);
            Assert.areEqual(4, person[0].maxActive, 'The KPI strip holds 4');
            Assert.areEqual('Account', person[0].objectApiName);
            Assert.areEqual(1, person[3].listSlot);
            Assert.isNull(person[3].objectApiName, 'List columns read the list\'s object');
            Assert.areEqual('Summary', s.widgets[1].sections[0].name, 'Business has the KPI strip too');
            Assert.areEqual(2, s.widgets[1].sections[4].listSlot, 'Business has both list slots too');
            Assert.isNotNull(s.lists);
            Assert.isTrue(s.columnTypes.contains('Image'));
            Assert.areEqual(new List<String>{ 'Text', 'Badge', 'Gauge' }, person[0].tileTypes, 'KPIs can be badges or gauges');
            Assert.areEqual(person[0].tileTypes, person[1].tileTypes, 'Insight tiles too');
            Assert.isNull(person[2].tileTypes, 'Details have no display types');
            Assert.isTrue(s.icons.contains('plug'));
            Boolean offersContacts = false;
            for (de_HXL_WidgetFieldEditor.ListObject o : s.listObjects) {
                offersContacts |= o.value == 'Contact' && o.parentFields.contains('AccountId');
            }
            Assert.isTrue(offersContacts, 'Contact is a related-list object');
            Assert.areEqual(s.widgets[0].family, s.widgets[1].family, 'Person and Business share a card');
            Assert.areEqual(2, s.widgets[4].sections[0].maxActive, 'Pipeline rows have 2 detail slots');
            Assert.isTrue(s.formats.contains('Currency'));
            for (de_HXL_WidgetFieldEditor.Row r : s.rows) {
                Assert.isTrue(r.issue != null || r.fieldType != null, 'Each row is resolved or flagged: ' + r.fieldPath);
            }
        }
    }

    @IsTest
    static void describeFieldsOffersReadableFieldsAndLookupHops() {
        System.runAs(editor()) {
            Map<String, de_HXL_WidgetFieldEditor.FieldOption> byName = new Map<String, de_HXL_WidgetFieldEditor.FieldOption>();
            for (de_HXL_WidgetFieldEditor.FieldOption o : de_HXL_WidgetFieldEditor.describeFields('Asset')) {
                byName.put(o.value, o);
            }
            Assert.isTrue(byName.containsKey('Name'));
            Assert.areEqual('Product2', byName.get('Product2Id').relationshipName);
            Assert.areEqual('Product2', byName.get('Product2Id').referenceTo);

            Exception caught;
            try {
                de_HXL_WidgetFieldEditor.describeFields('Not_An_Object__x');
            } catch (AuraHandledException e) {
                caught = e;
            }
            Assert.isTrue(messageOf(caught).contains('Unknown object'));
        }
    }

    @IsTest
    static void saveRejectsRowsTheWidgetCantUse() {
        de_HXL_WidgetFieldEditor.Row blank = row('Tile', '', 10);
        de_HXL_WidgetFieldEditor.Row bogus = row('Detail', 'Bogus__c', 20);
        de_HXL_WidgetFieldEditor.Row longSuffix = row('Detail', 'Phone', 30);
        longSuffix.suffix = 'a suffix that is far too long';
        de_HXL_WidgetFieldEditor.Row badSection = row('Sidebar', 'Name', 40);
        de_HXL_WidgetFieldEditor.Row badWidget = row('Detail', 'Name', 50);
        badWidget.widget = 'Sidebar360';
        de_HXL_WidgetFieldEditor.Row noDevicesOnContacts = row('DeviceTitle', 'Name', 60);
        noDevicesOnContacts.widget = de_HXL_GetContactQuickView.WIDGET;

        System.runAs(editor()) {
            Exception caught;
            try {
                de_HXL_WidgetFieldEditor.save(new List<de_HXL_WidgetFieldEditor.Row>{
                    blank, bogus, longSuffix, badSection, badWidget, noDevicesOnContacts
                }, null);
            } catch (AuraHandledException e) {
                caught = e;
            }
            String msg = messageOf(caught);
            Assert.isTrue(msg.contains('pick a field'), msg);
            Assert.isTrue(msg.contains('Bogus__c isn\'t a readable field'), msg);
            Assert.isTrue(msg.contains('too long'), msg);
            Assert.isTrue(msg.contains('unknown section'), msg);
            Assert.isTrue(msg.contains('unknown widget'), msg);
        }
    }

    @IsTest
    static void inactiveRowsMaySaveWithAMissingField() {
        de_HXL_WidgetFieldEditor.Row off = row('Detail', 'Field_From_Another_Org__c', 10);
        off.active = false;
        System.runAs(editor()) {
            Assert.isNull(de_HXL_WidgetFieldEditor.save(new List<de_HXL_WidgetFieldEditor.Row>{ off }, null), 'No deploy in tests');
        }
    }

    @IsTest
    static void buildContainerSkipsUnchangedRowsAndNamesNewOnes() {
        HXL_Widget_Field__mdt saved = new HXL_Widget_Field__mdt(
            DeveloperName = 'PA_Tile_Revenue', MasterLabel = 'Tile: Revenue',
            Widget__c = 'PersonAccount360', Section__c = 'Tile', Field_API_Name__c = 'AnnualRevenue',
            Label__c = 'Revenue', Format__c = 'Auto', Active__c = true, Hide_When_Blank__c = false,
            Sort_Order__c = 10
        );
        Map<String, HXL_Widget_Field__mdt> savedMap = new Map<String, HXL_Widget_Field__mdt>{ 'PA_Tile_Revenue' => saved };

        de_HXL_WidgetFieldEditor.Row unchanged = row('Tile', 'AnnualRevenue', 10.0);
        unchanged.developerName = 'PA_Tile_Revenue';
        unchanged.label = 'Revenue';
        de_HXL_WidgetFieldEditor.Row caseOnly = row('Tile', 'AnnualRevenue', 10);
        caseOnly.developerName = 'PA_Tile_Revenue';
        caseOnly.label = 'REVENUE';
        de_HXL_WidgetFieldEditor.Row added = row('Tile', 'NumberOfEmployees', 20);
        added.label = 'Revenue';

        Metadata.DeployContainer c = de_HXL_WidgetFieldEditor.buildContainer(
            new List<de_HXL_WidgetFieldEditor.Row>{ unchanged }, savedMap
        );
        Assert.areEqual(0, c.getMetadata().size(), 'Unchanged row (10 vs 10.0) is skipped');

        c = de_HXL_WidgetFieldEditor.buildContainer(new List<de_HXL_WidgetFieldEditor.Row>{ caseOnly, added }, savedMap);
        List<Metadata.Metadata> mds = c.getMetadata();
        Assert.areEqual(2, mds.size(), 'A case-only edit counts as a change');
        Assert.areEqual('HXL_Widget_Field.PA_Tile_Revenue', mds[0].fullName);
        Assert.areEqual('Tile: Revenue', ((Metadata.CustomMetadata) mds[0]).label, 'Existing MasterLabel kept');
        Assert.areEqual('HXL_Widget_Field.PA_Tile_Revenue_2', mds[1].fullName, 'New name avoids the existing one');
        Assert.areEqual('Insight Tiles: Revenue', ((Metadata.CustomMetadata) mds[1]).label);

        de_HXL_WidgetFieldEditor.Row moved = row('Detail', 'AnnualRevenue', 10);
        moved.developerName = 'PA_Tile_Revenue';
        moved.label = 'Revenue';
        mds = de_HXL_WidgetFieldEditor.buildContainer(new List<de_HXL_WidgetFieldEditor.Row>{ moved }, savedMap).getMetadata();
        Assert.areEqual('HXL_Widget_Field.PA_Tile_Revenue', mds[0].fullName, 'A moved row keeps its record');
        Assert.areEqual('Details: Revenue', ((Metadata.CustomMetadata) mds[0]).label, 'and gets a label for its new section');
    }

    @IsTest
    static void uniqueNameIsAValidDeveloperName() {
        de_HXL_WidgetFieldEditor.Row r = row('List1Column', 'Product2.ProductCode', 10);
        r.label = 'Net Revenue (USD) — this quarter, all regions combined';
        String name = de_HXL_WidgetFieldEditor.uniqueName(r, new Set<String>());
        Assert.isTrue(name.length() <= 40, name);
        Assert.isTrue(Pattern.matches('[A-Za-z][A-Za-z0-9_]*[A-Za-z0-9]', name), name);
        Assert.isFalse(name.contains('__'), name);

        r = row('Detail', 'Title', 10);
        r.widget = de_HXL_GetContactQuickView.WIDGET;
        r.label = 'Title';
        Assert.areEqual('CQV_Detail_Title', de_HXL_WidgetFieldEditor.uniqueName(r, new Set<String>()));
    }

    @IsTest
    static void previewRunsUnsavedRowsThroughTheWidget() {
        de_HXL_WidgetFieldEditor.Row industry = row('Detail', 'Industry', 10);
        industry.widget = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        de_HXL_WidgetFieldEditor.Row title = row('Detail', 'Title', 10);
        title.widget = de_HXL_GetContactQuickView.WIDGET;
        de_HXL_WidgetFieldEditor.Row type = row('OpportunityDetail', 'Type', 10);
        type.widget = de_HXL_GetOpportunityPipeline.WIDGET;

        System.runAs(editor()) {
            Account business = new Account(Name = 'Business Co', Industry = 'Energy');
            insert business;
            Contact c = new Contact(LastName = 'Lopez', Title = 'CFO', AccountId = business.Id);
            insert c;
            Exception caught;
            try {
                de_HXL_WidgetFieldEditor.preview(new List<de_HXL_WidgetFieldEditor.Row>(), null, null, null);
            } catch (AuraHandledException e) {
                caught = e;
            }
            Assert.isTrue(messageOf(caught).contains('Account'), messageOf(caught));
            caught = null;
            try {
                de_HXL_WidgetFieldEditor.preview(new List<de_HXL_WidgetFieldEditor.Row>(), null, de_HXL_GetCaseDetail.WIDGET, c.Id);
            } catch (AuraHandledException e) {
                caught = e;
            }
            Assert.isTrue(messageOf(caught).contains('Case'), 'Record must match the widget: ' + messageOf(caught));
            caught = null;
            try {
                de_HXL_WidgetFieldEditor.preview(new List<de_HXL_WidgetFieldEditor.Row>(), null, 'Sidebar360', c.Id);
            } catch (AuraHandledException e) {
                caught = e;
            }
            Assert.isTrue(messageOf(caught).contains('Unknown widget'), messageOf(caught));

            Assert.isNull(
                de_HXL_WidgetFieldEditor.preview(new List<de_HXL_WidgetFieldEditor.Row>{ row('Tile', 'Name', 10) }, null,
                    de_HXL_PersonAccountView.WIDGET, business.Id),
                'Business accounts have no person view'
            );
            String json = de_HXL_WidgetFieldEditor.preview(new List<de_HXL_WidgetFieldEditor.Row>{ industry }, null,
                de_HXL_PersonAccountView.BUSINESS_WIDGET, business.Id);
            Assert.isTrue(json.contains('Energy'), json);
            json = de_HXL_WidgetFieldEditor.preview(new List<de_HXL_WidgetFieldEditor.Row>{ title }, null,
                de_HXL_GetContactQuickView.WIDGET, c.Id);
            Assert.isTrue(json.contains('"hasDetails":true'), json);
            json = de_HXL_WidgetFieldEditor.preview(new List<de_HXL_WidgetFieldEditor.Row>{ type }, null,
                de_HXL_GetOpportunityPipeline.WIDGET, UserInfo.getUserId());
            Assert.isNotNull(json);
        }
    }

    @IsTest
    static void previewRunsCaseDetail() {
        de_HXL_WidgetFieldEditor.Row origin = row('Detail', 'Origin', 10);
        origin.widget = de_HXL_GetCaseDetail.WIDGET;
        System.runAs(editor()) {
            Case cs = new Case(Subject = 'Preview case', Origin = 'Phone', Status = 'New');
            insert cs;
            String json = de_HXL_WidgetFieldEditor.preview(new List<de_HXL_WidgetFieldEditor.Row>{ origin }, null,
                de_HXL_GetCaseDetail.WIDGET, cs.Id);
            Assert.isTrue(json.contains('Phone'), json);
        }
    }

    @IsTest
    static void previewRunsAssetDetail() {
        de_HXL_WidgetFieldEditor.Row serial = row('Detail', 'SerialNumber', 10);
        serial.widget = de_HXL_GetAssetDetail.WIDGET;
        System.runAs(editor()) {
            Account acct = new Account(Name = 'Preview asset account');
            insert acct;
            Asset a = new Asset(Name = 'Preview asset', SerialNumber = 'SN-PREVIEW-1', AccountId = acct.Id);
            insert a;
            String json = de_HXL_WidgetFieldEditor.preview(new List<de_HXL_WidgetFieldEditor.Row>{ serial }, null,
                de_HXL_GetAssetDetail.WIDGET, a.Id);
            Assert.isTrue(json.contains('SN-PREVIEW-1'), json);
        }
    }

    @IsTest
    static void deployEventReportsOutcome() {
        Id jobId = '0Af000000000001';
        Metadata.DeployResult ok = new Metadata.DeployResult();
        ok.id = jobId;
        ok.status = Metadata.DeployStatus.Succeeded;
        HXL_Widget_Field_Deploy__e e = de_HXL_WidgetFieldEditor.toEvent(ok);
        Assert.isTrue(e.Success__c);
        Assert.areEqual(String.valueOf(jobId), e.Job_Id__c);

        Metadata.DeployMessage failure = new Metadata.DeployMessage();
        failure.fullName = 'HXL_Widget_Field.PA_Tile_X';
        failure.problem = 'bad value';
        Metadata.DeployResult bad = new Metadata.DeployResult();
        bad.status = Metadata.DeployStatus.Failed;
        bad.details = new Metadata.DeployDetails();
        bad.details.componentFailures = new List<Metadata.DeployMessage>{ failure };
        e = de_HXL_WidgetFieldEditor.toEvent(bad);
        Assert.isFalse(e.Success__c);
        Assert.areEqual('HXL_Widget_Field.PA_Tile_X: bad value', e.Message__c);

        Test.startTest();
        new de_HXL_WidgetFieldEditor.DeployHandler().handleResult(ok, null);
        Test.stopTest();
    }

    private static de_HXL_WidgetFieldEditor.ListDef listDef(Integer slot, String obj) {
        de_HXL_WidgetFieldEditor.ListDef l = new de_HXL_WidgetFieldEditor.ListDef();
        l.widget = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        l.slot = slot;
        l.active = true;
        l.title = 'Contacts';
        l.layout = 'Card';
        l.objectApiName = obj;
        l.parentField = 'AccountId';
        l.filter = 'All';
        return l;
    }

    private static de_HXL_WidgetFieldEditor.Row listColumn(Integer slot, String type, String path) {
        de_HXL_WidgetFieldEditor.Row r = row('List' + slot + 'Column', path, 10);
        r.widget = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        r.columnType = type;
        return r;
    }

    @IsTest
    static void saveChecksListsAndTheirColumns() {
        de_HXL_WidgetFieldEditor.ListDef good = listDef(1, 'Contact');
        de_HXL_WidgetFieldEditor.ListDef badParent = listDef(2, 'Contact');
        badParent.parentField = 'ReportsToId';
        badParent.icon = 'not-an-icon';
        de_HXL_WidgetFieldEditor.ListDef untouched = listDef(1, null);
        untouched.active = false;
        de_HXL_WidgetFieldEditor.Row title = listColumn(1, 'Subtitle', 'Title');
        de_HXL_WidgetFieldEditor.Row fixedIcon = listColumn(1, 'Icon', null);
        fixedIcon.fallback = 'users';
        de_HXL_WidgetFieldEditor.Row badImage = listColumn(1, 'Image', null);
        badImage.fallback = 'http://insecure.example/x.png';
        de_HXL_WidgetFieldEditor.Row badBadge = listColumn(1, 'Badge', 'Department');
        badBadge.valueMap = 'Sales=purple';
        de_HXL_WidgetFieldEditor.Row wrongObject = listColumn(1, 'Text', 'StageName');

        System.runAs(editor()) {
            Assert.isNull(de_HXL_WidgetFieldEditor.save(
                new List<de_HXL_WidgetFieldEditor.Row>{ title, fixedIcon },
                new List<de_HXL_WidgetFieldEditor.ListDef>{ good, untouched }
            ), 'Valid; no deploy in tests');

            Exception caught;
            try {
                de_HXL_WidgetFieldEditor.save(
                    new List<de_HXL_WidgetFieldEditor.Row>{ badImage, badBadge, wrongObject },
                    new List<de_HXL_WidgetFieldEditor.ListDef>{ good, badParent }
                );
            } catch (AuraHandledException e) {
                caught = e;
            }
            String msg = messageOf(caught);
            Assert.isTrue(msg.contains('icon the widget knows'), msg);
            Assert.isTrue(msg.contains('https://'), msg);
            Assert.isTrue(msg.contains('value map colour'), msg);
            Assert.isTrue(msg.contains('StageName isn\'t a readable field on Contact'), msg);

            badParent.icon = null;
            caught = null;
            try {
                de_HXL_WidgetFieldEditor.save(null, new List<de_HXL_WidgetFieldEditor.ListDef>{ badParent });
            } catch (AuraHandledException e) {
                caught = e;
            }
            Assert.isTrue(messageOf(caught).contains('lookup from Contact to Account'), messageOf(caught));

            de_HXL_WidgetFieldEditor.ListDef provider = listDef(2, null);
            provider.providerClass = 'de_HXL_Format';
            caught = null;
            try {
                de_HXL_WidgetFieldEditor.save(null, new List<de_HXL_WidgetFieldEditor.ListDef>{ provider });
            } catch (AuraHandledException e) {
                caught = e;
            }
            Assert.isTrue(messageOf(caught).contains('de_HXL_RelatedListProvider'), messageOf(caught));
        }
    }

    @IsTest
    static void saveChecksTileDisplayTypes() {
        de_HXL_WidgetFieldEditor.Row gauge = row('Tile', 'NumberOfEmployees', 10);
        gauge.widget = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        gauge.columnType = 'Gauge';
        de_HXL_WidgetFieldEditor.Row badge = row('Summary', 'Industry', 10);
        badge.widget = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        badge.columnType = 'Badge';
        badge.valueMap = 'Energy=warning';
        de_HXL_WidgetFieldEditor.Row link = row('Tile', 'Name', 20);
        link.widget = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        link.columnType = 'Link';
        de_HXL_WidgetFieldEditor.Row badFallback = row('Summary', 'Rating', 20);
        badFallback.widget = de_HXL_PersonAccountView.BUSINESS_WIDGET;
        badFallback.columnType = 'Badge';
        badFallback.fallback = 'purple';

        System.runAs(editor()) {
            Assert.isNull(de_HXL_WidgetFieldEditor.save(
                new List<de_HXL_WidgetFieldEditor.Row>{ gauge, badge }, null
            ), 'Valid; no deploy in tests');

            Exception caught;
            try {
                de_HXL_WidgetFieldEditor.save(new List<de_HXL_WidgetFieldEditor.Row>{ link, badFallback }, null);
            } catch (AuraHandledException e) {
                caught = e;
            }
            String msg = messageOf(caught);
            Assert.isTrue(msg.contains('unknown column type "Link"'), msg);
            Assert.isTrue(msg.contains('fallback badge colour'), msg);
        }
    }

    @IsTest
    static void addListsSkipsUnchangedAndNamesNewOnes() {
        HXL_Related_List__mdt saved = new HXL_Related_List__mdt(
            DeveloperName = 'BA_Contacts', MasterLabel = 'Business 1: Contacts',
            Widget__c = de_HXL_PersonAccountView.BUSINESS_WIDGET, Slot__c = 1, Active__c = true, Title__c = 'Contacts',
            Layout__c = 'Card', Object__c = 'Contact', Parent_Field__c = 'AccountId', Filter__c = 'All',
            Sort_Descending__c = true
        );
        Map<String, HXL_Related_List__mdt> savedMap = new Map<String, HXL_Related_List__mdt>{ 'BA_Contacts' => saved };
        de_HXL_WidgetFieldEditor.ListDef unchanged = listDef(1, 'Contact');
        unchanged.developerName = 'BA_Contacts';
        de_HXL_WidgetFieldEditor.ListDef added = listDef(2, 'Case');
        added.title = 'Open Cases';
        added.layout = 'Table';

        Metadata.DeployContainer c = new Metadata.DeployContainer();
        de_HXL_WidgetFieldEditor.addLists(c, new List<de_HXL_WidgetFieldEditor.ListDef>{ unchanged, added }, savedMap);

        List<Metadata.Metadata> mds = c.getMetadata();
        Assert.areEqual(1, mds.size(), 'Unchanged list skipped');
        Assert.areEqual('HXL_Related_List.BA_List2_Open_Cases', mds[0].fullName);
        Assert.areEqual('Business Account 2: Open Cases', ((Metadata.CustomMetadata) mds[0]).label);
    }

    @IsTest
    static void previewRunsUnsavedLists() {
        de_HXL_WidgetFieldEditor.ListDef contacts = listDef(1, 'Contact');
        de_HXL_WidgetFieldEditor.Row name = listColumn(1, 'Link', 'LastName');
        System.runAs(editor()) {
            Account a = new Account(Name = 'Listed Co');
            insert a;
            insert new Contact(LastName = 'Okafor', AccountId = a.Id);
            String json = de_HXL_WidgetFieldEditor.preview(new List<de_HXL_WidgetFieldEditor.Row>{ name },
                new List<de_HXL_WidgetFieldEditor.ListDef>{ contacts }, de_HXL_PersonAccountView.BUSINESS_WIDGET, a.Id);
            Assert.isTrue(json.contains('"hasList1":true'), json);
            Assert.isTrue(json.contains('Okafor'), json);
        }
    }
}
