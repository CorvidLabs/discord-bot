@preconcurrency import Foundation

/// The page's script, vendored as text, depending on nothing.
///
/// **It reads the session id out of the fragment and puts it nowhere.** Not
/// in the address bar, which it rewrites on the first line; not in
/// `localStorage`, where the next person on a shared machine would find it;
/// not in a query string, which is what every log on the path writes down.
/// It lives in one closure variable for the life of the tab and travels only
/// in a request body (REQ-verify-003, REQ-verify-009).
///
/// **The member's name is written with `textContent` and never with
/// `innerHTML`.** A display name comes from a chat service and is whatever
/// somebody typed into it, which on that path includes markup.
public enum VerifyPageScript: Sendable {

    // MARK: - Properties

    /// What an operator's own wallet connector is called on `window`.
    ///
    /// The whole extension point, written down so the name in the script and
    /// the name in the documentation cannot drift. An object with two
    /// methods: `connect()`, answering an address, and `signProof({address,
    /// note, maximumFeeMicroAlgos})`, answering the signed transaction as
    /// base64. Absent, the page falls back to a typed address and a pasted
    /// blob, which works and is clumsy on a phone.
    public static let adapterGlobalName: String = "verifyWalletAdapter"

    /// The script itself.
    public static let source: String = #"""
        "use strict";

        // The session id is a bearer credential. It arrives in the fragment,
        // which no browser sends to a server, and it is taken out of the
        // address bar before anything else happens so that a screenshot, a
        // shared screen or the back button cannot hand it to somebody else.
        const sessionId = window.location.hash.slice(1);
        history.replaceState({}, document.title, window.location.pathname);

        const elements = {
            account: document.getElementById("account"),
            code: document.getElementById("code"),
            expires: document.getElementById("expires"),
            challenge: document.getElementById("challenge"),
            status: document.getElementById("status"),
            stepConnect: document.getElementById("step-connect"),
            stepSign: document.getElementById("step-sign"),
            pinnedNote: document.getElementById("pinned-note"),
            connectWallet: document.getElementById("connect-wallet"),
            connectTyped: document.getElementById("connect-typed"),
            signWallet: document.getElementById("sign-wallet"),
            submitPasted: document.getElementById("submit-pasted"),
            address: document.getElementById("address"),
            blob: document.getElementById("blob"),
            manual: document.getElementById("manual")
        };

        let card = null;

        function say(message, tone) {
            elements.status.textContent = message;
            elements.status.dataset.tone = tone || "";
        }

        function adapter() {
            return window["verifyWalletAdapter"] || null;
        }

        async function call(path, payload) {
            const response = await fetch(path, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                cache: "no-store",
                referrerPolicy: "no-referrer",
                body: JSON.stringify(Object.assign({ session: sessionId }, payload))
            });
            let body = {};
            try {
                body = await response.json();
            } catch (error) {
                body = {};
            }
            return { ok: response.ok, body: body };
        }

        function refuse(body) {
            const reason = body.error || "This did not work. Try again.";
            const handle = body.handle ? " (reference " + body.handle + ")" : "";
            say(reason + handle, "bad");
            if (body.retryable === false) {
                elements.stepConnect.hidden = true;
                elements.stepSign.hidden = true;
            }
        }

        async function load() {
            if (!/^[0-9a-f]{32}$/.test(sessionId)) {
                say("This link is missing its second half. Run the command again for a new one.", "bad");
                return;
            }
            const answer = await call("/verify/card", {});
            if (!answer.ok) {
                refuse(answer.body);
                return;
            }
            card = answer.body;
            // A text node, never markup: a display name is whatever
            // somebody typed into a chat service, and a suite asserts that
            // the other way of writing it appears nowhere in this file.
            elements.account.textContent = card.account;
            elements.code.textContent = card.code;
            elements.challenge.textContent = card.challenge;
            elements.expires.textContent = "at " + new Date(card.expiresAt * 1000).toLocaleTimeString();
            if (card.pinnedAddress) {
                elements.pinnedNote.hidden = false;
                elements.address.value = card.pinnedAddress;
            }
            if (adapter() && typeof adapter().connect === "function") {
                elements.connectWallet.hidden = false;
            }
            if (adapter() && typeof adapter().signProof === "function") {
                elements.signWallet.hidden = false;
                elements.manual.hidden = true;
            }
            if (card.connectedAddress) {
                elements.stepSign.hidden = false;
                say("Sign the prompt to finish.");
            } else {
                elements.stepConnect.hidden = false;
                say("Name the account you want to prove.");
            }
        }

        async function connect(address) {
            const answer = await call("/verify/connect", { address: address });
            if (!answer.ok) {
                refuse(answer.body);
                return;
            }
            card.connectedAddress = answer.body.connectedAddress;
            elements.stepConnect.hidden = true;
            elements.stepSign.hidden = false;
            say("Now sign the prompt. It moves nothing.");
        }

        async function submit(blob) {
            const answer = await call("/verify/submit", { blob: blob });
            if (!answer.ok) {
                refuse(answer.body);
                return;
            }
            elements.stepSign.hidden = true;
            say(answer.body.message);
        }

        elements.connectTyped.addEventListener("click", function () {
            const typed = elements.address.value.trim();
            if (!typed) {
                say("Type the address of the account you want to prove.", "bad");
                return;
            }
            connect(typed);
        });

        elements.connectWallet.addEventListener("click", async function () {
            try {
                const address = await adapter().connect();
                connect(address);
            } catch (error) {
                say("That wallet did not connect. Type the address instead.", "bad");
            }
        });

        elements.signWallet.addEventListener("click", async function () {
            try {
                const signed = await adapter().signProof({
                    address: card.connectedAddress,
                    note: new TextEncoder().encode(card.challenge),
                    maximumFeeMicroAlgos: card.maximumFeeMicroAlgos
                });
                submit(signed);
            } catch (error) {
                say("That wallet did not sign. Try again, or paste a signed transaction.", "bad");
            }
        });

        elements.submitPasted.addEventListener("click", function () {
            const pasted = elements.blob.value.trim();
            if (!pasted) {
                say("Paste the signed transaction first.", "bad");
                return;
            }
            submit(pasted);
        });

        load();
        """#
}
