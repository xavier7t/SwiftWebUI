import Foundation

public enum ChildPolicy: Sendable, Equatable {
    case none, optional, required
}

/// One argument of a view or modifier. A `nil` label means the argument is positional.
public struct ArgumentSpec: Equatable, Sendable {
    public let label: String?
    public let summary: String

    public init(_ label: String?, _ summary: String) {
        self.label = label
        self.summary = summary
    }
}

public struct ViewSpec: Equatable, Sendable {
    public enum Category: String, Sendable { case layout, content, gradient }

    public let name: String
    public let category: Category
    public let summary: String
    public let example: String
    public let arguments: [ArgumentSpec]
    public let children: ChildPolicy
    public let minArguments: Int
}

public struct ModifierSpec: Equatable, Sendable {
    public let name: String
    public let summary: String
    public let example: String
    public let arguments: [ArgumentSpec]
    public let minArguments: Int
}

/// The single list of views and modifiers MVP1 supports. The parser validates against it, and the
/// renderer and the in-app reference are generated from it.
public enum Registry {
    public static let views: [ViewSpec] = [
        ViewSpec(name: "VStack", category: .layout, summary: "Arranges children vertically.",
                 example: "VStack(spacing: 8) { … }",
                 arguments: [ArgumentSpec("alignment", "Horizontal alignment, e.g. .leading"),
                             ArgumentSpec("spacing", "Space between children")],
                 children: .optional, minArguments: 0),
        ViewSpec(name: "HStack", category: .layout, summary: "Arranges children horizontally.",
                 example: "HStack(spacing: 8) { … }",
                 arguments: [ArgumentSpec("alignment", "Vertical alignment, e.g. .top"),
                             ArgumentSpec("spacing", "Space between children")],
                 children: .optional, minArguments: 0),
        ViewSpec(name: "ZStack", category: .layout, summary: "Layers children on top of each other.",
                 example: "ZStack { … }",
                 arguments: [ArgumentSpec("alignment", "Alignment of the layers, e.g. .center")],
                 children: .optional, minArguments: 0),
        ViewSpec(name: "Spacer", category: .layout, summary: "Expands to fill the available space.",
                 example: "Spacer()",
                 arguments: [ArgumentSpec("minLength", "Minimum length")],
                 children: .none, minArguments: 0),
        ViewSpec(name: "List", category: .layout, summary: "A vertical list of rows.",
                 example: "List { … }", arguments: [], children: .required, minArguments: 0),
        ViewSpec(name: "ScrollView", category: .layout,
                 summary: "Scrolls its content when it is larger than the view.",
                 example: "ScrollView(.horizontal) { HStack { … } }",
                 arguments: [ArgumentSpec(nil, ".vertical (default), .horizontal or [.horizontal, .vertical]"),
                             ArgumentSpec("showsIndicators", "Accepted and ignored")],
                 children: .required, minArguments: 0),
        ViewSpec(name: "ForEach", category: .layout,
                 summary: "Repeats content for each item of a literal array or range.",
                 example: "ForEach(0..<3) { i in … }",
                 arguments: [ArgumentSpec(nil, "A literal array or range"), ArgumentSpec("id", "Only \\.self is supported")],
                 children: .required, minArguments: 1),
        ViewSpec(name: "LinearGradient", category: .gradient,
                 summary: "Blends colors along a line. Also works as a color in .background and .foregroundStyle.",
                 example: "LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)",
                 arguments: [ArgumentSpec("colors", "An array of colors"),
                             ArgumentSpec("stops", "An array of Gradient.Stop(color:location:)"),
                             ArgumentSpec("gradient", "Gradient(colors:) or Gradient(stops:)"),
                             ArgumentSpec("startPoint", "Where the first color starts, e.g. .top or UnitPoint(x: 0.2, y: 0)"),
                             ArgumentSpec("endPoint", "Where the last color ends, e.g. .bottom")],
                 children: .none, minArguments: 3),
        ViewSpec(name: "RadialGradient", category: .gradient,
                 summary: "Blends colors outward from a center point, in a circle.",
                 example: "RadialGradient(colors: [.yellow, .red], center: .center, startRadius: 0, endRadius: 200)",
                 arguments: [ArgumentSpec("colors", "An array of colors"),
                             ArgumentSpec("stops", "An array of Gradient.Stop(color:location:)"),
                             ArgumentSpec("gradient", "Gradient(colors:) or Gradient(stops:)"),
                             ArgumentSpec("center", "The center, e.g. .center. Default .center"),
                             ArgumentSpec("startRadius", "Radius of the first color, in points"),
                             ArgumentSpec("endRadius", "Radius of the last color, in points")],
                 children: .none, minArguments: 3),
        ViewSpec(name: "AngularGradient", category: .gradient,
                 summary: "Blends colors around a center point, like a color wheel.",
                 example: "AngularGradient(colors: [.red, .blue, .red], center: .center)",
                 arguments: [ArgumentSpec("colors", "An array of colors"),
                             ArgumentSpec("stops", "An array of Gradient.Stop(color:location:)"),
                             ArgumentSpec("gradient", "Gradient(colors:) or Gradient(stops:)"),
                             ArgumentSpec("center", "The center, e.g. .center. Default .center"),
                             ArgumentSpec("angle", "Start angle, e.g. .degrees(90)"),
                             ArgumentSpec("startAngle", "Start angle, e.g. .degrees(0)"),
                             ArgumentSpec("endAngle", "End angle. Without it the gradient goes all the way around")],
                 children: .none, minArguments: 1),
        ViewSpec(name: "EllipticalGradient", category: .gradient,
                 summary: "Blends colors outward from a center point, in an ellipse that follows the view's shape.",
                 example: "EllipticalGradient(colors: [.white, .blue], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)",
                 arguments: [ArgumentSpec("colors", "An array of colors"),
                             ArgumentSpec("stops", "An array of Gradient.Stop(color:location:)"),
                             ArgumentSpec("gradient", "Gradient(colors:) or Gradient(stops:)"),
                             ArgumentSpec("center", "The center, e.g. .center. Default .center"),
                             ArgumentSpec("startRadiusFraction", "Start radius as a fraction of the size. Default 0"),
                             ArgumentSpec("endRadiusFraction", "End radius as a fraction of the size. Default 0.5")],
                 children: .none, minArguments: 1),
        ViewSpec(name: "MeshGradient", category: .gradient,
                 summary: "Blends colors across a grid of points. Approximated in the browser, so blending differs slightly from SwiftUI.",
                 example: "MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]], colors: [.red, .blue, .green, .yellow])",
                 arguments: [ArgumentSpec("width", "Points per row, at least 2"),
                             ArgumentSpec("height", "Points per column, at least 2"),
                             ArgumentSpec("points", "width × height points, each written as [x, y] from 0 to 1"),
                             ArgumentSpec("colors", "One color per point"),
                             ArgumentSpec("background", "Color behind the mesh"),
                             ArgumentSpec("smoothsColors", "Accepted and ignored"),
                             ArgumentSpec("colorSpace", "Accepted and ignored")],
                 children: .none, minArguments: 4),
        ViewSpec(name: "Color", category: .content,
                 summary: "A view that fills the space it is given with a color.",
                 example: "Color.blue",
                 arguments: [ArgumentSpec("red", "Red, 0 to 1"), ArgumentSpec("green", "Green, 0 to 1"),
                             ArgumentSpec("blue", "Blue, 0 to 1"), ArgumentSpec("white", "Gray level, 0 to 1"),
                             ArgumentSpec("opacity", "Opacity, 0 to 1")],
                 children: .none, minArguments: 1),
        ViewSpec(name: "Text", category: .content, summary: "Displays a string.",
                 example: "Text(\"Hello\")",
                 arguments: [ArgumentSpec(nil, "The text, which may interpolate @State values")],
                 children: .none, minArguments: 1),
        ViewSpec(name: "Image", category: .content, summary: "Displays an image from the project or a system symbol.",
                 example: "Image(\"logo\")",
                 arguments: [ArgumentSpec(nil, "Image name"), ArgumentSpec("systemName", "Symbol name")],
                 children: .none, minArguments: 1),
        ViewSpec(name: "Button", category: .content, summary: "A control that runs an action when clicked.",
                 example: "Button(\"Add\") { count += 1 }",
                 arguments: [ArgumentSpec(nil, "Title"), ArgumentSpec("action", "Closure that changes @State")],
                 children: .optional, minArguments: 0),
        ViewSpec(name: "Link", category: .content, summary: "A link to a URL.",
                 example: "Link(\"Docs\", destination: \"https://example.com\")",
                 arguments: [ArgumentSpec(nil, "Title"), ArgumentSpec("destination", "URL string")],
                 children: .optional, minArguments: 1),
    ]

    public static let modifiers: [ModifierSpec] = [
        ModifierSpec(name: "padding", summary: "Adds space around the view.", example: ".padding(16)",
                     arguments: [ArgumentSpec(nil, "Edges, e.g. .horizontal"), ArgumentSpec(nil, "Length")],
                     minArguments: 0),
        ModifierSpec(name: "font", summary: "Sets the font.", example: ".font(.title)",
                     arguments: [ArgumentSpec(nil, "A font, e.g. .title or .system(size: 20)")], minArguments: 1),
        ModifierSpec(name: "foregroundColor", summary: "Sets the text and symbol color.",
                     example: ".foregroundColor(.blue)",
                     arguments: [ArgumentSpec(nil, "A color or a gradient")], minArguments: 1),
        ModifierSpec(name: "foregroundStyle", summary: "Sets the text and symbol color or gradient.",
                     example: ".foregroundStyle(LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing))",
                     arguments: [ArgumentSpec(nil, "A color or a gradient")], minArguments: 1),
        ModifierSpec(name: "background", summary: "Sets a background color or gradient.", example: ".background(Color.gray)",
                     arguments: [ArgumentSpec(nil, "A color or a gradient"), ArgumentSpec("alignment", "Alignment")],
                     minArguments: 1),
        ModifierSpec(name: "frame", summary: "Sets the size of the view.", example: ".frame(width: 200, height: 100)",
                     arguments: ["width", "height", "minWidth", "idealWidth", "maxWidth",
                                 "minHeight", "idealHeight", "maxHeight", "alignment"].map { ArgumentSpec($0, "") },
                     minArguments: 1),
        ModifierSpec(name: "cornerRadius", summary: "Rounds the corners.", example: ".cornerRadius(8)",
                     arguments: [ArgumentSpec(nil, "Radius")], minArguments: 1),
    ]

    public static func view(named name: String) -> ViewSpec? { views.first { $0.name == name } }
    public static func modifier(named name: String) -> ModifierSpec? { modifiers.first { $0.name == name } }
}
