import UIKit
import SVGRenderKit

class ViewController2: UIViewController {

    private let columns = 3
    private let spacing: CGFloat = 8
    private let cellHeight: CGFloat = 140

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.white
        title = "SVG Examples"
        setupGrid()
    }

    private func setupGrid() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = spacing
        grid.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(grid)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            grid.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: spacing),
            grid.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: spacing),
            grid.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -spacing),
            grid.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -spacing),
            grid.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * spacing)
        ])

        let names = svgNames()
        var row: UIStackView?
        for (index, name) in names.enumerated() {
            if index % columns == 0 {
                let newRow = UIStackView()
                newRow.axis = .horizontal
                newRow.distribution = .fillEqually
                newRow.spacing = spacing
                grid.addArrangedSubview(newRow)
                row = newRow
            }
            row?.addArrangedSubview(makeCell(name: name))
        }
    }

    private func makeCell(name: String) -> UIView {
        let cell = UIView()
        cell.backgroundColor = UIColor(white: 0.95, alpha: 1)
        cell.layer.cornerRadius = 4
        cell.clipsToBounds = true
        cell.heightAnchor.constraint(equalToConstant: cellHeight).isActive = true

        let svgView = SVGView()
        svgView.set(SVGName: "svg/" + name)
        svgView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(svgView)

        let label = UILabel()
        label.text = name
        label.font = UIFont.systemFont(ofSize: 10)
        label.textColor = UIColor.darkGray
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            svgView.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
            svgView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            svgView.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            svgView.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -4),

            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
            label.heightAnchor.constraint(equalToConstant: 16)
        ])

        return cell
    }

    /// Возвращает имена SVG относительно папки `svg` (например `Alfach_0.svg`, `test/tiger.svg`).
    private func svgNames() -> [String] {
        guard let resourceURL = Bundle.main.resourceURL else { return [] }
        let svgDirectory = resourceURL.appendingPathComponent("svg")
        guard let enumerator = FileManager.default.enumerator(atPath: svgDirectory.path) else { return [] }
        var names: [String] = []
        for case let path as String in enumerator {
            if (path as NSString).pathExtension.lowercased() == "svg" {
                names.append(path)
            }
        }
        return names.sorted()
    }
}
