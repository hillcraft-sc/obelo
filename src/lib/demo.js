// The public demo (DEMO_MODE=true): people sign in with a shared account, so nothing personal may be
// connected to it. Calendar accounts (CalDAV and Google) and notification channels are refused here, on the
// server, so no app or browser can get around the screens that hide them.
const DEMO_MESSAGE = "This isn't available on the demo. Run your own Obelo server to connect calendars and notifications.";

const DEMO_PASSWORD_MESSAGE = "Changing the password isn't available on the demo, so everyone signs in with the shared demo account.";

const isDemo = () => process.env.DEMO_MODE === 'true';

module.exports = { isDemo, DEMO_MESSAGE, DEMO_PASSWORD_MESSAGE };
