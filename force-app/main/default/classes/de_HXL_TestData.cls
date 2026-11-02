/**
 * de_HXL_TestData — shared fixtures for the HXL test classes. Inserts users inside runAs(self) so
 * callers can create sObject data in the same test without a MIXED_DML_OPERATION error.
 */
@IsTest
public class de_HXL_TestData {

    /** An active Standard User (the typical demo end user). */
    public static User standardUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias,
            LastName = 'HXL ' + alias,
            Email = alias + '@example.com',
            Username = alias + '.' + Datetime.now().getTime() + '@example.com.hxltest',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    /** First active open Opportunity stage in this org (stage names vary per org). */
    public static String openStage() {
        return [
            SELECT ApiName FROM OpportunityStage
            WHERE IsActive = true AND IsClosed = false ORDER BY SortOrder LIMIT 1
        ].ApiName;
    }

    /** First active closed-won Opportunity stage in this org. */
    public static String wonStage() {
        return [
            SELECT ApiName FROM OpportunityStage
            WHERE IsActive = true AND IsWon = true ORDER BY SortOrder LIMIT 1
        ].ApiName;
    }
}
