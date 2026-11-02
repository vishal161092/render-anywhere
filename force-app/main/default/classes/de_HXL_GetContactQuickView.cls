/**
 * de_HXL_GetContactQuickView — Agentforce/MCP invocable action that builds a Contact Quick View
 * from standard Contact data, including a recent activity timeline (Tasks + Events).
 *
 * Accepts a Contact NAME or Id (resolved on the fly via de_HXL_Resolve) so the caller need not know
 * the record Id. Output DTO is referenced by the payload CLT as
 * @apexClassType/c__HXL_GetContactQuickView$Result. Nested List<> DTOs render fine here (see
 * de_HXL_GetAccount360's contacts/opportunities and de_HXL_GetCaseDetail's kbArticles) — used below for
 * recentActivities.
 *
 * Extra label/value rows come from HXL_Widget_Field__mdt (widget 'ContactQuickView', section
 * 'Detail'), edited in Widget Field Settings. With no rows the widget hides that section.
 */
global with sharing class de_HXL_GetContactQuickView {

    public static final String WIDGET = 'ContactQuickView';

    @InvocableMethod(label='HXL: Get Contact Quick View' description='Returns a Contact quick view for HXL widget rendering. Accepts a Contact name or Id.')
    global static List<Response> getView(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            Response resp = new Response();
            Id contactId = de_HXL_Resolve.toContactId(req.contactRef);
            resp.view = build(contactId);
            results.add(resp);
        }
        return results;
    }

    private static Result build(Id contactId) {
        Result r = new Result();
        r.hasDetails = false; // meta.if input: HXL fails on a missing one, so set it even when nothing matches
        if (contactId == null) {
            return r;
        }

        List<Contact> contacts = [
            SELECT Id, Name, Title, Email, Phone, LeadSource, LastActivityDate,
                   Account.Name, AccountId
            FROM Contact
            WHERE Id = :contactId
            WITH USER_MODE
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            return r;
        }
        Contact c = contacts[0];

        r.name = c.Name;
        r.initials = de_HXL_Format.initials(c.Name);
        r.title = c.Title;
        if (c.AccountId != null) {
            r.accountName = c.Account.Name;
            r.accountUrl = de_HXL_Format.recordUrl(c.AccountId, 'Account');
        }
        r.email = c.Email;
        r.emailHref = String.isNotBlank(c.Email) ? 'mailto:' + c.Email : '';
        r.phone = c.Phone;
        r.phoneHref = String.isNotBlank(c.Phone) ? 'tel:' + c.Phone.replaceAll('[^0-9+]', '') : '';
        r.salesforceUrl = de_HXL_Format.recordUrl(c.Id, 'Contact');
        r.recentActivities = recentActivities(c.Id);
        applyDetails(r, c.Id);

        return r;
    }

    /** Admin-chosen detail rows (HXL_Widget_Field__mdt, widget 'ContactQuickView', section 'Detail'). */
    private static void applyDetails(Result r, Id recordId) {
        r.details = new List<DetailRow>();
        List<de_HXL_FieldConfig.Field> fields = de_HXL_FieldConfig.fields(WIDGET, 'Detail', Contact.SObjectType);
        SObject rec = de_HXL_FieldConfig.record(Contact.SObjectType, recordId, fields);
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

    /** Most recent 3 activities (Tasks + Events) against this Contact, newest first. */
    private static List<ActivityRow> recentActivities(Id contactId) {
        List<ActivityRow> rows = new List<ActivityRow>();

        for (Task t : [
            SELECT Subject, TaskSubtype, ActivityDate
            FROM Task
            WHERE WhoId = :contactId AND ActivityDate != null
            WITH USER_MODE
            ORDER BY ActivityDate DESC
            LIMIT 3
        ]) {
            ActivityRow row = new ActivityRow();
            row.subject = String.isNotBlank(t.Subject) ? t.Subject : t.TaskSubtype;
            row.typeLabel = String.isNotBlank(t.TaskSubtype) ? t.TaskSubtype : 'Task';
            row.dateDisplay = de_HXL_Format.timeAgo(t.ActivityDate);
            row.sortDate = t.ActivityDate;
            rows.add(row);
        }

        for (Event e : [
            SELECT Subject, ActivityDate
            FROM Event
            WHERE WhoId = :contactId AND ActivityDate != null
            WITH USER_MODE
            ORDER BY ActivityDate DESC
            LIMIT 3
        ]) {
            ActivityRow row = new ActivityRow();
            row.subject = String.isNotBlank(e.Subject) ? e.Subject : 'Meeting';
            row.typeLabel = 'Event';
            row.dateDisplay = de_HXL_Format.timeAgo(e.ActivityDate);
            row.sortDate = e.ActivityDate;
            rows.add(row);
        }

        rows.sort();
        List<ActivityRow> top3 = new List<ActivityRow>();
        for (Integer i = 0; i < rows.size() && i < 3; i++) {
            top3.add(rows[i]);
        }
        return top3;
    }

    global class Request {
        @InvocableVariable(required=true label='Contact (name or Id)' description='A Contact name (e.g. "Jane Doe") or a 15/18-char Contact Id.')
        public String contactRef;
    }

    global class Response {
        @InvocableVariable(label='Contact Quick View')
        public Result view;
    }

    global class Result {
        @InvocableVariable public String name;
        @InvocableVariable public String initials;
        @InvocableVariable public String title;
        @InvocableVariable public String accountName;
        @InvocableVariable public String accountUrl;
        @InvocableVariable public String email;
        @InvocableVariable public String emailHref;
        @InvocableVariable public String phone;
        @InvocableVariable public String phoneHref;
        @InvocableVariable public String salesforceUrl;
        @InvocableVariable public List<ActivityRow> recentActivities;
        @InvocableVariable public Boolean hasDetails;
        @InvocableVariable public List<DetailRow> details;
    }

    global class ActivityRow implements Comparable {
        @InvocableVariable public String subject;
        @InvocableVariable public String typeLabel;
        @InvocableVariable public String dateDisplay;
        public Date sortDate;

        // Most recent first; undated rows sort last (shouldn't occur — queries filter ActivityDate != null).
        public Integer compareTo(Object o) {
            ActivityRow other = (ActivityRow) o;
            if (this.sortDate == other.sortDate) { return 0; }
            if (this.sortDate == null) { return 1; }
            if (other.sortDate == null) { return -1; }
            return this.sortDate > other.sortDate ? -1 : 1;
        }
    }

    global class DetailRow {
        @InvocableVariable public String label;
        @InvocableVariable public String valueDisplay;
        @InvocableVariable public String groupTitle;
        @InvocableVariable public Boolean isGroupStart;
    }
}
