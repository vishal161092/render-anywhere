@IsTest
private class de_HXL_ResolveTest {

    @IsTest
    static void accountOwnedByMeWinsOverSameNamedRecords() {
        User other = de_HXL_TestData.standardUser('hxlrot1');
        Account mine = new Account(Name = 'Omega Test Co');
        insert mine;
        Account theirs = new Account(Name = 'Omega Test Co', OwnerId = other.Id);
        insert theirs;
        Test.setFixedSearchResults(new List<Id>{ theirs.Id, mine.Id });

        Test.startTest();
        Id resolved = de_HXL_Resolve.toAccountId('Omega');
        Test.stopTest();

        Assert.areEqual(mine.Id, resolved, 'Running user\'s own Account should win');
    }

    @IsTest
    static void exactNameBeatsPrefixWhenNeitherIsMine() {
        User other = de_HXL_TestData.standardUser('hxlrot2');
        Account prefix = new Account(Name = 'Omega Test Co Holdings', OwnerId = other.Id);
        Account exact = new Account(Name = 'Omega Test Co', OwnerId = other.Id);
        insert new List<Account>{ prefix, exact };
        Test.setFixedSearchResults(new List<Id>{ prefix.Id, exact.Id });

        Assert.areEqual(exact.Id, de_HXL_Resolve.toAccountId('omega test co'));
    }

    @IsTest
    static void contactUnderMyAccountCountsAsMine() {
        User other = de_HXL_TestData.standardUser('hxlrot3');
        Account myAccount = new Account(Name = 'HXL Parent');
        insert myAccount;
        Contact viaAccount = new Contact(LastName = 'Kingston', AccountId = myAccount.Id, OwnerId = other.Id);
        Contact unrelated = new Contact(LastName = 'Kingston', OwnerId = other.Id);
        insert new List<Contact>{ unrelated, viaAccount };
        Test.setFixedSearchResults(new List<Id>{ unrelated.Id, viaAccount.Id });

        Assert.areEqual(viaAccount.Id, de_HXL_Resolve.toContactId('Kingston'));
    }

    @IsTest
    static void caseResolvesByNumberAndBySubject() {
        Case cs = new Case(Subject = 'Password reset loop', Status = 'New', Origin = 'Web');
        insert cs;
        String caseNumber = [SELECT CaseNumber FROM Case WHERE Id = :cs.Id].CaseNumber;

        Assert.areEqual(cs.Id, de_HXL_Resolve.toCaseId(caseNumber), 'Full case number');
        Assert.areEqual(cs.Id, de_HXL_Resolve.toCaseId(caseNumber.replaceFirst('^0+', '')), 'Unpadded case number');

        Test.setFixedSearchResults(new List<Id>{ cs.Id });
        Assert.areEqual(cs.Id, de_HXL_Resolve.toCaseId('password'), 'Subject via SOSL');
    }

    @IsTest
    static void idsPassThroughAndBlanksResolveToNull() {
        Account a = new Account(Name = 'HXL Id Account');
        insert a;

        Assert.areEqual(a.Id, de_HXL_Resolve.toAccountId(a.Id));
        Assert.isNull(de_HXL_Resolve.toAccountId(' '));
        Assert.isNull(de_HXL_Resolve.toContactId(null));
        Assert.isNull(de_HXL_Resolve.toCaseId(''));
        Assert.isNull(de_HXL_Resolve.toUserId(''));
        Assert.isFalse(de_HXL_Resolve.looksLikeId(a.Id, 'Contact'), 'Account Id is not a Contact Id');
        Assert.isNull(de_HXL_Resolve.toAccountId('no such account'), 'No SOSL hits -> null');
    }

    @IsTest
    static void userResolvesByNameOrId() {
        User other = de_HXL_TestData.standardUser('hxlrot4');
        Test.setFixedSearchResults(new List<Id>{ other.Id });

        Assert.areEqual(other.Id, de_HXL_Resolve.toUserId('HXL hxlrot4'));
        Assert.areEqual(other.Id, de_HXL_Resolve.toUserId(other.Id));
    }

    @IsTest
    static void standardUserResolvesOwnRecordInUserMode() {
        User rep = de_HXL_TestData.standardUser('hxlrot5');
        System.runAs(rep) {
            Account a = new Account(Name = 'Rep Owned Account');
            insert a;
            Test.setFixedSearchResults(new List<Id>{ a.Id });

            List<de_HXL_Resolve.Candidate> ranked = de_HXL_Resolve.rankedAccounts('Rep Owned', 5);
            Assert.areEqual(1, ranked.size());
            Assert.isTrue(ranked[0].isMine);
            Assert.areEqual(a.Id, ranked[0].record.Id);
        }
    }

    @IsTest
    static void exactNameFindsRecordsNotYetInSearchIndex() {
        // No setFixedSearchResults: SOSL returns nothing in tests, like a record created minutes ago.
        Account a = new Account(Name = 'Northwind Index Lag');
        insert a;
        Contact c = new Contact(FirstName = 'Dana', LastName = 'Lagtest', AccountId = a.Id);
        insert c;
        Case k = new Case(Subject = 'Router offline after outage', AccountId = a.Id);
        insert k;

        Assert.areEqual(a.Id, de_HXL_Resolve.toAccountId('Northwind Index Lag'));
        Assert.areEqual(c.Id, de_HXL_Resolve.toContactId('Dana Lagtest'));
        Assert.areEqual(k.Id, de_HXL_Resolve.toCaseId('Router offline after outage'));
        Assert.isNull(de_HXL_Resolve.toAccountId('Northwind'), 'Fallback is exact-name only');
    }
}
