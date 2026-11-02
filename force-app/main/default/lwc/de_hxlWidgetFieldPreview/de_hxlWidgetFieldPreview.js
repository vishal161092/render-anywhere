import { LightningElement, api } from 'lwc';

/** Past this length HXL wraps a detail value onto its own line under the label. */
const LONG_TEXT = 48;
const HTML_TAG = /<\/?(p|br|div|span|b|i|u|em|strong|ul|ol|li|a|h[1-6])\b[^>]*>/i;

function isLong(value) {
    return typeof value === 'string' && (value.length > LONG_TEXT || HTML_TAG.test(value));
}

/** A Summary/Tile item with its Badge or Gauge styling (de_HXL_PersonAccountView.tile). */
function styledTile(t, key) {
    return {
        ...t,
        key,
        badgeClass: `badge badge_${t.badgeVariant || 'secondary'}`,
        gaugeClass: `progress-bar progress-bar_${t.gaugeVariant || 'success'}`,
        gaugeStyle: `width: ${Math.max(0, Math.min(100, Number(t.gaugeValue) || 0))}%`
    };
}

/**
 * Read-only sketch of a widget's configurable parts, drawn from the same Result the widget gets
 * (de_HXL_WidgetFieldEditor.preview). Layout only, not the HXL renderer: the fixed parts of each
 * widget are reduced to its header.
 */
export default class HxlWidgetFieldPreview extends LightningElement {
    /** Widget__c value: PersonAccount360, BusinessAccount360, ContactQuickView, CaseDetail, OpportunityPipeline, AssetDetail. */
    @api widget;
    @api result;

    get isAccount() {
        return !this.widget || this.widget.endsWith('Account360');
    }

    get showOwner() {
        return this.isAccount && Boolean(this.result?.ownerName);
    }

    get isPipeline() {
        return this.widget === 'OpportunityPipeline';
    }

    get header() {
        const r = this.result || {};
        switch (this.widget) {
            case 'ContactQuickView':
                return { title: r.name, subtitle: [r.title, r.accountName].filter(Boolean).join(' · ') };
            case 'CaseDetail':
                return { title: `Case #${r.caseNumber || ''}`, badge: r.priority, subtitle: r.subject };
            case 'OpportunityPipeline':
                return { title: r.userName, subtitle: r.userTitle };
            case 'AssetDetail':
                return {
                    title: r.assetName,
                    badge: r.status,
                    subtitle: [r.productName, r.serialNumber].filter(Boolean).join(' · ')
                };
            default:
                return { title: r.name, badge: r.tier, subtitle: r.headerSubtitle };
        }
    }

    get opportunities() {
        return (this.result?.opportunities || []).map((o, i) => ({
            ...o,
            key: `opp-${i}`,
            lines: [1, 2]
                .filter((n) => o[`hasDetail${n}`])
                .map((n) => ({ key: `opp-${i}-${n}`, text: `${o[`detail${n}Label`]}: ${o[`detail${n}Value`]}` }))
        }));
    }

    get hasOpportunities() {
        return this.isPipeline && this.opportunities.length > 0;
    }

    get summary() {
        return (this.result?.summaryTiles || []).map((t, i) => styledTile(t, `kpi-${i}`));
    }

    get hasSummary() {
        return this.summary.length > 0;
    }

    get tiles() {
        return (this.result?.personTiles || []).map((t, i) => styledTile(t, `tile-${i}`));
    }

    get hasTiles() {
        return this.tiles.length > 0;
    }

    get details() {
        const rows = this.isAccount ? this.result?.personDetails : this.result?.details;
        return (rows || []).map((d, i) => ({
            ...d,
            key: `detail-${i}`,
            isLong: isLong(d.valueDisplay)
        }));
    }

    get hasDetails() {
        return this.details.length > 0;
    }

    /** The two configurable related lists (de_HXL_RelatedList), as card rows or table cells. */
    get lists() {
        const r = this.result || {};
        return [1, 2]
            .filter((n) => r[`hasList${n}`])
            .map((n) => {
                const columns = r[`list${n}Columns`] || [];
                return {
                    key: `list-${n}`,
                    title: r[`list${n}Title`],
                    icon: r[`list${n}Icon`],
                    summary: r[`list${n}Summary`],
                    isEmpty: r[`list${n}IsEmpty`],
                    emptyText: r[`list${n}EmptyText`],
                    isCard: r[`list${n}IsCard`],
                    isTable: r[`list${n}IsTable`],
                    rows: (r[`list${n}Rows`] || []).map((row, i) => ({
                        ...row,
                        key: `list-${n}-${i}`,
                        iconLetter: (row.iconName || '?').charAt(0).toUpperCase(),
                        badgeClass: `badge badge_${row.badgeVariant || 'secondary'}`,
                        pairs: [1, 2, 3, 4]
                            .filter((d) => row[`hasDetail${d}`])
                            .map((d) => ({
                                key: `list-${n}-${i}-${d}`,
                                label: row[`detail${d}Label`],
                                value: row[`detail${d}Value`]
                            }))
                    })),
                    columns: columns.map((c) => ({ ...c, key: `list-${n}-${c.key}` })),
                    tableRows: (r[`list${n}TableRows`] || []).map((row, i) => ({
                        key: `list-${n}-row-${i}`,
                        cells: columns.map((c) => ({ key: `list-${n}-${i}-${c.key}`, value: row[c.key] }))
                    }))
                };
            });
    }

    get hasLists() {
        return this.lists.length > 0;
    }

    get isEmpty() {
        return !this.hasTiles && !this.hasDetails && !this.hasLists && !this.hasOpportunities;
    }
}
