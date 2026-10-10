import UIKit
import SVGRenderKit

class ViewController2: UIViewController {

    private let columns = 3
    private let spacing: CGFloat = 8
    private let cellHeight: CGFloat = 140

    private var names: [String] = []
    private var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.white
        title = "SVG Examples"
        names = svgNames()
        setupCollectionView()
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = UIColor.white
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = self
        collectionView.delegate = self
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
        detail.modalPresentationStyle = .fullScreen
        detail.modalTransitionStyle = .crossDissolve
        present(detail, animated: true)
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
        contentView.backgroundColor = UIColor(white: 0.95, alpha: 1)
        contentView.layer.cornerRadius = 4
        contentView.clipsToBounds = true

        svgView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(svgView)

        label.font = UIFont.systemFont(ofSize: 10)
        label.textColor = UIColor.darkGray
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

final class SVGDetailViewController: UIViewController, UIGestureRecognizerDelegate {

    private let name: String
    private let svgView = SVGView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
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
        view.backgroundColor = UIColor.white

        setupTitleLabel()
        setupSVGView()
        setupCloseButton()

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tap.delegate = self
        view.addGestureRecognizer(tap)

        svgView.set(SVGName: name)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    private func setupTitleLabel() {
        titleLabel.text = name
        titleLabel.font = UIFont.systemFont(ofSize: 13)
        titleLabel.textColor = UIColor.darkGray
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 72),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -72)
        ])
    }

    private func setupSVGView() {
        cardView.backgroundColor = UIColor(white: 0.95, alpha: 1)
        cardView.layer.cornerRadius = 8
        cardView.clipsToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        svgView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(svgView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cardView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            svgView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            svgView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            svgView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            svgView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        ])
    }

    private func setupCloseButton() {
        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .medium)
        closeButton.setTitleColor(UIColor.darkGray, for: .normal)
        closeButton.backgroundColor = UIColor(white: 0, alpha: 0.06)
        closeButton.layer.cornerRadius = 22
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func backgroundTapped() {
        dismiss(animated: true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = touch.view, view.isDescendant(of: closeButton) {
            return false
        }
        return true
    }
}
