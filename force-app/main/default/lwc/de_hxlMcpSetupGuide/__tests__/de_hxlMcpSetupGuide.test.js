import { createElement } from 'lwc';
import HxlMcpSetupGuide from 'c/de_hxlMcpSetupGuide';

describe('c-de_hxl-mcp-setup-guide', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    beforeEach(() => {
        Object.assign(navigator, {
            clipboard: {
                writeText: jest.fn().mockResolvedValue()
            }
        });
    });

    it('renders the Agentforce, Slack, ChatGPT, and Claude sections in easiest-to-hardest order', () => {
        const element = createElement('c-de_hxl-mcp-setup-guide', {
            is: HxlMcpSetupGuide
        });
        document.body.appendChild(element);

        const sections = element.shadowRoot.querySelectorAll(
            'lightning-accordion-section'
        );
        const names = Array.from(sections).map((section) => section.name);

        expect(names).toEqual(['agentforce', 'slack', 'chatgpt', 'claude']);
    });

    it('defaults the active accordion section to Agentforce', () => {
        const element = createElement('c-de_hxl-mcp-setup-guide', {
            is: HxlMcpSetupGuide
        });
        document.body.appendChild(element);

        const accordion = element.shadowRoot.querySelector(
            'lightning-accordion'
        );
        expect(accordion.activeSectionName).toBe('agentforce');
    });

    it('copies a value to the clipboard when a copy button is clicked', () => {
        const element = createElement('c-de_hxl-mcp-setup-guide', {
            is: HxlMcpSetupGuide
        });
        document.body.appendChild(element);

        const copyButton = element.shadowRoot.querySelector(
            'lightning-button-icon[data-value]'
        );
        copyButton.click();

        expect(navigator.clipboard.writeText).toHaveBeenCalledWith(
            copyButton.dataset.value
        );
    });

    it('derives the Authorization and Token URLs from the running org domain for ChatGPT', () => {
        const element = createElement('c-de_hxl-mcp-setup-guide', {
            is: HxlMcpSetupGuide
        });
        document.body.appendChild(element);

        const copyButtons = element.shadowRoot.querySelectorAll(
            'lightning-button-icon[data-value]'
        );
        const values = Array.from(copyButtons).map(
            (button) => button.dataset.value
        );

        expect(
            values.some((value) => value.endsWith('/services/oauth2/authorize'))
        ).toBe(true);
        expect(
            values.some((value) => value.endsWith('/services/oauth2/token'))
        ).toBe(true);
    });

    it('links out to the Slack documentation as a connection prerequisite', () => {
        const element = createElement('c-de_hxl-mcp-setup-guide', {
            is: HxlMcpSetupGuide
        });
        document.body.appendChild(element);

        const link = element.shadowRoot.querySelector(
            'a[href="https://slack.com/help"]'
        );
        expect(link).not.toBeNull();
    });

    it('links out to the MCP documentation as a Claude prerequisite', () => {
        const element = createElement('c-de_hxl-mcp-setup-guide', {
            is: HxlMcpSetupGuide
        });
        document.body.appendChild(element);

        const link = element.shadowRoot.querySelector(
            'a[href="https://modelcontextprotocol.io"]'
        );
        expect(link).not.toBeNull();
    });

    it('renders a copy-pasteable example prompt for each of the five HXL widgets', () => {
        const element = createElement('c-de_hxl-mcp-setup-guide', {
            is: HxlMcpSetupGuide
        });
        document.body.appendChild(element);

        const copyButtons = element.shadowRoot.querySelectorAll(
            'lightning-button-icon[data-value]'
        );
        const values = Array.from(copyButtons).map(
            (button) => button.dataset.value
        );

        expect(values).toEqual(
            expect.arrayContaining([
                'Account 360 for Northwind Traders',
                'Jane Doe Contact Quick View',
                'Case details for #00001000',
                'Opportunity Pipeline for Alex Morgan',
                'Asset details for serial number SN-1001'
            ])
        );
    });

    it('renders a reference screenshot next to the step it illustrates in each section', () => {
        const element = createElement('c-de_hxl-mcp-setup-guide', {
            is: HxlMcpSetupGuide
        });
        document.body.appendChild(element);

        const sections = element.shadowRoot.querySelectorAll(
            'lightning-accordion-section'
        );
        Array.from(sections).forEach((section) => {
            const images = section.querySelectorAll('img.step-screenshot');
            expect(images.length).toBeGreaterThan(0);
            images.forEach((image) => {
                expect(image.getAttribute('src')).toBeTruthy();
                expect(image.getAttribute('alt')).toBeTruthy();
            });
        });
    });
});
