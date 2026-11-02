@IsTest
private class de_HXL_FieldConfigTest {

    private static HXL_Widget_Field__mdt row(String section, String path, Decimal order) {
        return new HXL_Widget_Field__mdt(
            Widget__c = 'PersonAccount360', Section__c = section, Field_API_Name__c = path,
            Active__c = true, Sort_Order__c = order, Format__c = 'Auto'
        );
    }

    @IsTest
    static void fieldsSkipsInvalidInactiveAndOtherSectionsAndSorts() {
        HXL_Widget_Field__mdt inactive = row('Tile', 'Industry', 1);
        inactive.Active__c = false;
        HXL_Widget_Field__mdt labelled = row('Tile', 'NumberOfEmployees', 5);
        labelled.Label__c = 'Headcount';
        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{
            row('Tile', 'AnnualRevenue', 10),
            labelled,
            row('Tile', 'Not_A_Real_Field__c', 2),
            row('Detail', 'Phone', 1),
            inactive
        });

        List<de_HXL_FieldConfig.Field> tiles = de_HXL_FieldConfig.fields('PersonAccount360', 'Tile', Account.SObjectType);

        Assert.areEqual(2, tiles.size(), 'Missing field, inactive row and other section are skipped');
        Assert.areEqual('Headcount', tiles[0].label, 'Sorted by Sort_Order__c; Label__c overrides');
        Assert.areEqual(
            Schema.SObjectType.Account.fields.AnnualRevenue.getLabel(), tiles[1].label,
            'Blank label falls back to the field label'
        );
        Assert.isTrue(de_HXL_FieldConfig.paths(tiles).contains('annualrevenue'));
    }

    @IsTest
    static void resolveWalksRelationshipsAndRejectsUnknownPaths() {
        Assert.isNotNull(de_HXL_FieldConfig.resolve(Account.SObjectType, 'Name'));
        Assert.isNotNull(de_HXL_FieldConfig.resolve(Contact.SObjectType, 'Account.Name'));
        Assert.isNotNull(de_HXL_FieldConfig.resolve(Asset.SObjectType, 'Product2.Name'));
        Assert.isNull(de_HXL_FieldConfig.resolve(Account.SObjectType, 'Bogus__c'));
        Assert.isNull(de_HXL_FieldConfig.resolve(Account.SObjectType, 'Bogus.Name'));
    }

    @IsTest
    static void displayFormatsByTypeAndAppliesSuffix() {
        Account a = new Account(Name = 'Formats', AnnualRevenue = 8400000, NumberOfEmployees = 12);
        insert a;
        Contact c = new Contact(LastName = 'Path', AccountId = a.Id);
        insert c;
        c = [SELECT Id, Account.Name, Account.AnnualRevenue FROM Contact WHERE Id = :c.Id];
        a = [SELECT Id, Name, AnnualRevenue, NumberOfEmployees, Phone, CreatedDate FROM Account WHERE Id = :a.Id];

        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{ row('Tile', 'NumberOfEmployees', 1) });
        de_HXL_FieldConfig.Field f = de_HXL_FieldConfig.fields('PersonAccount360', 'Tile', Account.SObjectType)[0];
        f.suffix = 'tons';
        Assert.areEqual('12 tons', de_HXL_FieldConfig.display(a, f), 'Word suffix gets a space');
        f.suffix = '%';
        Assert.areEqual('12%', de_HXL_FieldConfig.display(a, f), 'Symbol suffix does not');

        de_HXL_FieldConfig.useRows(new List<HXL_Widget_Field__mdt>{
            row('Tile', 'AnnualRevenue', 1), row('Tile', 'Phone', 2), row('Tile', 'CreatedDate', 3)
        });
        List<de_HXL_FieldConfig.Field> fs = de_HXL_FieldConfig.fields('PersonAccount360', 'Tile', Account.SObjectType);
        Assert.areEqual('$8.4M', de_HXL_FieldConfig.display(a, fs[0]));
        Assert.areEqual('', de_HXL_FieldConfig.display(a, fs[1]), 'Blank value is empty');
        Assert.isTrue(String.isNotBlank(de_HXL_FieldConfig.display(a, fs[2])));

        Assert.areEqual('Formats', de_HXL_FieldConfig.valueAt(c, 'Account.Name'));
        Assert.isNull(de_HXL_FieldConfig.valueAt(new Contact(), 'Account.Name'));
    }

    @IsTest
    static void formatCoversEachDisplayStyle() {
        Assert.areEqual('85%', de_HXL_FieldConfig.format(85, 'Percent'));
        Assert.areEqual('$274.56', de_HXL_FieldConfig.format(274.56, 'Currency'));
        Assert.areEqual('2.4', de_HXL_FieldConfig.format(2.4, 'Number'));
        Assert.areEqual('1,250', de_HXL_FieldConfig.format(1250, 'Number'));
        Assert.areEqual('Yes', de_HXL_FieldConfig.format(true, 'Text'));
        Assert.areEqual('Jul 3, 2026', de_HXL_FieldConfig.format(Date.newInstance(2026, 7, 3), 'Date'), 'No time-zone shift');
        Assert.areEqual('Homeowner', de_HXL_FieldConfig.format('Homeowner', 'Auto'));

        Assert.areEqual('Percent', de_HXL_FieldConfig.autoFormat(Schema.DisplayType.PERCENT));
        Assert.areEqual('Currency', de_HXL_FieldConfig.autoFormat(Schema.DisplayType.CURRENCY));
        Assert.areEqual('Number', de_HXL_FieldConfig.autoFormat(Schema.DisplayType.DOUBLE));
        Assert.areEqual('Date', de_HXL_FieldConfig.autoFormat(Schema.DisplayType.DATE));
        Assert.areEqual('Text', de_HXL_FieldConfig.autoFormat(Schema.DisplayType.STRING));
    }

    @IsTest
    static void shippedDefaultsAreReadable() {
        // Uses the deployed HXL_Widget_Field__mdt records; only asserts the call is safe.
        Assert.isNotNull(de_HXL_FieldConfig.fields('PersonAccount360', 'Detail', Account.SObjectType));
    }
}
