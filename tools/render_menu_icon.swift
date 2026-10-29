import AppKit
import CoreText

// Renders the input menu icon: Resources/TaviMenuIcon.pdf. It copies the badge macOS draws
// for ABC and 두벌식 (a rounded box with the letter cut out) as a template image, so the
// menu bar and input menu tint it like theirs. The output is committed.
//   swift tools/render_menu_icon.swift [output]

let output = CommandLine.arguments.dropFirst().first ?? "Resources/TaviMenuIcon.pdf"
var box = CGRect(x: 0, y: 0, width: 22, height: 16)
guard let context = CGContext(URL(fileURLWithPath: output) as CFURL, mediaBox: &box, nil) else {
    FileHandle.standardError.write(Data("render_menu_icon: cannot write \(output)\n".utf8))
    exit(1)
}

let badge = CGMutablePath()
badge.addRoundedRect(in: box.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 4, cornerHeight: 4)

let font = NSFont.systemFont(ofSize: 11, weight: .semibold) as CTFont
var character = UniChar(("t" as Character).utf16.first!)
var glyph = CGGlyph()
CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
let letter = CTFontCreatePathForGlyph(font, glyph, nil)!
let bounds = letter.boundingBoxOfPath
let center = CGAffineTransform(translationX: box.midX - bounds.midX, y: box.midY - bounds.midY)
badge.addPath(letter, transform: center)

context.beginPDFPage(nil)
context.addPath(badge)
context.setFillColor(.black)
context.fillPath(using: .evenOdd)
context.endPDFPage()
context.closePDF()
