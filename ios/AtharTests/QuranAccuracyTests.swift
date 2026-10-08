import XCTest
import UIKit
@testable import Athar

final class QuranAccuracyTests: XCTestCase {
    func testIkhlasAndNasAreNumberedVersesWithoutInjectedBasmala() throws {
        let corpus = try XCTUnwrap(QuranResources.corpus)
        XCTAssertEqual(corpus[111].ayahs.count, 4)
        XCTAssertEqual(corpus[113].ayahs.count, 6)
        XCTAssertEqual(corpus[111].ayahs[0].text, "قُلْ هُوَ ٱللَّهُ أَحَدٌ")
        XCTAssertEqual(corpus[111].ayahs[1].text, "ٱللَّهُ ٱلصَّمَدُ")
        XCTAssertEqual(corpus[113].ayahs[0].text, "قُلْ أَعُوذُ بِرَبِّ ٱلنَّاسِ")
        XCTAssertEqual(corpus[113].ayahs[5].text, "مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ")
        for chapter in corpus { for ayah in chapter.ayahs {
            XCTAssertEqual(QuranText.verse(chapter: chapter.number, ayah: ayah), ayah.text)
        } }
        XCTAssertEqual(QuranText.separateBasmalas.count, 112)
        XCTAssertNil(QuranText.separateBasmalas["1"])
        XCTAssertNil(QuranText.separateBasmalas["9"])
        XCTAssertEqual(QuranText.separateBasmalas["112"], QuranText.basmala)
        XCTAssertEqual(QuranText.separateBasmalas["114"], QuranText.basmala)
        // Tanzil preserves a source shadda in these separate basmalas; do not reject all basmalas.
        XCTAssertTrue(QuranText.separateBasmalas["95"]?.hasPrefix("بِّسْمِ") == true)
        XCTAssertTrue(QuranText.separateBasmalas["97"]?.hasPrefix("بِّسْمِ") == true)
    }

    @MainActor func testTrustedArabicFontCoversEverySourceCharacter() throws {
        XCTAssertTrue(QuranTypography.available, "The pinned Arabic font must cover every source character before Quran text is shown.")
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 120)
        let result = try XCTUnwrap(MushafTypesetter.make(text: "ٱللَّهُ ٱلصَّمَدُ", fontName: QuranTypography.postScriptName,
                                                      size: 30, bounds: bounds, justify: false))
        XCTAssertTrue(bounds.contains(result.inkBounds))
        XCTAssertNil(MushafTypesetter.make(text: "😀", fontName: QuranTypography.postScriptName,
                                          size: 30, bounds: bounds, justify: false), "Font fallback is rejected, even if a system emoji font could draw the input.")
    }
}
