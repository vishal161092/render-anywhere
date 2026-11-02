/**
 * de_HXL_Search — Agentforce/MCP invocable action that resolves a user's free-text reference
 * (an Account name, a Contact name, or a Case subject/number) into concrete record Ids so the
 * agent can then call the detail tools (de_HXL_GetAccount360 / de_HXL_GetContactQuickView /
 * de_HXL_GetCaseDetail) without the user having to know or paste a raw record Id.
 *
 * This tool returns PLAIN DATA (a list of matches) — it is not bound to a UiWidgetBundle and
 * has no Custom Lightning Type. Because nothing introspects it for widget rendering, it is safe
 * to return a nested List<Row> here (unlike the rendered detail DTOs, which are kept flat).
 *
 * Matching + ordering are delegated to de_HXL_Resolve.ranked* (USER_MODE, the running user's own
 * records first), so this picker and the detail tools always agree on which match is "best".
 * Rows the user owns carry isMine = true and a leading "Yours" in the sublabel.
 */
global with sharing class de_HXL_Search {

    private static final Integer DEFAULT_LIMIT = 5;
    private static final Integer MAX_LIMIT = 25;

    @InvocableMethod(
        label='HXL: Search Records'
        description='Finds Accounts, Contacts, or Cases by name, subject, or number and returns their record Ids so a detail tool can be called next. Use this when the user refers to a record by name/subject/number instead of an Id.'
    )
    global static List<Response> search(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            Response resp = new Response();
            resp.matches = find(req);
            results.add(resp);
        }
        return results;
    }

    private static List<Row> find(Request req) {
        List<Row> rows = new List<Row>();
        if (req == null || String.isBlank(req.objectType) || String.isBlank(req.query)) {
            return rows;
        }

        String obj = req.objectType.trim().toLowerCase();
        String q = req.query.trim();
        Integer lim = normalizeLimit(req.maxResults);

        if (obj == 'account') {
            return searchAccounts(q, lim);
        } else if (obj == 'contact') {
            return searchContacts(q, lim);
        } else if (obj == 'case') {
            return searchCases(q, lim);
        }
        return rows;
    }

    // ---- Account ------------------------------------------------------------

    private static List<Row> searchAccounts(String q, Integer lim) {
        List<Row> rows = new List<Row>();
        for (de_HXL_Resolve.Candidate c : de_HXL_Resolve.rankedAccounts(q, lim)) {
            Account a = (Account) c.record;
            Row r = newRow(a.Id, 'Account', a.Name, c.isMine);
            r.sublabel = subtitle(new List<String>{
                mineTag(c.isMine), a.Industry, cityState(a.BillingCity, a.BillingState)
            });
            rows.add(r);
        }
        return rows;
    }

    // ---- Contact ------------------------------------------------------------

    private static List<Row> searchContacts(String q, Integer lim) {
        List<Row> rows = new List<Row>();
        for (de_HXL_Resolve.Candidate c : de_HXL_Resolve.rankedContacts(q, lim)) {
            Contact ct = (Contact) c.record;
            Row r = newRow(ct.Id, 'Contact', ct.Name, c.isMine);
            String acct = (ct.AccountId != null && ct.Account != null) ? ct.Account.Name : null;
            r.sublabel = subtitle(new List<String>{ mineTag(c.isMine), ct.Title, acct });
            rows.add(r);
        }
        return rows;
    }

    // ---- Case ---------------------------------------------------------------

    private static List<Row> searchCases(String q, Integer lim) {
        List<Row> rows = new List<Row>();
        for (de_HXL_Resolve.Candidate c : de_HXL_Resolve.rankedCases(q, lim)) {
            Case cs = (Case) c.record;
            String label = String.isNotBlank(cs.Subject) ? cs.Subject : ('Case ' + cs.CaseNumber);
            Row r = newRow(cs.Id, 'Case', label, c.isMine);
            String acct = (cs.AccountId != null && cs.Account != null) ? cs.Account.Name : null;
            r.sublabel = subtitle(new List<String>{
                mineTag(c.isMine), '#' + cs.CaseNumber, cs.Status, acct
            });
            rows.add(r);
        }
        return rows;
    }

    // ---- Helpers ------------------------------------------------------------

    private static Row newRow(Id id, String objectType, String label, Boolean isMine) {
        Row r = new Row();
        r.id = id;
        r.objectType = objectType;
        r.label = label;
        r.isMine = isMine;
        return r;
    }

    /** Leading sublabel tag so the agent/user can tell similarly named records apart. */
    private static String mineTag(Boolean isMine) {
        return isMine ? 'Yours' : null;
    }

    private static Integer normalizeLimit(Integer requested) {
        if (requested == null || requested <= 0) {
            return DEFAULT_LIMIT;
        }
        return requested > MAX_LIMIT ? MAX_LIMIT : requested;
    }

    private static String cityState(String city, String state) {
        return subtitle(new List<String>{ city, state });
    }

    /** Join non-blank parts with a middot; empty string when nothing is present. */
    private static String subtitle(List<String> parts) {
        List<String> kept = new List<String>();
        for (String p : parts) {
            if (String.isNotBlank(p)) {
                kept.add(p.trim());
            }
        }
        return kept.isEmpty() ? '' : String.join(kept, ' • ');
    }

    // ---- Invocable shapes ---------------------------------------------------

    global class Request {
        @InvocableVariable(required=true label='Object Type' description='One of: Account, Contact, Case')
        global String objectType;

        @InvocableVariable(required=true label='Query' description='Name, subject, or number to search for (or a record Id).')
        global String query;

        @InvocableVariable(label='Max Results' description='Optional cap on rows returned (default 5, max 25).')
        global Integer maxResults;
    }

    global class Response {
        @InvocableVariable(label='Matches')
        global List<Row> matches;
    }

    global class Row {
        @InvocableVariable(label='Record Id')
        global Id id;
        @InvocableVariable(label='Object Type')
        global String objectType;
        @InvocableVariable(label='Label')
        global String label;
        @InvocableVariable(label='Sublabel')
        global String sublabel;
        @InvocableVariable(label='Is Mine' description='True when the running user owns the record (or its Account).')
        global Boolean isMine;
    }
}
