import UIKit
import SVGRenderKit

/// Вариант цвета подложки для галереи и детального просмотра.
enum SubstrateStyle: Int, CaseIterable {
    case gray = 0
    case light = 1
    case dark = 2

    var title: String {
        switch self {
        case .gray: return "Серая"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    /// Цвет самой подложки (ячейка / карточка).
    var substrateColor: UIColor {
        switch self {
        case .gray: return UIColor(white: 0.95, alpha: 1)
        case .light: return UIColor.white
        case .dark: return UIColor(white: 0.12, alpha: 1)
        }
    }

    /// Цвет фона экрана позади подложки.
    var screenColor: UIColor {
        switch self {
        case .gray, .light: return UIColor.white
        case .dark: return UIColor(white: 0.08, alpha: 1)
        }
    }

    var textColor: UIColor {
        switch self {
        case .gray, .light: return UIColor.darkGray
        case .dark: return UIColor.lightGray
        }
    }

    var borderColor: UIColor {
        switch self {
        case .gray, .light: return UIColor(white: 0, alpha: 0.10)
        case .dark: return UIColor(white: 1, alpha: 0.12)
        }
    }
}

/// Общее хранилище выбранного варианта подложки.
final class SubstrateStore {
    static let shared = SubstrateStore()
    var style: SubstrateStyle = .gray
    private init() {}
}

/// Собирает кнопку-меню выбора подложки для навбара.
func makeSubstrateButton(onSelect: @escaping () -> Void) -> UIBarButtonItem {
    let current = SubstrateStore.shared.style
    let actions = SubstrateStyle.allCases.map { style in
        UIAction(title: style.title, state: style == current ? .on : .off) { _ in
            SubstrateStore.shared.style = style
            onSelect()
        }
    }
    let menu = UIMenu(title: "Подложка", options: .displayInline, children: actions)
    return UIBarButtonItem(image: UIImage(systemName: "paintpalette"), menu: menu)
}

/// Приводит внешний вид навбара в соответствие с выбранной подложкой.
func applyNavBarAppearance(style: SubstrateStyle, to navigationController: UINavigationController?) {
    guard let navigationController = navigationController else { return }
    let appearance = UINavigationBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = style.screenColor
    appearance.titleTextAttributes = [.foregroundColor: style.textColor]
    navigationController.navigationBar.standardAppearance = appearance
    navigationController.navigationBar.scrollEdgeAppearance = appearance
    navigationController.navigationBar.compactAppearance = appearance
    navigationController.navigationBar.tintColor = style == .dark ? UIColor.white : UIColor.darkGray
}

class ViewController2: UIViewController {

    private let columns = 3
    private let spacing: CGFloat = 8
    private let cellHeight: CGFloat = 140

    private var names: [String] = []
    private var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "SVG Examples"
        names = svgNames()
        setupCollectionView()
        refreshSubstrateButton()
        applyStyle()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        collectionView.flashScrollIndicators()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return SubstrateStore.shared.style == .dark ? .lightContent : .default
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = true
        collectionView.alwaysBounceVertical = true
        collectionView.register(SVGCell.self, forCellWithReuseIdentifier: SVGCell.reuseIdentifier)
        view.addSubview(collectionView)
        self.collectionView = collectionView

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func refreshSubstrateButton() {
        navigationItem.rightBarButtonItem = makeSubstrateButton { [weak self] in
            self?.applyStyle()
            self?.refreshSubstrateButton()
        }
    }

    private func applyStyle() {
        let style = SubstrateStore.shared.style
        view.backgroundColor = style.screenColor
        collectionView.backgroundColor = style.screenColor
        collectionView.indicatorStyle = style == .dark ? .white : .black
        collectionView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -2)
        applyNavBarAppearance(style: style, to: navigationController)
        setNeedsStatusBarAppearanceUpdate()
        collectionView.reloadData()
    }

    /// Возвращает пути SVG относительно корня бандла, включая подпапки
    /// (например `svg_0.0/Alfach_0.svg`, `svg_1.0/alert/foo.svg`).
    private func svgNames() -> [String] {
        guard let resourceURL = Bundle.main.resourceURL else { return [] }
        let directories = ["svg_0.0", "svg_1.0", "svg_2.0", "svg_3.0"]
        var names: [String] = []
        for directory in directories {
            let directoryURL = resourceURL.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(atPath: directoryURL.path) else { continue }
            for case let path as String in enumerator {
                if (path as NSString).pathExtension.lowercased() == "svg" {
                    names.append(directory + "/" + path)
                }
            }
        }
        return names.sorted()
    }
}

extension ViewController2: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return names.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SVGCell.reuseIdentifier, for: indexPath) as! SVGCell
        cell.configure(name: names[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let totalSpacing = spacing * CGFloat(columns + 1)
        let width = floor((collectionView.bounds.width - totalSpacing) / CGFloat(columns))
        return CGSize(width: width, height: cellHeight)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let detail = SVGDetailViewController(name: names[indexPath.item])
        let nav = UINavigationController(rootViewController: detail)
        nav.modalPresentationStyle = .fullScreen
        nav.modalTransitionStyle = .crossDissolve
        present(nav, animated: true)
    }
}

final class SVGCell: UICollectionViewCell {

    static let reuseIdentifier = "SVGCell"

    private let svgView = SVGView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        contentView.layer.cornerRadius = 4
        contentView.clipsToBounds = true
        contentView.layer.borderWidth = 1.0 / UIScreen.main.scale

        svgView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(svgView)

        label.font = UIFont.systemFont(ofSize: 10)
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            svgView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            svgView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            svgView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            svgView.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -4),

            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            label.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    func configure(name: String) {
        let style = SubstrateStore.shared.style
        contentView.backgroundColor = style.substrateColor
        contentView.layer.borderColor = style.borderColor.cgColor
        label.textColor = style.textColor
        label.text = name
        svgView.clear()
        svgView.set(SVGName: name)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        svgView.clear()
        label.text = nil
    }
}

final class SVGDetailViewController: UIViewController {

    private let name: String
    private let svgView = SVGView()
    private let cardView = UIView()

    init(name: String) {
        self.name = name
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = (name as NSString).lastPathComponent

        setupCardView()
        setupNavBar()

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        view.addGestureRecognizer(tap)

        svgView.set(SVGName: name)
        applyStyle()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return SubstrateStore.shared.style == .dark ? .lightContent : .default
    }

    private func setupCardView() {
        cardView.layer.cornerRadius = 8
        cardView.clipsToBounds = true
        cardView.layer.borderWidth = 1.0 / UIScreen.main.scale
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        svgView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(svgView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cardView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            svgView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            svgView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            svgView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            svgView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        ])
    }

    private func setupNavBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Закрыть",
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        refreshSubstrateButton()
    }

    private func refreshSubstrateButton() {
        navigationItem.rightBarButtonItem = makeSubstrateButton { [weak self] in
            self?.applyStyle()
            self?.refreshSubstrateButton()
        }
    }

    private func applyStyle() {
        let style = SubstrateStore.shared.style
        view.backgroundColor = style.screenColor
        cardView.backgroundColor = style.substrateColor
        cardView.layer.borderColor = style.borderColor.cgColor
        applyNavBarAppearance(style: style, to: navigationController)
        setNeedsStatusBarAppearanceUpdate()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func backgroundTapped() {
        dismiss(animated: true)
    }
}
