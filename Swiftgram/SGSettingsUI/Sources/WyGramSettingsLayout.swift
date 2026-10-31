import UIKit
import Display
import LegacyUI
import TelegramPresentationData

// LegacyControllerNode resets a newly attached UIKit view to y = 0. Apply the
// content frame after attachment as well as after Telegram's layout updates.
final class WyGramSettingsWrapper: LegacyController {
    private let settingsTheme: PresentationTheme
    private var settingsLayout: ContainerViewLayout?

    init(theme: PresentationTheme, strings: PresentationStrings) {
        self.settingsTheme = theme
        super.init(presentation: .navigation, theme: theme, strings: strings)
        self.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadDisplayNode() {
        super.loadDisplayNode()
        self.displayNode.backgroundColor = self.settingsTheme.list.blocksBackgroundColor
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.settingsLayout = layout
        super.containerLayoutUpdated(layout, transition: transition)
        self.updateContentFrame()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.updateContentFrame()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.updateContentFrame()
    }
    private func updateContentFrame() {
        guard let layout = self.settingsLayout, let controller = self.legacyController else { return }
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bottom = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom, layout.inputHeight ?? 0)
        let frame = CGRect(x: layout.intrinsicInsets.left, y: top, width: max(0, layout.size.width - layout.intrinsicInsets.left - layout.intrinsicInsets.right), height: max(0, layout.size.height - top - bottom))
        if controller.view.frame != frame { controller.view.frame = frame }
    }
}

class WyGramSettingsTableController: UITableViewController {
    let settingsTheme: PresentationTheme
    init(theme: PresentationTheme) {
        self.settingsTheme = theme
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        // Explicitly retain the grouped style when hosted by a legacy container.
        self.tableView = UITableView(frame: .zero, style: .insetGrouped)
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        self.overrideUserInterfaceStyle = self.settingsTheme.overallDarkAppearance ? .dark : .light
        self.tableView.backgroundColor = self.settingsTheme.list.blocksBackgroundColor
        self.tableView.separatorColor = self.settingsTheme.list.itemBlocksSeparatorColor
        self.tableView.tintColor = self.settingsTheme.list.itemAccentColor
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 76
        self.tableView.sectionHeaderHeight = UITableView.automaticDimension
        self.tableView.sectionFooterHeight = UITableView.automaticDimension
        self.tableView.keyboardDismissMode = .interactive
        self.tableView.cellLayoutMarginsFollowReadableWidth = true
        self.tableView.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = self.tableView.tableHeaderView else { return }
        let width = self.tableView.bounds.width
        let height = header.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        if height > 0 && (abs(header.frame.height - height) > 0.5 || header.frame.width != width) {
            header.frame = CGRect(x: 0, y: 0, width: width, height: height)
            self.tableView.tableHeaderView = header
        }
    }
    func style(_ cell: UITableViewCell) {
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = self.settingsTheme.list.itemBlocksBackgroundColor
        cell.backgroundConfiguration = background
        let selected = UIView()
        selected.backgroundColor = self.settingsTheme.list.itemHighlightedBackgroundColor
        cell.selectedBackgroundView = selected
        cell.tintColor = self.settingsTheme.list.itemAccentColor
        cell.textLabel?.textColor = self.settingsTheme.list.itemPrimaryTextColor
        cell.detailTextLabel?.textColor = self.settingsTheme.list.itemSecondaryTextColor
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
    }
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = self.settingsTheme.list.sectionHeaderTextColor
        header.textLabel?.font = .preferredFont(forTextStyle: .footnote)
        header.textLabel?.adjustsFontForContentSizeCategory = true
    }
    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        guard let footer = view as? UITableViewHeaderFooterView else { return }
        footer.textLabel?.textColor = self.settingsTheme.list.freeTextColor
        footer.textLabel?.font = .preferredFont(forTextStyle: .footnote)
        footer.textLabel?.adjustsFontForContentSizeCategory = true
    }
}

final class WyGramPaddedLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 14, height: size.height + 6)
    }
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 7, dy: 3)) }
}

final class WyGramHistoryCell: UITableViewCell {
    let chatLabel = UILabel()
    let statusLabel = WyGramPaddedLabel()
    let authorLabel = UILabel()
    let dateLabel = UILabel()
    let previewLabel = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.accessoryType = .disclosureIndicator
        self.chatLabel.font = .preferredFont(forTextStyle: .headline)
        self.chatLabel.numberOfLines = 1
        self.authorLabel.font = .preferredFont(forTextStyle: .caption1)
        self.authorLabel.lineBreakMode = .byTruncatingTail
        self.statusLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .medium))
        self.statusLabel.layer.cornerRadius = 5
        self.statusLabel.clipsToBounds = true
        self.statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        self.statusLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        self.dateLabel.font = .preferredFont(forTextStyle: .caption1)
        self.dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        self.dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.authorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.previewLabel.font = .preferredFont(forTextStyle: .subheadline)
        self.previewLabel.numberOfLines = 3
        for label in [self.chatLabel, self.authorLabel, self.statusLabel, self.dateLabel, self.previewLabel] { label.adjustsFontForContentSizeCategory = true }
        let metadata = UIStackView(arrangedSubviews: [self.statusLabel, self.authorLabel, self.dateLabel])
        metadata.axis = .horizontal
        metadata.alignment = .center
        metadata.spacing = 8
        let stack = UIStackView(arrangedSubviews: [self.chatLabel, metadata, self.previewLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -14)
        ])
        self.isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class WyGramStatusSummary: UIView {
    let icon = UIImageView()
    let title = UILabel()
    let detail = UILabel()
    private let card = UIView()
    init(theme: PresentationTheme) {
        super.init(frame: .zero)
        self.card.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.card.layer.cornerRadius = 16
        self.title.font = .preferredFont(forTextStyle: .headline)
        self.title.textColor = theme.list.itemPrimaryTextColor
        self.detail.font = .preferredFont(forTextStyle: .subheadline)
        self.detail.textColor = theme.list.itemSecondaryTextColor
        for label in [self.title, self.detail] { label.numberOfLines = 0; label.adjustsFontForContentSizeCategory = true }
        self.icon.contentMode = .scaleAspectFit
        self.icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        let text = UIStackView(arrangedSubviews: [self.title, self.detail])
        text.axis = .vertical; text.spacing = 6
        let row = UIStackView(arrangedSubviews: [self.icon, text])
        row.alignment = .top; row.spacing = 14
        self.card.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.card); self.card.addSubview(row)
        NSLayoutConstraint.activate([
            self.card.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 20),
            self.card.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -20),
            self.card.topAnchor.constraint(equalTo: self.topAnchor, constant: 16),
            self.card.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: self.card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: self.card.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: self.card.topAnchor, constant: 18),
            row.bottomAnchor.constraint(equalTo: self.card.bottomAnchor, constant: -18),
            self.icon.widthAnchor.constraint(equalToConstant: 30),
            self.icon.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
