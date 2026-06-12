import AppKit
import CoreText
import PDFKit
import SwiftUI

enum PDFExportPostProcessor {

    struct Options {
        var paintFullPageBackground: Bool = false
        var backgroundHex: String = "#ffffff"
        var margins: ExportService.ExportOptions.PDFMargins = .init()
        var stampPageNumbers: Bool = false
        var pageNumberColorHex: String = "#636366"
    }

    static func postProcess(_ pdfData: Data, options: Options) -> Data {
        guard options.paintFullPageBackground || options.stampPageNumbers else { return pdfData }
        guard let source = PDFDocument(data: pdfData) else { return pdfData }

        let output = PDFDocument()
        let pageFill = NSColor(Color(hex: options.backgroundHex))
        let numberFont = NSFont.systemFont(ofSize: 10)
        let numberColor = NSColor(Color(hex: options.pageNumberColorHex))

        for index in 0..<source.pageCount {
            guard let page = source.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let stampedData = NSMutableData()
            var mediaBox = bounds

            guard let consumer = CGDataConsumer(data: stampedData as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                output.insert(page, at: output.pageCount)
                continue
            }

            context.beginPDFPage(nil)

            if options.paintFullPageBackground {
                context.setFillColor(pageFill.cgColor)
                context.fill(bounds)
            }

            if let pageRef = page.pageRef {
                context.drawPDFPage(pageRef)
            }

            if options.stampPageNumbers {
                drawPageNumber(
                    "\(index + 1)",
                    in: context,
                    bounds: bounds,
                    bottomMargin: options.margins.bottom,
                    font: numberFont,
                    color: numberColor
                )
            }

            context.endPDFPage()
            context.closePDF()

            if let stampedPage = PDFDocument(data: stampedData as Data)?.page(at: 0) {
                output.insert(stampedPage, at: output.pageCount)
            } else {
                output.insert(page, at: output.pageCount)
            }
        }

        return output.dataRepresentation() ?? pdfData
    }

    private static func drawPageNumber(
        _ label: String,
        in context: CGContext,
        bounds: CGRect,
        bottomMargin: CGFloat,
        font: NSFont,
        color: NSColor
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: label, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let textWidth = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let x = (bounds.width - CGFloat(textWidth)) / 2
        let y = max(10, (bottomMargin - ascent - descent) / 2)

        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
