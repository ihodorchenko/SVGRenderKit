# ``SVGRenderKitSwiftUI``

A SwiftUI wrapper around `SVGView`.

## Overview

``SVGImageView`` renders an SVG from a bundled resource, markup, data or a file URL, without writing a
`UIViewRepresentable` by hand. It takes all the space it is offered, so give it a size.

```swift
import SwiftUI
import SVGRenderKitSwiftUI

struct IconView: View {
    var body: some View {
        SVGImageView(name: "icons/my-icon.svg", fillColors: ["path1": .systemBlue])
            .frame(width: 48, height: 48)
    }
}
```

The underlying UIKit view, parsing and rendering are documented in the `SVGRenderKit` module.

## Topics

### Views

- ``SVGImageView``
