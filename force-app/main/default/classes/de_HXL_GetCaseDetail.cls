/**
 * de_HXL_GetCaseDetail — Agentforce/MCP invocable action that builds a Case Detail view from
 * standard Case data (account/contact/owner, description, related KB articles).
 *
 * Rebuilt to the flat-primitive style proven on de_HXL_GetAccount360: plain `global class` DTO with
 * `public @InvocableVariable` fields, NO @JsonAccess / @AuraEnabled, and NO nested List<> — the
 * related KB articles are flattened into fixed primitive slots (kb1..kb3). This avoids the HXL v2
 * server introspection flattening nested Apex List<> into "object" (the render bug).
 *
 * SLA is a display string derived from CreatedDate + a priority-based target (Critical 4h,
 * High 8h, otherwise 24h) — there is no reliable standard SLA field on a stock SDO. The tile/progress
 * bar is intentionally NOT used (that component NPEd during the Account 360 rebuild); SLA is shown
 * as a colored badge + caption instead.
 *
 * Accepts a Case Id, case NUMBER, or case SUBJECT (resolved on the fly via de_HXL_Resolve).
 *
 * Extra label/value rows come from HXL_Widget_Field__mdt (widget 'CaseDetail', section 'Detail'),
 * edited in Widget Field Settings. With no rows the widget hides that section.
 */
global with sharing class de_HXL_GetCaseDetail {

    public static final String WIDGET = 'CaseDetail';

    @InvocableMethod(label='HXL: Get Case Detail' description='Returns a Case detail view for HXL widget rendering. Accepts a Case number, subject, or Id.')
    global static List<Response> getDetail(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            Response resp = new Response();
            Id caseId = de_HXL_Resolve.toCaseId(req.caseRef);
            resp.detail = build(caseId);
            results.add(resp);
        }
        return results;
    }

    private static Result build(Id caseId) {
        Result r = new Result();
        r.hasDetails = false; // meta.if input: HXL fails on a missing one, so set it even when nothing matches
        if (caseId == null) {
            return r;
        }

        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Priority, Status, Origin, Description, CreatedDate,
                   Account.Name, AccountId, Contact.Name, ContactId, Owner.Name
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            return r;
        }
        Case c = cases[0];

        r.caseNumber = c.CaseNumber;
        r.subject = c.Subject;
        r.priority = c.Priority;
        r.priorityVariant = priorityVariant(c.Priority);
        r.status = c.Status;
        r.statusVariant = statusVariant(c.Status);
        r.origin = c.Origin;
        r.description = c.Description;
        r.createdDisplay = c.CreatedDate != null ? c.CreatedDate.format('MMM d, yyyy, h:mm a') : '';

        if (c.AccountId != null) {
            r.accountName = c.Account.Name;
            r.accountUrl = de_HXL_Format.recordUrl(c.AccountId, 'Account');
        }
        if (c.ContactId != null) {
            r.contactName = c.Contact.Name;
            r.contactInitials = de_HXL_Format.initials(c.Contact.Name);
            r.contactUrl = de_HXL_Format.recordUrl(c.ContactId, 'Contact');
        }
        if (c.Owner != null) {
            r.ownerName = c.Owner.Name;
            r.ownerInitials = de_HXL_Format.initials(c.Owner.Name);
        }
        r.salesforceUrl = de_HXL_Format.recordUrl(c.Id, 'Case');

        applySla(r, c);
        applyKbArticles(r, c.Subject);
        applyDetails(r, c.Id);

        return r;
    }

    /** Admin-chosen detail rows (HXL_Widget_Field__mdt, widget 'CaseDetail', section 'Detail'). */
    private static void applyDetails(Result r, Id recordId) {
        r.details = new List<DetailRow>();
        List<de_HXL_FieldConfig.Field> fields = de_HXL_FieldConfig.fields(WIDGET, 'Detail', Case.SObjectType);
        SObject rec = de_HXL_FieldConfig.record(Case.SObjectType, recordId, fields);
        if (rec != null) {
            for (de_HXL_FieldConfig.Shown s : de_HXL_FieldConfig.shown(rec, fields, '—')) {
                DetailRow row = new DetailRow();
                row.label = s.label;
                row.valueDisplay = s.value;
                row.groupTitle = s.groupTitle;
                row.isGroupStart = s.isGroupStart;
                r.details.add(row);
            }
        }
        r.hasDetails = !r.details.isEmpty();
    }

    /** Display-only SLA derived from CreatedDate + priority-based target hours. */
    private static void applySla(Result r, Case c) {
        if (c.CreatedDate == null || String.isBlank(c.Priority)) {
            return;
        }
        Integer targetHours = targetHoursFor(c.Priority);
        Datetime due = c.CreatedDate.addHours(targetHours);
        Long totalMs = due.getTime() - c.CreatedDate.getTime();
        Long elapsedMs = Datetime.now().getTime() - c.CreatedDate.getTime();
        Decimal pct = totalMs > 0 ? (Decimal.valueOf(elapsedMs) / totalMs) * 100 : 100;
        if (pct < 0) { pct = 0; }
        if (pct > 100) { pct = 100; }
        Boolean breached = pct >= 100;

        r.slaDueDisplay = due.format('MMM d, yyyy, h:mm a');
        r.slaPercent = pct.setScale(0);
        // progress uses `color` (not `variant`) for the semantic token; keep a variant too for badges.
        r.slaVariant = breached ? 'error' : (pct >= 75 ? 'warning' : 'success');
        r.slaColor = breached ? 'error' : (pct >= 75 ? 'warning' : 'success');
        r.slaStatus = breached ? 'SLA breached' : 'On track';
        r.slaTitle = breached ? 'SLA breached' : 'SLA — ' + r.slaStatus;
    }

    private static Integer targetHoursFor(String priority) {
        String p = priority.toLowerCase();
        if (p.contains('critical')) {
            return 4;
        }
        if (p == 'high') {
            return 8;
        }
        return 24;
    }

    /**
     * Related KB articles, matched to the case SUBJECT by keyword overlap.
     *
     * WHY subject-match instead of the CaseArticle attach-junction: on this SDO the CaseArticle
     * junction is effectively empty (an end-to-end invoke returned no rows even for cases that have
     * a linked article), so relying on it shows nothing. The published Knowledge__kav set IS
     * populated (53+ Online/en_US articles), so we score each published article by keyword overlap
     * against the case Subject and surface the best matches — more compelling and robust. Returns
     * NONE when nothing overlaps (per the user: "okay to return none if no matches arise").
     *
     * Emits a nested List<KbArticle> (the Playground forEach shape). Read in USER_MODE (demo users
     * only see articles they can access); a user without Knowledge read gets an empty list via the
     * catch below. Do NOT add CaseArticle queries back — they throw an uncatchable
     * UNKNOWN_EXCEPTION inside @InvocableMethod.
     */
    private static void applyKbArticles(Result r, String subject) {
        r.kbArticles = new List<KbArticle>();
        if (String.isBlank(subject) || !Schema.getGlobalDescribe().containsKey('Knowledge__kav')) {
            return;
        }
        Set<String> terms = keywords(subject);
        if (terms.isEmpty()) {
            return;
        }
        try {
            List<Knowledge__kav> arts = [
                SELECT Title, ArticleNumber, Summary, UrlName, LastPublishedDate
                FROM Knowledge__kav
                WHERE PublishStatus = 'Online' AND Language = 'en_US' AND IsLatestVersion = true
                WITH USER_MODE
                LIMIT 200
            ];
            r.kbArticles.addAll(rankArticles(terms, arts));
        } catch (Exception e) {
            // Knowledge not accessible / query invalid — leave the list empty.
        }
    }

    /** Meaningful lowercased tokens from the subject (drops stopwords + very short tokens). */
    @TestVisible
    private static Set<String> keywords(String subject) {
        Set<String> stop = new Set<String>{
            'the','a','an','and','or','of','to','for','is','are','my','your','our','you','i',
            'in','on','with','how','do','does','can','what','why','when','where','please','send',
            'need','it','this','that','be','as','at','by','from','has','have',
            'about','question','issue','problem','help','get','got','see','know','want','would',
            'could','should','will','was','were','out','up','me','we','they','their','there'
        };
        Set<String> terms = new Set<String>();
        for (String raw : subject.toLowerCase().split('[^a-z0-9]+')) {
            String t = raw.trim();
            if (t.length() >= 3 && !stop.contains(t)) {
                terms.add(t);
            }
        }
        return terms;
    }

    /**
     * +2 per term prefix-hit in Title, +1 per term prefix-hit in Summary.
     * Matches on tokenized WORDS with shared-prefix stemming (min 4 chars), so "bill" still
     * matches "billing" but "cover" no longer matches "recover" (substring bug) and short
     * common words don't fan out. A term matches an article word when either is a prefix of
     * the other and the shorter is at least 4 chars.
     */
    @TestVisible
    private static Integer overlapScore(Set<String> terms, String title, String summary) {
        Set<String> titleWords = wordSet(title);
        Set<String> summaryWords = wordSet(summary);
        Integer score = 0;
        for (String term : terms) {
            if (anyWordMatches(term, titleWords)) { score += 2; }
            if (anyWordMatches(term, summaryWords)) { score += 1; }
        }
        return score;
    }

    /** True if term shares a stem with any article word (prefix match, min 4 chars). */
    private static Boolean anyWordMatches(String term, Set<String> words) {
        if (words.contains(term)) {
            return true;
        }
        for (String w : words) {
            String shorter = term.length() <= w.length() ? term : w;
            String longer = term.length() <= w.length() ? w : term;
            if (shorter.length() >= 4 && longer.startsWith(shorter)) {
                return true;
            }
        }
        return false;
    }

    /** Lowercased whole-word token set (same tokenizer as keywords, minus the stopword filter). */
    private static Set<String> wordSet(String text) {
        Set<String> words = new Set<String>();
        if (String.isBlank(text)) {
            return words;
        }
        for (String raw : text.toLowerCase().split('[^a-z0-9]+')) {
            if (String.isNotBlank(raw)) {
                words.add(raw);
            }
        }
        return words;
    }

    /** The top 3 articles scoring >= 3 against `terms`, best first. */
    @TestVisible
    private static List<KbArticle> rankArticles(Set<String> terms, List<Knowledge__kav> arts) {
        // Require score >= 3 so a single common-word Title hit (e.g. "service") alone
        // doesn't surface a marginal article: a match needs a Title hit plus a Summary
        // corroboration (2+1), a multi-term overlap, or two summary hits + more. A truly
        // on-topic article (e.g. billing FAQ for a billing case) scores far higher.
        List<ScoredArticle> scored = new List<ScoredArticle>();
        for (Knowledge__kav a : arts) {
            Integer score = overlapScore(terms, a.Title, a.Summary);
            if (score >= 3) {
                scored.add(new ScoredArticle(score, a));
            }
        }
        List<KbArticle> result = new List<KbArticle>();
        for (ScoredArticle s : topThreeByScore(scored)) {
            KbArticle kb = new KbArticle();
            kb.title = s.art.Title;
            kb.caption = kbCaption(s.art);
            result.add(kb);
        }
        return result;
    }

    /** Sort desc by score (tie-break newer published first) via Comparable, take top 3. */
    private static List<ScoredArticle> topThreeByScore(List<ScoredArticle> items) {
        items.sort(); // ScoredArticle.compareTo orders best-first
        List<ScoredArticle> top = new List<ScoredArticle>();
        for (ScoredArticle s : items) {
            if (top.size() >= 3) { break; }
            top.add(s);
        }
        return top;
    }

    private static String kbCaption(Knowledge__kav a) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(a.ArticleNumber)) {
            parts.add(a.ArticleNumber);
        }
        if (a.LastPublishedDate != null) {
            parts.add('Updated ' + a.LastPublishedDate.format('MMM d, yyyy'));
        }
        return String.join(parts, ' • ');
    }

    /** Small holder pairing a relevance score with its article; sorts best-first. */
    private class ScoredArticle implements Comparable {
        Integer score;
        Knowledge__kav art;
        ScoredArticle(Integer score, Knowledge__kav art) {
            this.score = score;
            this.art = art;
        }
        // Higher score first; tie-break on more-recent LastPublishedDate.
        public Integer compareTo(Object o) {
            ScoredArticle other = (ScoredArticle) o;
            if (this.score != other.score) {
                return other.score - this.score;
            }
            Datetime a = this.art.LastPublishedDate;
            Datetime b = other.art.LastPublishedDate;
            if (a == b) { return 0; }
            if (a == null) { return 1; }
            if (b == null) { return -1; }
            return a > b ? -1 : 1;
        }
    }

    private static String priorityVariant(String priority) {
        if (String.isBlank(priority)) {
            return 'secondary';
        }
        String p = priority.toLowerCase();
        if (p.contains('critical') || p == 'high') {
            return 'error';
        }
        if (p == 'medium') {
            return 'warning';
        }
        return 'info';
    }

    private static String statusVariant(String status) {
        if (String.isBlank(status)) {
            return 'secondary';
        }
        String s = status.toLowerCase();
        if (s == 'new') {
            return 'info';
        }
        if (s == 'closed') {
            return 'success';
        }
        if (s == 'escalated') {
            return 'error';
        }
        return 'info';
    }

    global class Request {
        @InvocableVariable(required=true label='Case (number, subject, or Id)' description='A case number, subject text, or a 15/18-char Case Id.')
        public String caseRef;
    }

    global class Response {
        @InvocableVariable(label='Case Detail')
        public Result detail;
    }

    global class Result {
        @InvocableVariable public String caseNumber;
        @InvocableVariable public String subject;
        @InvocableVariable public String priority;
        @InvocableVariable public String priorityVariant;
        @InvocableVariable public String status;
        @InvocableVariable public String statusVariant;
        @InvocableVariable public String origin;
        @InvocableVariable public String createdDisplay;
        @InvocableVariable public String slaStatus;
        @InvocableVariable public String slaTitle;
        @InvocableVariable public String slaDueDisplay;
        @InvocableVariable public String slaVariant;
        @InvocableVariable public String slaColor;
        @InvocableVariable public Decimal slaPercent;
        @InvocableVariable public String description;
        @InvocableVariable public String accountName;
        @InvocableVariable public String accountUrl;
        @InvocableVariable public String contactName;
        @InvocableVariable public String contactInitials;
        @InvocableVariable public String contactUrl;
        @InvocableVariable public String ownerName;
        @InvocableVariable public String ownerInitials;
        @InvocableVariable public String salesforceUrl;
        @InvocableVariable public List<KbArticle> kbArticles;
        @InvocableVariable public Boolean hasDetails;
        @InvocableVariable public List<DetailRow> details;
    }

    global class KbArticle {
        @InvocableVariable public String title;
        @InvocableVariable public String caption;
    }

    global class DetailRow {
        @InvocableVariable public String label;
        @InvocableVariable public String valueDisplay;
        @InvocableVariable public String groupTitle;
        @InvocableVariable public Boolean isGroupStart;
    }
}
