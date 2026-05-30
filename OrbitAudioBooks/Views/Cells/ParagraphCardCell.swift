import UIKit

/// Card cell for EPUB paragraph/sentence blocks. Renders HTML content via UITextView.
final class ParagraphCardCell: UICollectionViewCell {
    static let reuseIdentifier = "ParagraphCardCell"

    private let textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.backgroundColor = .clear
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let activeBar: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBlue
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    var isActiveBlock: Bool = false {
        didSet {
            activeBar.isHidden = !isActiveBlock
            contentView.alpha = isActiveBlock ? 1.0 : 0.95
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(textView)
        contentView.addSubview(activeBar)
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true

        NSLayoutConstraint.activate([
            activeBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            activeBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            activeBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            activeBar.widthAnchor.constraint(equalToConstant: 3),

            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func configure(with block: EPubBlockRecord, font: UIFont, tint: UIColor, lineSpacing: CGFloat) {
        let displayHTML = block.htmlContent ?? block.text ?? ""
        let data = Data(displayHTML.utf8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) {
            let range = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(.font, value: font, range: range)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = lineSpacing
            attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
            textView.attributedText = attributed
        } else {
            textView.text = block.text
            textView.font = font
        }

        contentView.backgroundColor = tint.withAlphaComponent(0.08)
    }
}
