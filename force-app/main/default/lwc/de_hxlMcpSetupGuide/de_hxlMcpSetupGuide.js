import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import HXL_AGENTFORCE_ADD_FROM_ASSET_LIBRARY from '@salesforce/resourceUrl/hxlAgentforceAddFromAssetLibrary';
import HXL_SLACK_MANAGE_MCP_ADMIN from '@salesforce/resourceUrl/hxlSlackManageMcpAdmin';
import HXL_SLACK_ADD_MCP_SERVER from '@salesforce/resourceUrl/hxlSlackAddMcpServer';
import HXL_SLACK_SELECT_HXLXDO_SERVER from '@salesforce/resourceUrl/hxlSlackSelectHxlxdoServer';
import HXL_SLACK_CONNECTION_TOGGLE from '@salesforce/resourceUrl/hxlSlackConnectionToggle';
import HXL_CHATGPT_CREATE_MCP_APP from '@salesforce/resourceUrl/hxlChatgptCreateMcpApp';
import HXL_CHATGPT_GET_CALLBACK_URL from '@salesforce/resourceUrl/hxlChatgptGetCallbackUrl';
import HXL_CALLBACK_URL_AND_CONSUMER_KEYS from '@salesforce/resourceUrl/hxlCallbackUrlAndConsumerKeys';

const MCP_SERVER_URL_PROD =
    'https://api.salesforce.com/platform/mcp/v1/custom/HXLXDO';
const MCP_SERVER_URL_SANDBOX =
    'https://api.salesforce.com/platform/mcp/v1/sandbox/custom/HXLXDO';
const SLACK_INTEGRATION_DOCS_URL = 'https://slack.com/help';
const CLAUDE_CONNECTORS_DOCS_URL = 'https://modelcontextprotocol.io';

const EXAMPLE_PROMPTS = [
    { label: 'Account 360 Snapshot', value: 'Account 360 for Northwind Traders' },
    {
        label: 'Contact Quick View',
        value: 'Jane Doe Contact Quick View'
    },
    { label: 'Case Detail', value: 'Case details for #00001000' },
    {
        label: 'Opportunity Pipeline',
        value: 'Opportunity Pipeline for Alex Morgan'
    },
    { label: 'Asset Detail', value: 'Asset details for serial number SN-1001' }
];

function deriveMyDomainOrigin() {
    const { hostname } = window.location;
    if (hostname.endsWith('.my.salesforce.com')) {
        return `https://${hostname}`;
    }
    const base = hostname.replace(/\.lightning\.force\.com$/i, '');
    return `https://${base}.my.salesforce.com`;
}

const MY_DOMAIN_ORIGIN = deriveMyDomainOrigin();
const OAUTH_AUTHORIZE_URL = `${MY_DOMAIN_ORIGIN}/services/oauth2/authorize`;
const OAUTH_TOKEN_URL = `${MY_DOMAIN_ORIGIN}/services/oauth2/token`;

const SECTIONS = [
    {
        name: 'agentforce',
        label: 'Agentforce (Lightning)',
        difficulty: 'In-org, no OAuth',
        badgeVariant: 'success',
        summary:
            'The five HXL widgets ship as Agentforce actions, so any agent in this org can render them in the Agentforce panel. No MCP server, External Client App, or OAuth setup is involved.',
        caveat: "Each action's output is already typed at its Agentforce widget renderer (e.g. account360Agent), so no Output Rendering setup is needed. If an action shows a generic card instead of the widget, check its output's Output Rendering in the agent.",
        values: [
            {
                label: 'Asset Library search term',
                value: 'HXL'
            },
            {
                label: 'Actions to add',
                value: 'HXL Get Account 360 Snapshot, HXL Get Case Detail, HXL Get Contact Quick View, HXL Get Opportunity Pipeline, HXL Get Asset Detail'
            },
            {
                label: 'Permission set (assigned to the deploying user automatically)',
                value: 'HXL_MCP_Permissions'
            }
        ],
        steps: [
            {
                text: 'Go to App Launcher → Agentforce Studio → Agents, then either open an existing agent or create a new one.'
            },
            {
                text: 'If the agent is active, deactivate it (or create a new version) so you can edit it.'
            },
            {
                text: 'Choose "Add from Asset Library", search for "HXL", click Select on each of the five HXL actions, then click Add to Agent.',
                screenshot: {
                    src: HXL_AGENTFORCE_ADD_FROM_ASSET_LIBRARY,
                    alt: 'Agentforce Builder: Actions dialog filtered to "hxl", showing the HXL Get actions with Select buttons and Add to Agent'
                }
            },
            {
                text: 'Make sure any user testing the agent has the HXL_MCP_Permissions permission set, which grants access to the Apex behind each action.'
            },
            {
                text: 'Save and activate the agent, open the Agentforce panel, and test with one of the example prompts above.'
            }
        ]
    },
    {
        name: 'slack',
        label: 'Slack',
        difficulty: 'Easiest',
        badgeVariant: 'success',
        summary:
            'Slack discovers this org\'s MCP servers natively — an admin picks "HXLXDO" from a list. No MCP Server URL or Client ID is ever pasted in.',
        caveat: 'HXL widgets render using Block Kit inside Slack, so some visual fidelity from Agentforce/ChatGPT/Claude will be lost — this is a known Slack MCP client limitation, not a bug in this project.',
        prerequisite: {
            text: "Requires this Slack workspace to already be connected to this org. If it isn't yet, set that up first (see the ",
            linkLabel: 'Slack documentation',
            linkUrl: SLACK_INTEGRATION_DOCS_URL,
            suffix: ') before continuing below.'
        },
        values: [
            {
                label: 'MCP Server Name (select this in Slack)',
                value: 'HXLXDO'
            }
        ],
        steps: [
            {
                text: 'As a Slack admin, go to Tools & settings → Manage Salesforce MCP.',
                screenshot: {
                    src: HXL_SLACK_MANAGE_MCP_ADMIN,
                    alt: 'Slack admin: Tools & settings → Manage Salesforce MCP'
                }
            },
            {
                text: 'Click Add MCP Server.',
                screenshot: {
                    src: HXL_SLACK_ADD_MCP_SERVER,
                    alt: 'Slack: Manage Salesforce MCP → Add MCP Server'
                }
            },
            {
                text: 'Select "HXLXDO" from the list, then click Add.',
                screenshot: {
                    src: HXL_SLACK_SELECT_HXLXDO_SERVER,
                    alt: 'Slack: choosing HXLXDO from the Add MCP Server list'
                }
            },
            {
                text: 'Click Next, then check which workspaces you want to add this MCP server to.'
            },
            {
                text: 'Click Next, then choose Member Access (Everyone works well for demos).'
            },
            {
                text: 'Review Tool Access — leave the defaults — then click Connect.'
            },
            {
                text: 'Each user then enables the connection individually from the Slackbot plug/Apps icon menu — this is the "toggle" step. It works at the chat/session level, letting the user decide which MCP servers/apps they want available for that particular Slackbot conversation.',
                screenshot: {
                    src: HXL_SLACK_CONNECTION_TOGGLE,
                    alt: 'Slackbot: toggling the HXLXDO connection on for a chat'
                }
            }
        ]
    },
    {
        name: 'chatgpt',
        label: 'ChatGPT',
        difficulty: 'Requires Developer Mode',
        badgeVariant: 'warning',
        summary:
            'ChatGPT requires enabling Developer Mode before the Plugins tab and connector builder are available, and it requires a Client Secret — unlike Slack and Claude.',
        caveat: 'Expanding "Advanced OAuth settings" generates ChatGPT\'s Callback URL immediately — you don\'t need to save the connector first. That same screen in Setup → Headless_360_Hosted_MCP → OAuth Settings is also where you\'ll find the "Consumer Key and Secret" button for the Client ID/Secret.',
        values: [
            {
                label: 'MCP Server URL (Production / Developer Edition)',
                value: MCP_SERVER_URL_PROD
            },
            {
                label: 'MCP Server URL (Sandbox / Scratch org)',
                value: MCP_SERVER_URL_SANDBOX
            },
            {
                label: 'Authorization URL',
                value: OAUTH_AUTHORIZE_URL
            },
            {
                label: 'Token URL',
                value: OAUTH_TOKEN_URL
            },
            {
                label: 'Client ID (Consumer Key)',
                value: 'Setup → External Client App Manager → Headless_360_Hosted_MCP → Settings tab → OAuth Settings → "Consumer Key and Secret" (identity verification required)'
            },
            {
                label: 'Client Secret',
                value: 'Same location as Client ID above — ChatGPT requires this value; Slack and Claude do not.'
            }
        ],
        steps: [
            {
                text: 'In ChatGPT, turn on Developer Mode (Settings → Apps) so the Plugins tab appears in the left sidebar.'
            },
            {
                text: 'Go to Plugins, click the + icon, and choose "Create app".',
                screenshot: {
                    src: HXL_CHATGPT_CREATE_MCP_APP,
                    alt: 'ChatGPT: Plugins → + → Create MCP App'
                }
            },
            {
                text: 'Enter a Name, paste the MCP Server URL into Connection → Server URL, and set Authentication to OAuth.'
            },
            {
                text: 'Expand "Advanced OAuth settings" — ChatGPT generates a Callback URL here immediately; copy it.',
                screenshot: {
                    src: HXL_CHATGPT_GET_CALLBACK_URL,
                    alt: 'ChatGPT: Advanced OAuth settings showing the generated Callback URL'
                }
            },
            {
                text: 'In Setup → Headless_360_Hosted_MCP → OAuth Settings, add that Callback URL as a new line in the Callback URL field (keep the existing entries), then click "Consumer Key and Secret" to reveal the Client ID/Secret.',
                screenshot: {
                    src: HXL_CALLBACK_URL_AND_CONSUMER_KEYS,
                    alt: 'Setup → Headless_360_Hosted_MCP → OAuth Settings: Callback URL field and Consumer Key and Secret button'
                }
            },
            {
                text: 'Back in ChatGPT\'s Advanced OAuth settings, confirm Registration method is "User-Defined OAuth Client", then paste in the Authorization URL, Token URL, Client ID, and Client Secret.'
            },
            {
                text: 'Save (Create), then test the connection.'
            }
        ]
    },
    {
        name: 'claude',
        label: 'Claude',
        difficulty: 'Requires a custom connector',
        badgeVariant: 'warning',
        summary:
            'Claude connects to HXLXDO as a custom remote MCP connector using the same External Client App and OAuth flow as ChatGPT.',
        caveat: 'Adding custom connectors may require a Claude plan that supports remote MCP servers (and an admin to enable them for team plans).',
        prerequisite: {
            text: 'Review how remote MCP connectors work in the ',
            linkLabel: 'MCP documentation',
            linkUrl: CLAUDE_CONNECTORS_DOCS_URL,
            suffix: ' if this is your first time.'
        },
        values: [
            {
                label: 'Client ID (Consumer Key) — HXLXDO',
                value: 'Setup → External Client App Manager → Headless_360_Hosted_MCP → Settings tab → OAuth Settings → "Consumer Key and Secret" (identity verification required)'
            }
        ],
        steps: [
            {
                text: 'In Claude, open Settings → Connectors → Add custom connector.'
            },
            {
                text: 'Paste the MCP Server URL for this org (shown in the ChatGPT section above) and, under advanced settings, the Client ID and Secret from the External Client App.',
                screenshot: {
                    src: HXL_CALLBACK_URL_AND_CONSUMER_KEYS,
                    alt: 'Setup → Headless_360_Hosted_MCP → OAuth Settings: Consumer Key and Secret button'
                }
            },
            {
                text: "Add Claude's OAuth callback URL to the External Client App's Callback URLs, then complete the sign-in prompt."
            },
            {
                text: 'Confirm the HXLXDO connector appears under Settings → Connectors and is enabled for your conversation.'
            },
            {
                text: 'Test with one of the example prompts above.'
            }
        ]
    }
];

export default class HxlMcpSetupGuide extends LightningElement {
    activeSectionName = SECTIONS[0].name;

    get sections() {
        return SECTIONS;
    }

    get examplePrompts() {
        return EXAMPLE_PROMPTS;
    }

    handleCopy(event) {
        const { value, label } = event.currentTarget.dataset;
        navigator.clipboard
            .writeText(value)
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Copied',
                        message: `${label} copied to clipboard.`,
                        variant: 'success'
                    })
                );
            })
            .catch(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Copy failed',
                        message: `Could not copy ${label}. Copy it manually instead.`,
                        variant: 'error'
                    })
                );
            });
    }
}
