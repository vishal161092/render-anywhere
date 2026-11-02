/**
 * de_HXL_Format — shared display-derivation helpers for HXL widget result DTOs.
 * Pure functions over standard field values. No DML, no custom fields.
 */
@JsonAccess(serializable='always' deserializable='always')
global class de_HXL_Format {

    /** Initials from a full name, e.g. "Priya Nair" -> "PN". Falls back to first two letters. */
    global static String initials(String fullName) {
        if (String.isBlank(fullName)) {
            return '';
        }
        List<String> parts = fullName.trim().split('\\s+');
        if (parts.size() == 1) {
            String p = parts[0];
            return (p.length() >= 2 ? p.substring(0, 2) : p).toUpperCase();
        }
        String first = parts[0].substring(0, 1);
        String last = parts[parts.size() - 1].substring(0, 1);
        return (first + last).toUpperCase();
    }

    /** Compact currency, e.g. 2.16e11 -> "$216B", 8400000 -> "$8.4M", 420000 -> "$420K". */
    global static String currencyCompact(Decimal amount) {
        if (amount == null) {
            return null;
        }
        Decimal abs = Math.abs(amount);
        if (abs >= 1000000000) {
            Decimal b = (amount / 1000000000).setScale(abs >= 100000000000L ? 0 : 1);
            return '$' + stripTrailingZero(b) + 'B';
        }
        if (abs >= 1000000) {
            Decimal m = (amount / 1000000).setScale(1);
            return '$' + stripTrailingZero(m) + 'M';
        }
        if (abs >= 1000) {
            Decimal k = (amount / 1000).setScale(0);
            return '$' + String.valueOf(k) + 'K';
        }
        return '$' + String.valueOf(amount.setScale(0));
    }

    /** Thousands-separated integer, e.g. 4300 -> "4,300". */
    global static String number(Decimal value) {
        if (value == null) {
            return null;
        }
        String s = String.valueOf(value.setScale(0));
        Boolean neg = s.startsWith('-');
        if (neg) {
            s = s.substring(1);
        }
        String out = '';
        Integer count = 0;
        for (Integer i = s.length() - 1; i >= 0; i--) {
            out = s.substring(i, i + 1) + out;
            count++;
            if (Math.mod(count, 3) == 0 && i > 0) {
                out = ',' + out;
            }
        }
        return (neg ? '-' : '') + out;
    }

    /** Relative "time ago" from a date, coarse buckets. */
    global static String timeAgo(Date d) {
        if (d == null) {
            return null;
        }
        Integer days = d.daysBetween(Date.today());
        if (days < 0) {
            return d.format();
        }
        if (days == 0) {
            return 'Today';
        }
        if (days == 1) {
            return 'Yesterday';
        }
        if (days < 7) {
            return days + ' days ago';
        }
        if (days < 14) {
            return '1 week ago';
        }
        if (days < 60) {
            return (days / 7) + ' weeks ago';
        }
        return (days / 30) + ' months ago';
    }

    /**
     * Absolute Lightning record URL for an Id + sObject API name.
     * Built from URL.getOrgDomainUrl() so the link resolves in external MCP clients
     * (ChatGPT / Claude), where a relative path has no origin to resolve against.
     */
    global static String recordUrl(Id recordId, String sobjectApiName) {
        if (recordId == null) {
            return '';
        }
        String base = URL.getOrgDomainUrl().toExternalForm();
        return base + '/lightning/r/' + sobjectApiName + '/' + recordId + '/view';
    }

    private static String stripTrailingZero(Decimal d) {
        String s = String.valueOf(d);
        if (s.endsWith('.0')) {
            return s.substring(0, s.length() - 2);
        }
        return s;
    }
}
