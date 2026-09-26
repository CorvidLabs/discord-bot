@preconcurrency import Foundation

/// The page, its stylesheet and its script, as three strings compiled into
/// this target.
///
/// **A static asset with no build step and no bundler**, which is the whole
/// of the precedent this follows: the bot this was ported from serves its
/// administrator page the same way, as text in a constant, and a second web
/// service exists in neither design. There is nothing to install, nothing to
/// transpile and nothing that can be missing at runtime.
///
/// Held in a constant rather than in a SwiftPM resource bundle on purpose.
/// `Bundle.module` traps when the bundle is not beside the binary, and the
/// bot this was ported from hit exactly that: a page route that takes the
/// whole process down the first time somebody loads it. A string cannot be
/// missing.
///
/// **No value is ever interpolated into this HTML.** The member's chat
/// account name, the code and the expiry are fetched by the script and
/// written as text nodes in the browser, so there is no template, no
/// escaping rule to get right, and no way for a name to become markup. The
/// page is the same bytes for every member.
///
/// **What an operator still has to add.** There is no wallet connector here.
/// Bundling one would mean vendoring a third party browser library of some
/// hundreds of kilobytes into a repository whose answer to "should I install
/// this" is that you can read what it depends on, and this target will not
/// do that quietly. So the page ships two paths: an operator drops their own
/// connector in and sets ``VerifyPageScript/adapterGlobalName`` on `window`,
/// or the member pastes a signed transaction produced by whatever tool they
/// already use. The second works today and is honest about being clumsy on a
/// phone; the first is what a public community needs, and it is an
/// operator's asset plus a widened `script-src`, not a change here.
public enum VerifyPage: Sendable {

    // MARK: - Properties

    /// The page a member's wallet signs against.
    public static let html: String = #"""
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="no-referrer">
        <title>Prove your wallet</title>
        <link rel="stylesheet" href="/verify/app.css">
        </head>
        <body>
        <main>
        <h1>Prove your wallet</h1>

        <section class="whose" aria-labelledby="whose-heading">
        <h2 id="whose-heading">This link was made for</h2>
        <p class="account" id="account">Reading the link</p>
        <p class="warning">
        Only go on if that is your own account. Nobody should ever send you this
        link: not a moderator, not an administrator, not a friend. If somebody
        sent it to you, close this page and run the command yourself.
        </p>
        </section>

        <noscript>
        <p class="warning">
        This page needs JavaScript to talk to your wallet. Nothing here works
        without it.
        </p>
        </noscript>

        <section class="facts">
        <p>Code: <span class="code" id="code">loading</span>. It should match the code you
        were just shown where you ran the command. If it does not, stop.</p>
        <p>This link stops working <span id="expires">shortly</span>.</p>
        </section>

        <section class="step" id="step-connect" hidden>
        <h2>1. Name the account</h2>
        <p id="pinned-note" hidden>You named an account when you ran the command, and
        it is the only one this link will take.</p>
        <button type="button" id="connect-wallet" hidden>Connect a wallet</button>
        <label for="address">Account address</label>
        <input type="text" id="address" name="address" autocomplete="off"
        spellcheck="false" inputmode="text" placeholder="Your Algorand address">
        <button type="button" id="connect-typed">Use this address</button>
        </section>

        <section class="step" id="step-sign" hidden>
        <h2>2. Sign the prompt</h2>
        <p>Your wallet will ask you to sign a payment of zero to yourself. It moves
        nothing, and it is never sent to the network. This is exactly what it says:</p>
        <pre id="challenge" aria-label="What you will sign"></pre>
        <button type="button" id="sign-wallet" hidden>Sign with your wallet</button>
        <details id="manual">
        <summary>My wallet is not offered here</summary>
        <p>Build a payment from your account to itself, amount zero, fee at or below
        the network minimum, with the text above as its note, sign it, and paste the
        signed transaction below as base64. It is not submitted anywhere.</p>
        <label for="blob">Signed transaction, base64</label>
        <textarea id="blob" name="blob" rows="4" autocomplete="off"
        spellcheck="false"></textarea>
        <button type="button" id="submit-pasted">Send it</button>
        </details>
        </section>

        <p class="status" id="status" role="status" aria-live="polite"></p>
        </main>
        <script src="/verify/app.js"></script>
        </body>
        </html>
        """#

    /// The page's stylesheet.
    ///
    /// Plain CSS with no font, no image and no third party origin in it, so
    /// the content security policy can name nothing but this one.
    public static let stylesheet: String = #"""
        :root {
            color-scheme: light dark;
            --ink: #14161a;
            --paper: #f7f7f5;
            --edge: #c9c9c4;
            --warn: #8a3b12;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --ink: #eceae5;
                --paper: #16181c;
                --edge: #3a3d44;
                --warn: #f0a878;
            }
        }

        body {
            background: var(--paper);
            color: var(--ink);
            font-family: system-ui, sans-serif;
            line-height: 1.5;
            margin: 0;
            padding: 1.5rem 1rem 4rem;
        }

        main {
            margin: 0 auto;
            max-width: 34rem;
        }

        h1 {
            font-size: 1.5rem;
        }

        h2 {
            font-size: 1rem;
            letter-spacing: 0.04em;
            text-transform: uppercase;
        }

        section {
            border: 1px solid var(--edge);
            border-radius: 0.5rem;
            margin: 1rem 0;
            padding: 0.25rem 1rem 1rem;
        }

        .account {
            font-size: 1.25rem;
            font-weight: 700;
            overflow-wrap: anywhere;
        }

        .warning {
            color: var(--warn);
            font-weight: 600;
        }

        .code {
            font-family: ui-monospace, monospace;
            font-size: 1.125rem;
            letter-spacing: 0.15em;
        }

        pre {
            background: var(--paper);
            border: 1px solid var(--edge);
            border-radius: 0.25rem;
            overflow-x: auto;
            padding: 0.75rem;
            white-space: pre-wrap;
            word-break: break-word;
        }

        label {
            display: block;
            font-weight: 600;
            margin-top: 0.75rem;
        }

        input,
        textarea {
            border: 1px solid var(--edge);
            border-radius: 0.25rem;
            box-sizing: border-box;
            font-family: ui-monospace, monospace;
            font-size: 1rem;
            padding: 0.5rem;
            width: 100%;
        }

        button {
            background: var(--ink);
            border: 0;
            border-radius: 0.25rem;
            color: var(--paper);
            cursor: pointer;
            font-size: 1rem;
            margin-top: 0.75rem;
            padding: 0.6rem 1rem;
        }

        button:disabled {
            opacity: 0.5;
        }

        .status {
            font-weight: 600;
            min-height: 1.5rem;
        }

        .status[data-tone="bad"] {
            color: var(--warn);
        }
        """#

    /// The page's script.
    public static var script: String { VerifyPageScript.source }
}
