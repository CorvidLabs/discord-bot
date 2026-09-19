import Foundation
import Testing

@testable import Surface

/// A card is a value, and a picture nobody can load costs the picture.
@Suite("Cards")
struct SurfaceCardTests {

    @Test("Two cards built the same way are equal, so a test can assert on one without a gateway")
    func cardsAreValues() {
        let left = SurfaceCard(title: "T", description: "D", fields: [SurfaceField(name: "n", value: "v")])
        let right = SurfaceCard(title: "T", description: "D", fields: [SurfaceField(name: "n", value: "v")])
        #expect(left == right)
    }

    @Test("A thumbnail that is not http or https is dropped, and the card survives")
    func unusableThumbnailDropsThePicture() {
        // Discord refuses the whole message for one of these, so an operator
        // who mistypes a logo would otherwise lose every card rather than
        // one picture.
        for candidate in ["cid:hand.png", "/relative/logo.png", "data:image/png;base64,AAAA", "logo.png"] {
            let card = SurfaceCard(title: "T", thumbnailURL: candidate)
            #expect(card.thumbnailURL == nil, "\(candidate) should have been dropped")
            #expect(card.title == "T")
        }
    }

    @Test("A usable picture is kept exactly as written")
    func usablePictureIsKept() {
        let card = SurfaceCard(
            title: "T",
            thumbnailURL: "https://pictures.example.test/logo.png",
            imageURL: "http://pictures.example.test/big.png"
        )
        #expect(card.thumbnailURL == "https://pictures.example.test/logo.png")
        #expect(card.imageURL == "http://pictures.example.test/big.png")
    }

    @Test("An unset picture is no picture (ADOPT-6.a)")
    func unsetIsNothing() {
        #expect(SurfaceCard(title: "T").thumbnailURL == nil)
    }

    @Test("A button carries an id, never a closure, so an old build's button is a string nobody claims")
    func buttonsAreData() {
        let work = ButtonSpec(id: "verify:add", label: "Add", style: .primary)
        #expect(work.isRoutable)
        #expect(work.url == nil)

        let link = ButtonSpec.link(label: "Open", url: "https://example.test")
        #expect(link.isRoutable == false)
        #expect(link.id.isEmpty)
    }

    @Test("A work button asked for the link style is corrected rather than sent without a url")
    func linkStyleWithoutURLIsCorrected() {
        // Discord refuses the whole message for a link button with no url,
        // so a caller's mistake here would cost a member their reply.
        let button = ButtonSpec(id: "x:y", label: "Go", style: .link)
        #expect(button.style == .secondary)
    }

    @Test("A message always carries an attachment list, empty rather than absent")
    func attachmentsAreAlwaysPresent() {
        #expect(VisibleMessage(content: "hello").attachments.isEmpty)
    }
}
