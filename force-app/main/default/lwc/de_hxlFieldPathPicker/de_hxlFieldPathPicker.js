import { LightningElement, api } from 'lwc';
import describeFields from '@salesforce/apex/de_HXL_WidgetFieldEditor.describeFields';

/** Lookups a path may follow; matches de_HXL_WidgetFieldEditor.MAX_HOPS. */
const MAX_HOPS = 3;
const HOP_SUFFIX = '.';

// One describe per object for the page's lifetime; every picker on the page shares it.
const describeCache = new Map();

function fieldsFor(objectApiName) {
    if (!describeCache.has(objectApiName)) {
        describeCache.set(
            objectApiName,
            describeFields({ objectApiName }).catch((error) => {
                describeCache.delete(objectApiName);
                throw error;
            })
        );
    }
    return describeCache.get(objectApiName);
}

function sameName(a, b) {
    return (a || '').toLowerCase() === (b || '').toLowerCase();
}

/**
 * Picks a field path such as `Name` or `Product2.Name` from describe data, one dropdown per
 * hop, so admins can only choose fields that exist and that they can read. Fires `change` with
 * { value, fieldType, fieldLabel } when a field (not a lookup hop) is chosen.
 */
export default class HxlFieldPathPicker extends LightningElement {
    @api objectApiName;
    @api label = 'Field';
    @api disabled = false;

    levels = [];
    error;
    _value;
    _connected = false;

    @api
    get value() {
        return this._value;
    }
    set value(v) {
        if (v === this._value) {
            return;
        }
        this._value = v;
        if (this._connected) {
            this.build();
        }
    }

    connectedCallback() {
        this._connected = true;
        this.build();
    }

    disconnectedCallback() {
        this._connected = false;
    }

    get hasError() {
        return Boolean(this.error);
    }

    /** Rebuild the dropdown chain from the current path. */
    async build() {
        const parts = (this._value || '').split('.').filter(Boolean);
        const levels = [];
        let objectApiName = this.objectApiName;
        try {
            for (let depth = 0; depth <= MAX_HOPS; depth++) {
                // eslint-disable-next-line no-await-in-loop
                const fields = await fieldsFor(objectApiName);
                const level = this.makeLevel(objectApiName, fields, depth, levels);
                levels.push(level);
                const part = parts[depth];
                if (part === undefined) {
                    break;
                }
                if (depth < parts.length - 1) {
                    const hop = fields.find((f) =>
                        sameName(f.relationshipName, part)
                    );
                    if (!hop) {
                        this.markMissing(level, part + HOP_SUFFIX, part);
                        break;
                    }
                    level.value = hop.relationshipName + HOP_SUFFIX;
                    objectApiName = hop.referenceTo;
                } else {
                    const leaf = fields.find((f) => sameName(f.value, part));
                    if (leaf) {
                        level.value = leaf.value;
                    } else {
                        this.markMissing(level, part, part);
                    }
                    break;
                }
            }
            this.levels = levels;
            this.error = undefined;
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Could not load fields.';
        }
    }

    makeLevel(objectApiName, fields, depth, parents) {
        const leaves = fields.map((f) => ({
            label: `${f.label} (${f.value})`,
            value: f.value
        }));
        const hops =
            depth < MAX_HOPS
                ? fields
                      .filter((f) => f.relationshipName)
                      .map((f) => ({
                          label: `${f.referenceToLabel} fields via ${f.label} ›`,
                          value: f.relationshipName + HOP_SUFFIX
                      }))
                : [];
        const parent = parents[parents.length - 1];
        const parentHop =
            parent && parent.fields.find((f) => parent.value === f.relationshipName + HOP_SUFFIX);
        return {
            key: `${depth}-${objectApiName}`,
            depth,
            objectApiName,
            fields,
            value: null,
            label: depth === 0 ? this.label : `${parentHop?.referenceToLabel || objectApiName} field`,
            options: [...leaves, ...hops]
        };
    }

    /** Keep an unknown saved value visible (and selected) so the admin can see and replace it. */
    markMissing(level, value, name) {
        level.options = [{ label: `${name} (not found)`, value }, ...level.options];
        level.value = value;
    }

    async handleChange(event) {
        const depth = Number(event.target.dataset.depth);
        const value = event.detail.value;
        const levels = this.levels.slice(0, depth + 1);
        levels[depth] = { ...levels[depth], value };

        if (value.endsWith(HOP_SUFFIX)) {
            const hop = levels[depth].fields.find(
                (f) => f.relationshipName + HOP_SUFFIX === value
            );
            if (!hop) {
                this.levels = levels;
                return;
            }
            try {
                const fields = await fieldsFor(hop.referenceTo);
                levels.push(this.makeLevel(hop.referenceTo, fields, depth + 1, levels));
                this.error = undefined;
            } catch (e) {
                this.error = e?.body?.message || e?.message || 'Could not load fields.';
            }
            this.levels = levels;
            return;
        }

        this.levels = levels;
        const field = levels[depth].fields.find((f) => f.value === value);
        const path =
            levels
                .slice(0, depth)
                .map((l) => l.value)
                .join('') + value;
        this._value = path;
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: {
                    value: path,
                    fieldType: field ? field.type : null,
                    fieldLabel: field ? field.label : null
                }
            })
        );
    }
}
