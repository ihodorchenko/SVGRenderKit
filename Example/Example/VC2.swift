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
