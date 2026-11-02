@IsTest
private class de_HXL_SearchTest {

    private static List<de_HXL_Search.Row> run(String objectType, String query, Integer maxResults) {
        de_HXL_Search.Request req = new de_HXL_Search.Request();
        req.objectType = objectType;
        req.query = query;
        req.maxResults = maxResults;
        return de_HXL_Search.search(new List<de_HXL_Search.Request>{ req })[0].matches;
    }

    @IsTest
    static void accountsComeBackMineFirstAndTagged() {
        User other = de_HXL_TestData.standardUser('hxlsrt1');
        Account theirs = new Account(Name = 'Acme Search', OwnerId = other.Id, Industry = 'Technology');
        insert theirs;
        Account mine = new Account(Name = 'Acme Search', BillingCity = 'Austin', BillingState = 'TX');
        insert mine;
        Test.setFixedSearchResults(new List<Id>{ theirs.Id, mine.Id });

        List<de_HXL_Search.Row> rows = run('Account', 'Acme', null);

        Assert.areEqual(2, rows.size());
        Assert.areEqual(mine.Id, rows[0].id);
        Assert.isTrue(rows[0].isMine);
        Assert.isTrue(rows[0].sublabel.startsWith('Yours'), rows[0].sublabel);
        Assert.isFalse(rows[1].isMine);
        Assert.areEqual('Technology', rows[1].sublabel);
    }

    @IsTest
    static void maxResultsCapsRows() {
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accts.add(new Account(Name = 'Capped ' + i));
        }
        insert accts;
        Test.setFixedSearchResults(new List<Id>(new Map<Id, Account>(accts).keySet()));

        Assert.areEqual(1, run('Account', 'Capped', 1).size());
        Assert.areEqual(3, run('Account', 'Capped', 100).size(), 'Over-max is clamped, not rejected');
    }

    @IsTest
    static void contactsAndCasesReturnRows() {
        Account a = new Account(Name = 'Search Parent');
        insert a;
        Contact c = new Contact(LastName = 'Nair', Title = 'CTO', AccountId = a.Id);
        insert c;
        Case cs = new Case(Subject = 'Billing question', AccountId = a.Id, Status = 'New', Origin = 'Web');
        insert cs;
        String caseNumber = [SELECT CaseNumber FROM Case WHERE Id = :cs.Id].CaseNumber;
        Test.setFixedSearchResults(new List<Id>{ c.Id, cs.Id });

        List<de_HXL_Search.Row> contacts = run('contact', 'Nair', 5);
        Assert.areEqual(c.Id, contacts[0].id);
        Assert.isTrue(contacts[0].sublabel.contains('Search Parent'));

        Assert.areEqual(cs.Id, run('Case', caseNumber, 5)[0].id, 'Case number path');
        Assert.areEqual(cs.Id, run('Case', 'Billing', 5)[0].id, 'Subject SOSL path');
        Assert.areEqual(cs.Id, run('Case', cs.Id, 5)[0].id, 'Id path');
    }

    @IsTest
    static void unsupportedOrBlankInputsReturnNoRows() {
        Assert.isTrue(run('Lead', 'anything', 5).isEmpty());
        Assert.isTrue(run('Account', '  ', 5).isEmpty());
        Assert.isTrue(run(null, 'x', 5).isEmpty());
    }
}
