// Dessine le fond de la fenêtre du DMG, en 1x et 2x, dans le dossier passé en argument.
// Les positions des icônes viennent de settings.py : les deux fichiers bougent ensemble.
import AppKit

// Plus haute que la zone utile de 400 points : le Finder de macOS 27 ajoute une barre
// d'onglets et une barre de chemin qui mangent 90 points de la fenêtre, les versions
// précédentes seulement la barre de titre. Le surplus reste un fond uni.
let width: CGFloat = 640
let height: CGFloat = 490
let appCenter = CGPoint(x: 170, y: 190)
let applicationsCenter = CGPoint(x: 470, y: 190)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: background.swift <dossier>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

func centered(_ text: String, font: NSFont, color: NSColor, y: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
    ]
    NSAttributedString(string: text, attributes: attributes)
        .draw(in: CGRect(x: 40, y: y, width: width - 80, height: font.pointSize * 1.6))
}

func render(scale: CGFloat) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { return nil }
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    // Repère retourné, origine en haut à gauche comme les positions d'icônes du Finder.
    let cg = context.cgContext
    cg.scaleBy(x: scale, y: scale)
    cg.translateBy(x: 0, y: height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    // Fond clair : sur une image de fond, le Finder écrit les noms des icônes en sombre,
    // quel que soit le mode du système, et cette couleur ne se règle pas.
    NSGradient(
        starting: NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1),
        ending: NSColor(srgbRed: 0.92, green: 0.93, blue: 0.95, alpha: 1)
    )?.draw(in: CGRect(x: 0, y: 0, width: width, height: height), angle: -90)

    let primary = NSColor(white: 0.12, alpha: 1)
    let secondary = NSColor(white: 0.42, alpha: 1)
    let accent = NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1)

    centered("Installer Magneto", font: .systemFont(ofSize: 24, weight: .semibold), color: primary, y: 30)
    centered("Faites glisser Magneto sur le dossier Applications.",
             font: .systemFont(ofSize: 14, weight: .regular), color: secondary, y: 68)

    // La flèche, droite d'une icône à l'autre, la pointe dans l'axe du trait.
    let start = CGPoint(x: appCenter.x + 88, y: appCenter.y)
    let tip = CGPoint(x: applicationsCenter.x - 88, y: applicationsCenter.y)
    let arrow = NSBezierPath()
    arrow.move(to: start)
    arrow.line(to: tip)
    arrow.move(to: CGPoint(x: tip.x - 12, y: tip.y - 12))
    arrow.line(to: tip)
    arrow.line(to: CGPoint(x: tip.x - 12, y: tip.y + 12))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    accent.setStroke()
    arrow.stroke()

    // Une app de barre des menus n'a pas d'icône dans le Dock : sans cette ligne, qui
    // l'ouvre une fois copiée ne voit rien se passer et croit l'installation ratée.
    centered("Lancez ensuite Magneto : son icône apparaît dans la barre des menus.",
             font: .systemFont(ofSize: 12, weight: .regular), color: secondary, y: 315)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (scale, name) in [(CGFloat(1), "background.png"), (2, "background@2x.png")] {
    guard let rep = render(scale: scale), let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("rendu impossible en \(scale)x\n".utf8))
        exit(1)
    }
    try png.write(to: output.appendingPathComponent(name))
}
