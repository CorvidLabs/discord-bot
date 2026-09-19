import Foundation
import Testing
import Verify
@testable import VerifyHTTP

/// What the page says before anybody signs anything, and what it carries in
/// its headers (REQ-verify-009, REQ-verify-010).
@Suite("The page")
struct PageTests {

    // MARK: - What it says

    @Test("The page warns that nobody should ever send a member this link, before any call is made")
    func theWarningIsInTheStaticPage() async throws {
        // Goes red against the warning arriving with the card, which is the
        // shape where a member whose card call fails reads a page with no
        // warning on it at all. The named account is the whole mitigation
        // for a relayed prompt, and half of it is the sentence beside the
        // name.
        let surface = try SurfaceFixtures.surface()
        let page = await surface.service.respond(
            to: SurfaceFixtures.get(VerifyRouting.pagePath),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(page.status == 200)
        #expect(page.contentType == "text/html; charset=utf-8")
        #expect(page.body.contains("Only go on if that is your own account"))
        #expect(page.body.contains("Nobody should ever send you this"))
        #expect(page.body.contains("id=\"account\""))
    }

    @Test("The page tells a member what the code is for")
    func theCodeIsExplained() {
        #expect(VerifyPage.html.contains("It should match the code you"))
    }

    // MARK: - What it loads

    @Test("The page carries no inline script and no inline style, so the policy can name one origin")
    func nothingIsInline() {
        // Goes red against somebody inlining the script for convenience,
        // which forces `unsafe-inline` into the policy and with it every
        // injected script anybody ever manages to land on the page.
        #expect(!VerifyPage.html.contains("<script>"))
        #expect(!VerifyPage.html.contains("<style"))
        #expect(VerifyPage.html.contains("src=\"/verify/app.js\""))
        #expect(VerifyPage.html.contains("href=\"/verify/app.css\""))
        #expect(VerifyHTTPResponse.contentSecurityPolicy.contains("script-src 'self'"))
        #expect(!VerifyHTTPResponse.contentSecurityPolicy.contains("unsafe-inline"))
        #expect(!VerifyHTTPResponse.contentSecurityPolicy.contains("http"))
    }

    @Test("The script takes the session id out of the address bar and writes the name as text")
    func theScriptHandlesTheCredential() {
        // Two properties, both of them one line of script and both of them
        // easy to lose in an edit: the fragment is removed so a screenshot
        // or the back button cannot hand the credential to somebody else,
        // and a display name from a chat service is never written as markup.
        #expect(VerifyPage.script.contains("history.replaceState"))
        #expect(VerifyPage.script.contains("elements.account.textContent = card.account"))
        #expect(!VerifyPage.script.contains("innerHTML"))
        #expect(VerifyPage.script.contains("location.hash"))
    }

    @Test("Every element the script reaches for is on the page")
    func theScriptAndThePageAgree() {
        // The page and the script are two strings in two files, and a
        // renamed id in one of them is a member staring at a page that
        // silently does nothing. There is no browser here to catch it, so
        // the agreement is asserted instead.
        let wanted = VerifyPage.script
            .components(separatedBy: "getElementById(\"")
            .dropFirst()
            .compactMap { $0.split(separator: "\"", maxSplits: 1).first.map(String.init) }
        #expect(!wanted.isEmpty)
        for identifier in wanted {
            #expect(VerifyPage.html.contains("id=\"\(identifier)\""), "the page has no \(identifier)")
        }
    }

    @Test("The script names one extension point, and it is the one the documentation names")
    func theAdapterHasOneName() {
        #expect(VerifyPage.script.contains("window[\"\(VerifyPageScript.adapterGlobalName)\"]"))
    }

    // MARK: - Headers

    @Test("Every answer carries no-referrer, so the fragment never reaches anybody else")
    func everyAnswerIsNoReferrer() async throws {
        // The one obligation on this list that a browser enforces rather
        // than this process: the address of a page opened with a session id
        // in its fragment must not be sent anywhere (REQ-verify-009).
        #expect(VerifyHTTPResponse.securityHeaders["Referrer-Policy"] == "no-referrer")
        #expect(VerifyHTTPResponse.securityHeaders["Cache-Control"] == "no-store")
        #expect(VerifyHTTPResponse.securityHeaders["X-Frame-Options"] == "DENY")

        let surface = try SurfaceFixtures.surface()
        let responses = [
            await surface.service.respond(
                to: SurfaceFixtures.get(VerifyRouting.pagePath),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            ),
            await surface.service.respond(
                to: SurfaceFixtures.get("/nothing"),
                from: SurfaceFixtures.source,
                now: SurfaceFixtures.now
            )
        ]
        for response in responses {
            let wire = String(decoding: response.wireBytes, as: UTF8.self)
            #expect(wire.contains("Referrer-Policy: no-referrer"))
            #expect(wire.contains("Cache-Control: no-store"))
            #expect(wire.contains("Content-Length: \(response.body.utf8.count)"))
        }
    }

    @Test("A content type carrying a newline cannot add a header of its own")
    func aContentTypeCannotEndTheHeaderBlock() {
        // Inside this target every content type is a literal, so nothing a
        // request carries reaches this. It is a public product other
        // programs serve the same flow with, though, and a newline in a
        // header value ends the header block early and lets whatever
        // follows be read as a header of its own. The health endpoint in
        // this package guards exactly this.
        let injected = VerifyHTTPResponse(
            status: 200,
            contentType: "text/html\r\nX-Injected: yes",
            body: "hello"
        )
        let wire = String(decoding: injected.wireBytes, as: UTF8.self)
        #expect(!wire.contains("X-Injected"))
        #expect(wire.contains("Content-Type: \(VerifyHTTPResponse.fallbackContentType)"))
        #expect(wire.contains("Content-Length: 5"))
    }

    @Test("The script and the stylesheet are served as themselves")
    func theAssetsAreServed() async throws {
        let surface = try SurfaceFixtures.surface()
        let script = await surface.service.respond(
            to: SurfaceFixtures.get(VerifyRouting.scriptPath),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(script.status == 200)
        #expect(script.contentType == "text/javascript; charset=utf-8")
        #expect(script.body == VerifyPage.script)

        let stylesheet = await surface.service.respond(
            to: SurfaceFixtures.get(VerifyRouting.stylesheetPath),
            from: SurfaceFixtures.source,
            now: SurfaceFixtures.now
        )
        #expect(stylesheet.status == 200)
        #expect(stylesheet.contentType == "text/css; charset=utf-8")
    }
}
