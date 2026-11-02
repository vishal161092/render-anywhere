@IsTest
private class de_HXL_FormatTest {

    @IsTest
    static void formatsDisplayValues() {
        Assert.areEqual('PN', de_HXL_Format.initials('Priya Nair'));
        Assert.areEqual('OM', de_HXL_Format.initials('Omega'));
        Assert.areEqual('', de_HXL_Format.initials(null));

        Assert.areEqual('$216B', de_HXL_Format.currencyCompact(215961500000L));
        Assert.areEqual('$1.5B', de_HXL_Format.currencyCompact(1500000000));
        Assert.areEqual('$8.4M', de_HXL_Format.currencyCompact(8400000));
        Assert.areEqual('$2M', de_HXL_Format.currencyCompact(2000000));
        Assert.areEqual('$420K', de_HXL_Format.currencyCompact(420000));
        Assert.areEqual('$950', de_HXL_Format.currencyCompact(950));
        Assert.isNull(de_HXL_Format.currencyCompact(null));

        Assert.areEqual('4,300', de_HXL_Format.number(4300));
        Assert.areEqual('-1,234,567', de_HXL_Format.number(-1234567));
        Assert.isNull(de_HXL_Format.number(null));

        Date today = Date.today();
        Assert.areEqual('Today', de_HXL_Format.timeAgo(today));
        Assert.areEqual('Yesterday', de_HXL_Format.timeAgo(today.addDays(-1)));
        Assert.areEqual('3 days ago', de_HXL_Format.timeAgo(today.addDays(-3)));
        Assert.areEqual('1 week ago', de_HXL_Format.timeAgo(today.addDays(-8)));
        Assert.areEqual('5 weeks ago', de_HXL_Format.timeAgo(today.addDays(-35)));
        Assert.areEqual('3 months ago', de_HXL_Format.timeAgo(today.addDays(-90)));
        Assert.areEqual(today.addDays(5).format(), de_HXL_Format.timeAgo(today.addDays(5)));
        Assert.isNull(de_HXL_Format.timeAgo(null));

        Assert.areEqual('', de_HXL_Format.recordUrl(null, 'Account'));
    }
}
