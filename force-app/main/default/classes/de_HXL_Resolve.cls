/**
 * de_HXL_Resolve — shared helper that turns a free-text reference (an Account/Contact name, a
 * Case subject, or a Case number) into a concrete record Id, so the detail invocable actions
 * (de_HXL_GetAccount360 / de_HXL_GetContactQuickView / de_HXL_GetCaseDetail) can accept a name-OR-Id and
 * resolve it on the fly. This removes the need for the agent to chain a separate search call
 * before the detail call.
 *
 * Demo-org behaviour: every query runs in USER_MODE (sharing + CRUD + FLS of the running user), and
 * when a name matches several records the candidates are RANKED so the user's own record wins
 * (shared demo orgs have many similarly named Accounts/Contacts/Cases). de_HXL_Search reuses the
 * same ranked lists, so the picker and the detail tools always agree on the order.
 *
 * If the ref already looks like a well-formed Id of the expected object, it is returned as-is
 * (the detail tool's USER_MODE query then enforces access). Returns null when nothing matches.
 */
public with sharing class de_HXL_Resolve {

    /**
     * How many SOSL hits are ranked. SOSL can't order by "is mine", so a generous window is
     * fetched (newest-modified first) and ranked in Apex.
     */
    @TestVisible
    private static final Integer CANDIDATE_LIMIT = 200;

    /** Resolve an Account reference (Id or name) to an Account Id, or null. */
    public static Id toAccountId(String ref) {
        if (String.isBlank(ref)) {
            return null;
        }
        if (looksLikeId(ref, 'Account')) {
            return (Id) ref.trim();
        }
        return firstId(rankedAccounts(ref, 1));
    }

    /** Resolve a Contact reference (Id or name) to a Contact Id, or null. */
    public static Id toContactId(String ref) {
        if (String.isBlank(ref)) {
            return null;
        }
        if (looksLikeId(ref, 'Contact')) {
            return (Id) ref.trim();
        }
        return firstId(rankedContacts(ref, 1));
    }

    /** Resolve a Case reference (Id, case number, or subject) to a Case Id, or null. */
    public static Id toCaseId(String ref) {
        if (String.isBlank(ref)) {
            return null;
        }
        if (looksLikeId(ref, 'Case')) {
            return (Id) ref.trim();
        }
        return firstId(rankedCases(ref, 1));
    }

    /** Resolve an Asset reference (Id, name, or serial number) to an Asset Id, or null. */
    public static Id toAssetId(String ref) {
        if (String.isBlank(ref)) {
            return null;
        }
        if (looksLikeId(ref, 'Asset')) {
            return (Id) ref.trim();
        }
        return firstId(rankedAssets(ref, 1));
    }

    /** Resolve a User reference (Id or name) to a User Id, or null. No ownership ranking. */
    public static Id toUserId(String ref) {
        if (String.isBlank(ref)) {
            return null;
        }
        if (looksLikeId(ref, 'User')) {
            return (Id) ref.trim();
        }
        String term = soslPhrase(ref);
        List<List<SObject>> found = Search.query(
            'FIND :term IN NAME FIELDS RETURNING User(Id WHERE IsActive = true ORDER BY Name LIMIT 1)',
            AccessLevel.USER_MODE
        );
        return (found.isEmpty() || found[0].isEmpty()) ? null : found[0][0].Id;
    }

    // ---- Ranked candidate lists (shared with de_HXL_Search) --------------------

    /** Accounts matching the ref (Id or name), best match first. */
    public static List<Candidate> rankedAccounts(String ref, Integer lim) {
        List<SObject> records;
        String trimmed = ref.trim();
        if (looksLikeId(trimmed, 'Account')) {
            records = [
                SELECT Id, Name, Industry, BillingCity, BillingState, OwnerId,
                       LastViewedDate, LastModifiedDate
                FROM Account WHERE Id = :((Id) trimmed) WITH USER_MODE LIMIT 1
            ];
        } else {
            records = sosl(trimmed, 'NAME',
                'Account(Id, Name, Industry, BillingCity, BillingState, OwnerId, '
                    + 'LastViewedDate, LastModifiedDate');
        }
        return rank(records, trimmed, lim);
    }

    /** Contacts matching the ref (Id or name), best match first. */
    public static List<Candidate> rankedContacts(String ref, Integer lim) {
        List<SObject> records;
        String trimmed = ref.trim();
        if (looksLikeId(trimmed, 'Contact')) {
            records = [
                SELECT Id, Name, Title, AccountId, Account.Name, Account.OwnerId, OwnerId,
                       LastViewedDate, LastModifiedDate
                FROM Contact WHERE Id = :((Id) trimmed) WITH USER_MODE LIMIT 1
            ];
        } else {
            records = sosl(trimmed, 'NAME',
                'Contact(Id, Name, Title, AccountId, Account.Name, Account.OwnerId, OwnerId, '
                    + 'LastViewedDate, LastModifiedDate');
        }
        return rank(records, trimmed, lim);
    }

    /** Cases matching the ref (Id, case number, or subject), best match first. */
    public static List<Candidate> rankedCases(String ref, Integer lim) {
        List<SObject> records = new List<SObject>();
        String trimmed = ref.trim();
        if (looksLikeId(trimmed, 'Case')) {
            records = [
                SELECT Id, CaseNumber, Subject, Status, AccountId, Account.Name, Account.OwnerId,
                       OwnerId, LastViewedDate, LastModifiedDate
                FROM Case WHERE Id = :((Id) trimmed) WITH USER_MODE LIMIT 1
            ];
            return rank(records, trimmed, lim);
        }
        // Numeric-looking refs match a CaseNumber directly (trailing match handles zero-padding).
        if (trimmed.replaceAll('[^0-9]', '').length() == trimmed.length()) {
            records = [
                SELECT Id, CaseNumber, Subject, Status, AccountId, Account.Name, Account.OwnerId,
                       OwnerId, LastViewedDate, LastModifiedDate
                FROM Case WHERE CaseNumber LIKE :('%' + trimmed)
                WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT :CANDIDATE_LIMIT
            ];
        }
        if (records.isEmpty()) {
            records = sosl(trimmed, 'ALL',
                'Case(Id, CaseNumber, Subject, Status, AccountId, Account.Name, Account.OwnerId, '
                    + 'OwnerId, LastViewedDate, LastModifiedDate');
        }
        return rank(records, trimmed, lim);
    }

    /**
     * Assets matching the ref (Id, name, or serial number), best match first. Asset has no
     * OwnerId, so "mine" is decided by the owner of the parent Account (see isMine).
     */
    public static List<Candidate> rankedAssets(String ref, Integer lim) {
        List<SObject> records;
        String trimmed = ref.trim();
        if (looksLikeId(trimmed, 'Asset')) {
            records = [
                SELECT Id, Name, SerialNumber, Status, AccountId, Account.Name, Account.OwnerId,
                       Product2.Name, LastViewedDate, LastModifiedDate
                FROM Asset WHERE Id = :((Id) trimmed) WITH USER_MODE LIMIT 1
            ];
        } else {
            // ALL fields so a serial number (not a NAME field) still matches.
            records = sosl(trimmed, 'ALL',
                'Asset(Id, Name, SerialNumber, Status, AccountId, Account.Name, Account.OwnerId, '
                    + 'Product2.Name, LastViewedDate, LastModifiedDate');
        }
        return rank(records, trimmed, lim);
    }

    // ---- Ranking -------------------------------------------------------------
    //
    // DEMO ORG OWNERS: this is the one place to change which record wins when names collide.
    // Order today: (1) mine, (2) exact name/subject/number match, (3) most recently viewed by
    // me, (4) most recently modified, (5) alphabetical label. "Mine" is decided in isMine().

    /** A ranked match. `record` carries whatever fields the ranked* query selected. */
    public class Candidate implements Comparable {
        public SObject record;
        public Boolean isMine;
        public Boolean isExact;

        public Integer compareTo(Object o) {
            Candidate other = (Candidate) o;
            if (isMine != other.isMine) {
                return isMine ? -1 : 1;
            }
            if (isExact != other.isExact) {
                return isExact ? -1 : 1;
            }
            Integer byViewed = newestFirst(
                (Datetime) record.get('LastViewedDate'), (Datetime) other.record.get('LastViewedDate'));
            if (byViewed != 0) {
                return byViewed;
            }
            Integer byModified = newestFirst(
                (Datetime) record.get('LastModifiedDate'), (Datetime) other.record.get('LastModifiedDate'));
            if (byModified != 0) {
                return byModified;
            }
            return label(record).compareTo(label(other.record));
        }
    }

    /**
     * True when the running user owns the record — or, for Contacts and Cases, owns the parent
     * Account (an account owner's contacts/cases are "theirs" in a demo sense).
     */
    @TestVisible
    private static Boolean isMine(SObject rec) {
        Id me = UserInfo.getUserId();
        // Asset has no OwnerId field at all, so "mine" is the parent Account's owner; check this
        // first to avoid an "Invalid field OwnerId for Asset" error on rec.get('OwnerId').
        if (rec instanceof Asset) {
            SObject acct = rec.getSObject('Account');
            return acct != null && acct.get('OwnerId') == me;
        }
        if (rec.get('OwnerId') == me) {
            return true;
        }
        if (rec instanceof Contact || rec instanceof Case) {
            SObject acct = rec.getSObject('Account');
            return acct != null && acct.get('OwnerId') == me;
        }
        return false;
    }

    /** Exact (case-insensitive) match on the record's display label or Case number. */
    private static Boolean isExact(SObject rec, String ref) {
        if (rec instanceof Case) {
            Case cs = (Case) rec;
            String digits = ref.replaceAll('^0+', '');
            return ref.equalsIgnoreCase(cs.Subject)
                || (String.isNotBlank(digits) && cs.CaseNumber != null
                    && cs.CaseNumber.replaceAll('^0+', '') == digits);
        }
        // Compare Ids as strings: `rec.Id == ref` throws "Invalid id" when ref is a name.
        String recId = String.valueOf(rec.Id);
        return ref.equalsIgnoreCase(label(rec)) || ref == recId || ref == recId.left(15);
    }

    private static List<Candidate> rank(List<SObject> records, String ref, Integer lim) {
        List<Candidate> ranked = new List<Candidate>();
        for (SObject rec : records) {
            Candidate c = new Candidate();
            c.record = rec;
            c.isMine = isMine(rec);
            c.isExact = isExact(rec, ref);
            ranked.add(c);
        }
        ranked.sort();
        List<Candidate> top = new List<Candidate>();
        for (Integer i = 0; i < ranked.size() && i < lim; i++) {
            top.add(ranked[i]);
        }
        return top;
    }

    // ---- Helpers ------------------------------------------------------------

    /**
     * USER_MODE SOSL over `scope` (NAME or ALL) fields. `returning` is an object clause without
     * its closing paren, e.g. 'Account(Id, Name'; ordering + limit are appended here.
     */
    private static List<SObject> sosl(String ref, String scope, String returning) {
        String term = soslPhrase(ref);
        List<List<SObject>> found = Search.query(
            'FIND :term IN ' + scope + ' FIELDS RETURNING ' + returning
                + ' ORDER BY LastModifiedDate DESC LIMIT ' + CANDIDATE_LIMIT + ')',
            AccessLevel.USER_MODE
        );
        List<SObject> hits = found.isEmpty() ? new List<SObject>() : found[0];
        if (hits.isEmpty()) {
            // New records take minutes to reach the search index; an exact name (Case: subject) still finds them.
            String obj = returning.substringBefore('(');
            hits = Database.queryWithBinds(
                'SELECT ' + returning.substringAfter('(') + ' FROM ' + obj
                    + ' WHERE ' + (obj == 'Case' ? 'Subject' : 'Name') + ' = :ref'
                    + ' ORDER BY LastModifiedDate DESC LIMIT ' + CANDIDATE_LIMIT,
                new Map<String, Object>{ 'ref' => ref },
                AccessLevel.USER_MODE
            );
        }
        return hits;
    }

    private static Id firstId(List<Candidate> ranked) {
        return ranked.isEmpty() ? null : ranked[0].record.Id;
    }

    private static Integer newestFirst(Datetime a, Datetime b) {
        if (a == b) {
            return 0;
        }
        if (a == null) {
            return 1;
        }
        if (b == null) {
            return -1;
        }
        return a > b ? -1 : 1;
    }

    private static String label(SObject rec) {
        Object value = (rec instanceof Case) ? rec.get('Subject') : rec.get('Name');
        return value == null ? '' : String.valueOf(value);
    }

    /** True when the ref is a well-formed 15/18-char Id whose prefix matches the sObject. */
    public static Boolean looksLikeId(String ref, String sobjectType) {
        if (ref == null) {
            return false;
        }
        String r = ref.trim();
        if (r.length() != 15 && r.length() != 18) {
            return false;
        }
        try {
            Id candidate = (Id) r;
            return candidate.getSObjectType() == Schema.getGlobalDescribe().get(sobjectType);
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Build a safe SOSL search phrase: escape the reserved characters SOSL treats specially,
     * then append a trailing wildcard so "Omeg" still matches "Omega, Inc." The value is bound
     * (not concatenated) so this is defence-in-depth against a malformed FIND clause.
     */
    public static String soslPhrase(String raw) {
        String cleaned = raw.trim();
        cleaned = cleaned.replaceAll('([?&|!{}\\[\\]()^~*:\\\\"\'+\\-])', '\\\\$1');
        return cleaned + '*';
    }
}
