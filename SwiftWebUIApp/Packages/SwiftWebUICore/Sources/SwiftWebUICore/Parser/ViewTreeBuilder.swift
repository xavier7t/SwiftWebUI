import Foundation
import SwiftParser
import SwiftSyntax

public enum ViewTreeBuilder {
    /// Builds the tree for `entryView` from the given files. Problems become diagnostics; valid parts are kept.
    public static func build(files: [SourceFile], entryView: String = ProjectManifest.defaultEntryView) -> ParseResult {
        Builder(files: files).run(entry: entryView)
    }

    /// Convenience for a single source string. Uses `entryView`, or the first `View` struct when `nil`.
    public static func build(source: String, entryView: String? = nil) -> ParseResult {
        let file = SourceFile(path: "ContentView.swift", text: source)
        let entry = entryView ?? Builder(files: [file]).firstViewName() ?? ProjectManifest.defaultEntryView
        return build(files: [file], entryView: entry)
    }
}

public enum ProjectParser {
    /// Reads every `.swift` file under the project's sources folder and builds the entry view's tree.
    /// `overrides` maps a path relative to the sources folder to text that replaces (or adds) that file,
    /// so unsaved editor contents can be used without writing them to disk.
    public static func parse(project: Project, fileManager: FileManager = .default,
                             overrides: [String: String] = [:]) -> ParseResult {
        var texts: [String: String] = [:]
        var diagnostics: [Diagnostic] = []
        let base = project.sourcesURL.standardizedFileURL.path
        let urls = (fileManager.enumerator(at: project.sourcesURL, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
        for url in urls.filter({ $0.pathExtension == "swift" }) {
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            if overrides[relative] != nil { continue }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                texts[relative] = text
            } else {
                diagnostics.append(Diagnostic(code: .unreadableFile, message: "Could not read “\(relative)”.",
                                              suggestion: "Check that the file is saved as UTF-8 text.",
                                              location: CodeLocation(file: relative, line: 1, column: 1)))
            }
        }
        for (path, text) in overrides { texts[path] = text }
        let files = texts.keys.sorted().map { SourceFile(path: $0, text: texts[$0]!) }
        let result = ViewTreeBuilder.build(files: files, entryView: project.manifest.entryView)
        return ParseResult(tree: result.tree, diagnostics: (diagnostics + result.diagnostics).sorted { $0.location < $1.location })
    }
}

// MARK: - Implementation

private final class FileContext {
    let path: String
    let tree: SourceFileSyntax
    let converter: SourceLocationConverter
    let lines: [String]

    init(path: String, text: String) {
        self.path = path
        tree = Parser.parse(source: text)
        converter = SourceLocationConverter(fileName: path, tree: tree)
        lines = text.utf8.split(separator: 10, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
    }

    func location(_ position: AbsolutePosition) -> CodeLocation {
        let loc = converter.location(for: position)
        var column = loc.column
        if loc.line >= 1, loc.line <= lines.count {
            let line = lines[loc.line - 1]
            let utf8 = line.utf8
            let offset = max(0, min(column - 1, utf8.count))
            column = line.distance(from: line.startIndex, to: utf8.index(utf8.startIndex, offsetBy: offset)) + 1
        }
        return CodeLocation(file: path, line: loc.line, column: column)
    }

    func location(of node: some SyntaxProtocol) -> CodeLocation {
        location(node.positionAfterSkippingLeadingTrivia)
    }
}

private struct Property {
    let name: String
    let isState: Bool
    let isLet: Bool
    let defaultValue: ExprSyntax?
    let location: CodeLocation

    /// Whether the memberwise initializer takes this property as an argument.
    var isParameter: Bool { !isState && !(isLet && defaultValue != nil) }
}

private struct StructInfo {
    let name: String
    let file: FileContext
    let properties: [Property]
    let body: CodeBlockItemListSyntax?
    let location: CodeLocation
}

private struct Scope {
    var values: [String: Value] = [:]
}

private struct CallArgument {
    let label: String?
    let expr: ExprSyntax
}

private final class Builder {
    let maxDepth = 64
    let maxForEach = 500

    var files: [FileContext] = []
    var structs: [String: StructInfo] = [:]
    var structOrder: [String] = []
    var diagnostics: [Diagnostic] = []
    var states: [StateVariable] = []
    var instanceCounts: [String: Int] = [:]
    var visited: Set<String> = []
    var current: FileContext!
    var reportMissing = true

    init(files sources: [SourceFile]) {
        for source in sources {
            let ctx = FileContext(path: source.path, text: source.text)
            files.append(ctx)
            current = ctx
            reportSyntaxErrors(ctx)
            collectStructs(ctx)
        }
    }

    func firstViewName() -> String? { structOrder.first }

    // MARK: Entry

    func run(entry: String) -> ParseResult {
        guard let info = structs[entry] else {
            let known = structOrder
            let hint = Suggest.closest(to: entry, in: known).map { "Did you mean “\($0)”?" }
                ?? "Add a struct named “\(entry)” that conforms to View."
            let loc = CodeLocation(file: files.first?.path ?? "", line: 1, column: 1)
            add(.missingEntryView, "The entry view “\(entry)” was not found.", hint, loc)
            return ParseResult(tree: nil, diagnostics: finish())
        }
        let root = instantiate(info, arguments: [], callLocation: info.location, stack: [], depth: 0)
        let tree = root.map { ViewTree(root: $0, states: states) }

        // Check views the entry doesn't reach, so errors show up while the user is still writing them.
        let savedStates = states, savedCounts = instanceCounts
        reportMissing = false
        for name in structOrder where !visited.contains(name) {
            if let other = structs[name] {
                _ = instantiate(other, arguments: [], callLocation: other.location, stack: [], depth: 0)
            }
        }
        states = savedStates
        instanceCounts = savedCounts
        return ParseResult(tree: tree, diagnostics: finish())
    }

    func finish() -> [Diagnostic] {
        var seen = Set<Diagnostic>()
        return diagnostics.filter { seen.insert($0).inserted }.sorted { $0.location < $1.location }
    }

    // MARK: Diagnostics

    func add(_ code: DiagnosticCode, _ message: String, _ suggestion: String? = nil, _ location: CodeLocation,
             severity: Diagnostic.Severity = .error) {
        diagnostics.append(Diagnostic(severity: severity, code: code, message: message,
                                      suggestion: suggestion, location: location))
    }

    func loc(_ node: some SyntaxProtocol) -> CodeLocation { current.location(of: node) }

    func snippet(_ node: some SyntaxProtocol) -> String {
        let text = node.trimmedDescription.replacingOccurrences(of: "\n", with: " ")
        return text.count > 40 ? String(text.prefix(40)) + "…" : text
    }

    func reportSyntaxErrors(_ ctx: FileContext) {
        guard ctx.tree.hasError else { return }
        var lines = Set<Int>()
        for token in ctx.tree.tokens(viewMode: .all) {
            let message: String
            if token.presence == .missing {
                message = token.text.isEmpty ? "Syntax error: something is missing here." : "Syntax error: expected “\(token.text)”."
            } else if token.parent?.is(UnexpectedNodesSyntax.self) == true {
                message = "Syntax error: unexpected “\(token.text)”."
            } else { continue }
            let location = ctx.location(token.presence == .missing ? token.position : token.positionAfterSkippingLeadingTrivia)
            guard lines.insert(location.line).inserted, lines.count <= 5 else { continue }
            add(.syntaxError, message, "Check the code near this line for a missing bracket, quote or keyword.", location)
        }
    }

    // MARK: Declarations

    func collectStructs(_ ctx: FileContext) {
        for item in ctx.tree.statements {
            guard let decl = item.item.as(StructDeclSyntax.self), conformsToView(decl) else { continue }
            let name = decl.name.text
            if structs[name] != nil {
                add(.duplicateView, "“\(name)” is defined more than once.", "Rename or remove one of the definitions.", loc(decl.name))
                continue
            }
            structs[name] = makeInfo(decl, ctx)
            structOrder.append(name)
        }
    }

    func conformsToView(_ decl: StructDeclSyntax) -> Bool {
        decl.inheritanceClause?.inheritedTypes.contains {
            let t = $0.type.trimmedDescription
            return t == "View" || t == "SwiftUI.View"
        } ?? false
    }

    func makeInfo(_ decl: StructDeclSyntax, _ ctx: FileContext) -> StructInfo {
        var properties: [Property] = []
        var body: CodeBlockItemListSyntax?
        for member in decl.memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                if variable.modifiers.contains(where: { $0.name.text == "static" }) { continue }
                var isState = false
                for case .attribute(let attr) in variable.attributes {
                    let name = attr.attributeName.trimmedDescription
                    if name == "State" { isState = true } else {
                        add(.unsupportedSyntax, "@\(name) isn’t supported yet.",
                            "Only @State is available in this version. Use a plain property instead.", ctx.location(of: attr))
                    }
                }
                for binding in variable.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                        add(.unsupportedSyntax, "This kind of property declaration isn’t supported.",
                            "Declare one property per line, like “let title = \"Hello\"”.", ctx.location(of: binding))
                        continue
                    }
                    if let block = binding.accessorBlock {
                        if name == "body" { body = bodyStatements(block) } else {
                            add(.unsupportedSyntax, "Computed property “\(name)” isn’t supported.",
                                "Use a stored property with a literal value, or move the content into its own View struct.",
                                ctx.location(of: binding))
                        }
                        continue
                    }
                    properties.append(Property(name: name, isState: isState, isLet: variable.bindingSpecifier.text == "let",
                                               defaultValue: binding.initializer?.value, location: ctx.location(of: binding)))
                }
            } else {
                add(.unsupportedSyntax, "This declaration is ignored.",
                    "Only properties and “body” are supported inside a View struct.", ctx.location(of: member.decl), severity: .warning)
            }
        }
        return StructInfo(name: decl.name.text, file: ctx, properties: properties, body: body, location: ctx.location(of: decl.name))
    }

    func bodyStatements(_ block: AccessorBlockSyntax) -> CodeBlockItemListSyntax? {
        switch block.accessors {
        case .getter(let statements): return statements
        case .accessors(let list): return list.first { $0.accessorSpecifier.text == "get" }?.body?.statements
        }
    }

    // MARK: Instantiating custom views

    func instantiate(_ info: StructInfo, arguments: [(label: String?, value: Value, location: CodeLocation)],
                     callLocation: CodeLocation, stack: [String], depth: Int) -> ViewNode? {
        visited.insert(info.name)
        if let start = stack.firstIndex(of: info.name) {
            let cycle = (stack[start...] + [info.name]).joined(separator: " → ")
            add(.circularReference, "“\(info.name)” contains itself (\(cycle)).",
                "A view can’t include itself, directly or through other views. Remove one of the references.", callLocation)
            return nil
        }
        let saved = current
        current = info.file
        defer { current = saved }

        let count = (instanceCounts[info.name] ?? 0) + 1
        instanceCounts[info.name] = count
        let prefix = count == 1 ? info.name : "\(info.name)#\(count)"

        // Validate call arguments against the memberwise initializer.
        let params = info.properties.filter(\.isParameter)
        var supplied: [String: Value] = [:]
        for arg in arguments {
            guard let label = arg.label else {
                add(.invalidArgument, "Arguments to “\(info.name)” need a label.",
                    "Write it like \(info.name)(\(params.first?.name ?? "name"): …).", arg.location)
                continue
            }
            if params.contains(where: { $0.name == label }) { supplied[label] = arg.value } else {
                let hint = Suggest.closest(to: label, in: params.map(\.name)).map { "Did you mean “\($0)”?" }
                    ?? (params.isEmpty ? "“\(info.name)” has no properties to set." : "Available: \(params.map(\.name).joined(separator: ", ")).")
                add(.unknownArgument, "“\(info.name)” has no property “\(label)”.", hint, arg.location)
            }
        }

        var scope = Scope()
        for prop in info.properties {
            if prop.isState {
                guard let expr = prop.defaultValue, let initial = eval(expr, scope) else {
                    if prop.defaultValue == nil {
                        add(.invalidState, "@State variable “\(prop.name)” needs an initial value.",
                            "Write it like “@State var \(prop.name) = 0”.", prop.location)
                    }
                    continue
                }
                let id = "\(prefix).\(prop.name)"
                states.append(StateVariable(id: id, name: prop.name, initial: initial, location: prop.location))
                scope.values[prop.name] = .state(id)
            } else if let value = supplied[prop.name] {
                scope.values[prop.name] = value
            } else if let expr = prop.defaultValue {
                if let v = eval(expr, scope) { scope.values[prop.name] = v }
            } else {
                if reportMissing {
                    add(.missingArgument, "“\(info.name)” needs a value for “\(prop.name)”.",
                        "Pass it when you use the view: \(info.name)(\(prop.name): …).", callLocation)
                }
                scope.values[prop.name] = .string("")
            }
        }

        guard let body = info.body else {
            add(.unsupportedSyntax, "“\(info.name)” has no body.", "Add “var body: some View { … }”.", info.location)
            return ViewNode(kind: info.name, isCustom: true, location: callLocation)
        }
        let nodes = views(in: body, scope, stack + [info.name], depth + 1)
        var node = ViewNode(kind: info.name, isCustom: true, location: callLocation)
        node.children = [group(nodes, at: info.location)].compactMap { $0 }
        return node
    }

    /// One view stays as is; several are wrapped in a `Group`; none gives `nil`.
    func group(_ nodes: [ViewNode], at location: CodeLocation) -> ViewNode? {
        switch nodes.count {
        case 0: return nil
        case 1: return nodes[0]
        default: return ViewNode(kind: "Group", children: nodes, location: nodes[0].location)
        }
    }

    // MARK: Views

    func views(in statements: CodeBlockItemListSyntax, _ scope: Scope, _ stack: [String], _ depth: Int) -> [ViewNode] {
        var result: [ViewNode] = []
        for item in statements {
            switch item.item {
            case .expr(let expr):
                if let node = view(from: expr, scope, stack, depth) { result.append(node) }
            case .stmt(let stmt):
                if let ret = stmt.as(ReturnStmtSyntax.self), let expr = ret.expression {
                    if let node = view(from: expr, scope, stack, depth) { result.append(node) }
                } else if let wrapped = stmt.as(ExpressionStmtSyntax.self) {
                    if let node = view(from: wrapped.expression, scope, stack, depth) { result.append(node) }
                } else {
                    unsupported(stmt, "Statements like this aren’t supported in a view body.")
                }
            case .decl(let decl):
                unsupported(decl, "Local declarations aren’t supported in a view body.",
                            "Move it to a property of the struct.")
            }
        }
        return result
    }

    func unsupported(_ node: some SyntaxProtocol, _ message: String, _ hint: String = "Use the supported views and modifiers listed in the reference.") {
        add(.unsupportedSyntax, message, hint, loc(node))
    }

    func view(from expr: ExprSyntax, _ scope: Scope, _ stack: [String], _ depth: Int) -> ViewNode? {
        guard depth < maxDepth else {
            add(.unsupportedSyntax, "This view is nested too deeply.", "Split it into smaller View structs.", loc(expr))
            return nil
        }
        if expr.is(IfExprSyntax.self) || expr.is(SwitchExprSyntax.self) {
            unsupported(expr, "“if” and “switch” aren’t supported in views yet.",
                        "Show the content unconditionally, or split it into separate View structs.")
            return nil
        }
        guard let call = expr.as(FunctionCallExprSyntax.self) else {
            unsupported(expr, "“\(snippet(expr))” isn’t a view.", "Use a view such as Text(\"…\") or VStack { … }.")
            return nil
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            guard let base = member.base else {
                unsupported(call, "“\(snippet(call))” isn’t a view.", "Use a view such as Text(\"…\") or VStack { … }.")
                return nil
            }
            let modifier = modifier(named: member.declName.baseName.text, call: call, at: member.declName, scope)
            guard var node = view(from: base, scope, stack, depth + 1) else { return nil }
            if let modifier { node.modifiers.append(modifier) }
            return node
        }
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return construct(ref.baseName.text, call, scope, stack, depth)
        }
        unsupported(call, "“\(snippet(call))” isn’t a view.")
        return nil
    }

    func construct(_ name: String, _ call: FunctionCallExprSyntax, _ scope: Scope, _ stack: [String], _ depth: Int) -> ViewNode? {
        let location = loc(call.calledExpression)
        if let spec = Registry.view(named: name) {
            return builtIn(spec, call, scope, stack, depth, location)
        }
        guard let info = structs[name] else {
            let candidates = Registry.views.map(\.name) + structOrder
            let hint = Suggest.closest(to: name, in: candidates).map { "Did you mean “\($0)”?" }
                ?? "Check the reference for supported views, or define “struct \(name): View” in your project."
            add(.unknownView, "Unknown view “\(name)”.", hint, location)
            return nil
        }
        if call.trailingClosure != nil {
            unsupported(call, "“\(name)” can’t take a content closure.", "Pass values as labeled arguments instead.")
        }
        var args: [(label: String?, value: Value, location: CodeLocation)] = []
        for arg in call.arguments {
            if let v = eval(arg.expression, scope) { args.append((arg.label?.text, v, loc(arg))) }
        }
        return instantiate(info, arguments: args, callLocation: location, stack: stack, depth: depth)
    }

    func builtIn(_ spec: ViewSpec, _ call: FunctionCallExprSyntax, _ scope: Scope, _ stack: [String],
                 _ depth: Int, _ location: CodeLocation) -> ViewNode? {
        var node = ViewNode(kind: spec.name, location: location)
        let closureLabels: Set<String> = ["action"]
        let skip: Set<String> = spec.name == "ForEach" ? ["id"] : closureLabels

        let args = Array(call.arguments)
        guard validate(args, spec.arguments, owner: spec.name, minimum: spec.minArguments, example: spec.example, skip: skip) else {
            if spec.children != .none, let closure = call.trailingClosure { _ = childViews(closure, scope, stack, depth) }
            return node
        }
        let valueArgs = args.filter { $0.label.map { !skip.contains($0.text) } ?? true }
        node.arguments = valueArgs.compactMap { a in eval(a.expression, scope).map { Argument(label: a.label?.text, value: $0) } }

        switch spec.name {
        case "ForEach":
            return forEach(node, call, args, scope, stack, depth)
        case "Button":
            return button(node, call, args, scope, stack, depth)
        default:
            break
        }

        if let closure = call.trailingClosure {
            if spec.children == .none {
                unsupported(closure, "“\(spec.name)” doesn’t take content.", "Remove the braces.")
            } else {
                node.children = childViews(closure, scope, stack, depth)
            }
        } else if spec.children == .required {
            add(.missingArgument, "“\(spec.name)” needs content.", "Add a closure: \(spec.example).", location)
        }
        if spec.name == "Link" { checkLink(node, call) }
        return node
    }

    func checkLink(_ node: ViewNode, _ call: FunctionCallExprSyntax) {
        if !node.arguments.contains(where: { $0.label == "destination" }) {
            add(.missingArgument, "“Link” needs a destination.",
                "Add one: Link(\"Docs\", destination: \"https://example.com\").", loc(call.calledExpression))
        }
    }

    func childViews(_ closure: ClosureExprSyntax, _ scope: Scope, _ stack: [String], _ depth: Int) -> [ViewNode] {
        views(in: closure.statements, scope, stack, depth + 1)
    }

    // MARK: ForEach

    func forEach(_ node: ViewNode, _ call: FunctionCallExprSyntax, _ args: [LabeledExprSyntax],
                 _ scope: Scope, _ stack: [String], _ depth: Int) -> ViewNode? {
        var node = node
        for arg in args where arg.label?.text == "id" && arg.expression.trimmedDescription != "\\.self" {
            unsupported(arg.expression, "Only “id: \\.self” is supported in ForEach.", "Use ForEach(items, id: \\.self) or a range.")
        }
        guard let dataArg = args.first(where: { $0.label == nil }) else { return node }
        guard case .array(let items)? = node.arguments.first?.value else {
            if node.arguments.first != nil {
                unsupported(dataArg.expression, "ForEach only supports literal arrays and ranges.",
                            "Use something like ForEach([\"A\", \"B\"], id: \\.self) or ForEach(0..<3).")
            }
            node.arguments = []
            return node
        }
        node.arguments = []
        guard let closure = call.trailingClosure else {
            add(.missingArgument, "“ForEach” needs content.", "Add a closure: ForEach(0..<3) { i in … }.", node.location)
            return node
        }
        guard items.count <= maxForEach else {
            unsupported(dataArg.expression, "ForEach repeats at most \(maxForEach) items.", "Use a shorter array or range.")
            return node
        }
        let name = closureParameterName(closure) ?? "$0"
        for item in items {
            var inner = scope
            inner.values[name] = item
            node.children += childViews(closure, inner, stack, depth)
        }
        return node
    }

    func closureParameterName(_ closure: ClosureExprSyntax) -> String? {
        switch closure.signature?.parameterClause {
        case .simpleInput(let list)?: return list.first?.name.text
        case .parameterClause(let clause)?:
            guard let p = clause.parameters.first else { return nil }
            return (p.secondName ?? p.firstName).text
        case nil: return nil
        }
    }

    // MARK: Button

    func button(_ node: ViewNode, _ call: FunctionCallExprSyntax, _ args: [LabeledExprSyntax],
                _ scope: Scope, _ stack: [String], _ depth: Int) -> ViewNode? {
        var node = node
        let hasTitle = args.contains { $0.label == nil }
        var actionClosure = args.first { $0.label?.text == "action" }?.expression.as(ClosureExprSyntax.self)
        var labelClosure: ClosureExprSyntax?
        if let action = args.first(where: { $0.label?.text == "action" }), actionClosure == nil {
            unsupported(action.expression, "Button actions must be written as a closure.", "Use Button(\"Add\") { count += 1 }.")
        }
        if let trailing = call.trailingClosure {
            if hasTitle || actionClosure != nil {
                if actionClosure == nil { actionClosure = trailing } else { labelClosure = trailing }
            } else {
                actionClosure = trailing
                labelClosure = call.additionalTrailingClosures.first { $0.label.text == "label" }?.closure
            }
        }
        if let label = labelClosure { node.children = childViews(label, scope, stack, depth) }
        if let closure = actionClosure { node.actions = actions(in: closure, scope) }
        else { add(.missingArgument, "“Button” needs an action.", "Add a closure: Button(\"Add\") { count += 1 }.", node.location) }
        if !hasTitle && labelClosure == nil {
            add(.missingArgument, "“Button” needs a title or a label.",
                "Write Button(\"Add\") { … } or add “label: { Text(\"Add\") }”.", node.location)
        }
        return node
    }

    func actions(in closure: ClosureExprSyntax, _ scope: Scope) -> [Action] {
        let hint = "Button actions support “x += 1”, “x -= 1”, “x = value” and “x.toggle()” on @State variables."
        var result: [Action] = []
        for item in closure.statements {
            guard case .expr(let expr) = item.item else {
                unsupported(item, "This statement isn’t supported in a Button action.", hint)
                continue
            }
            if let call = expr.as(FunctionCallExprSyntax.self), let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == "toggle", call.arguments.isEmpty, let base = member.base {
                if let id = stateID(base, scope) { result.append(.toggle(state: id)) }
                continue
            }
            guard let seq = expr.as(SequenceExprSyntax.self), seq.elements.count == 3 else {
                unsupported(expr, "“\(snippet(expr))” isn’t supported in a Button action.", hint)
                continue
            }
            let parts = Array(seq.elements)
            let op = parts[1].is(AssignmentExprSyntax.self) ? "=" : (parts[1].as(BinaryOperatorExprSyntax.self)?.operator.text ?? "")
            guard let id = stateID(parts[0], scope) else { continue }
            switch op {
            case "=":
                if let prefix = parts[2].as(PrefixOperatorExprSyntax.self), prefix.operator.text == "!",
                   stateID(prefix.expression, scope, report: false) == id {
                    result.append(.toggle(state: id))
                } else if let v = eval(parts[2], scope) {
                    result.append(.set(state: id, value: v))
                }
            case "+=", "-=":
                if case .number(let n)? = eval(parts[2], scope) {
                    result.append(.add(state: id, amount: op == "+=" ? n : -n))
                } else {
                    unsupported(parts[2], "“\(op)” needs a number.", "Write it like “count \(op) 1”.")
                }
            default:
                unsupported(expr, "“\(snippet(expr))” isn’t supported in a Button action.", hint)
            }
        }
        return result
    }

    func stateID(_ expr: ExprSyntax, _ scope: Scope, report: Bool = true) -> String? {
        var name: String?
        if let ref = expr.as(DeclReferenceExprSyntax.self) { name = ref.baseName.text }
        else if let m = expr.as(MemberAccessExprSyntax.self), m.base?.trimmedDescription == "self" { name = m.declName.baseName.text }
        guard let name else {
            if report { unsupported(expr, "“\(snippet(expr))” can’t be changed here.", "Only @State variables can be changed.") }
            return nil
        }
        if case .state(let id)? = scope.values[name] { return id }
        if report {
            let hint = scope.values[name] == nil ? "Declare it with “@State var \(name) = 0”." : "Only @State variables can be changed."
            add(.invalidState, "“\(name)” isn’t a @State variable.", hint, loc(expr))
        }
        return nil
    }

    // MARK: Modifiers

    func modifier(named name: String, call: FunctionCallExprSyntax, at nameNode: some SyntaxProtocol, _ scope: Scope) -> ModifierNode? {
        let location = loc(nameNode)
        guard let spec = Registry.modifier(named: name) else {
            let hint = Suggest.closest(to: name, in: Registry.modifiers.map(\.name)).map { "Did you mean “\($0)”?" }
                ?? "Supported modifiers: \(Registry.modifiers.map(\.name).joined(separator: ", "))."
            add(.unknownModifier, "Unknown modifier “\(name)”.", hint, location)
            return nil
        }
        if let closure = call.trailingClosure {
            unsupported(closure, "“.\(name)” can’t take a closure.", "Pass a value instead, like \(spec.example).")
            return nil
        }
        let args = Array(call.arguments)
        guard validate(args, spec.arguments, owner: ".\(name)", minimum: spec.minArguments, example: spec.example, skip: []) else { return nil }
        let values = args.compactMap { a in eval(a.expression, scope).map { Argument(label: a.label?.text, value: $0) } }
        guard values.count == args.count else { return nil }
        return ModifierNode(name: name, arguments: values, location: location)
    }

    /// Checks labels, positional count and the minimum number of arguments. Emits diagnostics.
    func validate(_ args: [LabeledExprSyntax], _ specs: [ArgumentSpec], owner: String, minimum: Int,
                  example: String, skip: Set<String>) -> Bool {
        var ok = true
        let maxPositional = specs.filter { $0.label == nil }.count
        let labels = specs.compactMap(\.label)
        var positional = 0
        for arg in args {
            if let label = arg.label?.text {
                if !labels.contains(label) {
                    let hint = Suggest.closest(to: label, in: labels).map { "Did you mean “\($0)”?" }
                        ?? (labels.isEmpty ? "“\(owner)” doesn’t take labeled arguments. Example: \(example)." : "Available: \(labels.joined(separator: ", ")).")
                    add(.unknownArgument, "“\(owner)” has no argument “\(label)”.", hint, loc(arg))
                    ok = false
                }
            } else {
                positional += 1
                if positional > maxPositional {
                    add(.invalidArgument, "Too many arguments for “\(owner)”.", "Example: \(example).", loc(arg))
                    ok = false
                }
            }
        }
        if args.count < minimum {
            add(.missingArgument, "“\(owner)” needs \(minimum == 1 ? "a value" : "more arguments").", "Example: \(example).",
                args.first.map { loc($0) } ?? loc(current.tree))
            ok = false
        }
        return ok
    }

    // MARK: Expressions

    func eval(_ expr: ExprSyntax, _ scope: Scope) -> Value? {
        if let s = expr.as(StringLiteralExprSyntax.self) { return evalString(s, scope) }
        if let i = expr.as(IntegerLiteralExprSyntax.self) {
            let text = i.literal.text.replacingOccurrences(of: "_", with: "")
            if let n = Int(text) ?? (text.hasPrefix("0x") ? Int(text.dropFirst(2), radix: 16) : nil) { return .number(Double(n)) }
            unsupported(expr, "“\(i.literal.text)” isn’t a supported number."); return nil
        }
        if let f = expr.as(FloatLiteralExprSyntax.self) {
            if let n = Double(f.literal.text.replacingOccurrences(of: "_", with: "")) { return .number(n) }
            unsupported(expr, "“\(f.literal.text)” isn’t a supported number."); return nil
        }
        if let b = expr.as(BooleanLiteralExprSyntax.self) { return .bool(b.literal.text == "true") }
        if let a = expr.as(ArrayExprSyntax.self) {
            var items: [Value] = []
            for element in a.elements { if let v = eval(element.expression, scope) { items.append(v) } }
            return .array(items)
        }
        if let t = expr.as(TupleExprSyntax.self), t.elements.count == 1, let only = t.elements.first, only.label == nil {
            return eval(only.expression, scope)
        }
        if let p = expr.as(PrefixOperatorExprSyntax.self), p.operator.text == "-" {
            if case .number(let n)? = eval(p.expression, scope) { return .number(-n) }
            unsupported(expr, "“\(snippet(expr))” isn’t a supported value."); return nil
        }
        if let seq = expr.as(SequenceExprSyntax.self) { return evalRange(seq, scope) }
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            let name = ref.baseName.text
            if let v = scope.values[name] { return v }
            let hint = Suggest.closest(to: name, in: Array(scope.values.keys)).map { "Did you mean “\($0)”?" }
                ?? "Declare it as a property of this struct, e.g. “let \(name) = …” or “@State var \(name) = …”."
            add(.unknownName, "Unknown name “\(name)”.", hint, loc(ref))
            return nil
        }
        if let m = expr.as(MemberAccessExprSyntax.self) { return evalMember(m, scope) }
        if let call = expr.as(FunctionCallExprSyntax.self) { return evalCall(call, scope) }
        unsupported(expr, "“\(snippet(expr))” isn’t supported here.",
                    "Use a literal value such as \"text\", 42, true, [1, 2, 3] or a color like .blue.")
        return nil
    }

    func evalString(_ literal: StringLiteralExprSyntax, _ scope: Scope) -> Value? {
        var parts: [TextPart] = []
        func append(_ s: String) {
            if case .literal(let last)? = parts.last { parts[parts.count - 1] = .literal(last + s) } else { parts.append(.literal(s)) }
        }
        for segment in literal.segments {
            switch segment {
            case .stringSegment(let s):
                append(literal.openingPounds == nil ? unescape(s.content.text) : s.content.text)
            case .expressionSegment(let e):
                guard let inner = e.expressions.first?.expression, let value = eval(inner, scope) else { return nil }
                switch value {
                case .state(let id): parts.append(.state(id))
                case .string(let s): append(s)
                case .number(let n): append(formatNumber(n))
                case .bool(let b): append(b ? "true" : "false")
                default:
                    unsupported(inner, "“\(snippet(inner))” can’t be shown in text.", "Interpolate a string, number, boolean or @State value.")
                    return nil
                }
            }
        }
        if parts.isEmpty { return .string("") }
        if parts.count == 1, case .literal(let s) = parts[0] { return .string(s) }
        return .interpolated(parts)
    }

    func unescape(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = "", it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let n = it.next() else { out.append(c); continue }
            switch n {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "0": out.append("\0")
            case "\"", "'", "\\": out.append(n)
            default: out.append("\\"); out.append(n)
            }
        }
        return out
    }

    func evalRange(_ seq: SequenceExprSyntax, _ scope: Scope) -> Value? {
        let parts = Array(seq.elements)
        guard parts.count == 3, let op = parts[1].as(BinaryOperatorExprSyntax.self)?.operator.text, op == "..<" || op == "..." else {
            unsupported(seq, "“\(snippet(seq))” isn’t supported here.", "Only ranges like 0..<3 or 1...5 are supported as expressions.")
            return nil
        }
        guard case .number(let lo)? = eval(parts[0], scope), case .number(let hi)? = eval(parts[2], scope),
              lo == lo.rounded(), hi == hi.rounded() else {
            unsupported(seq, "Ranges must use whole-number literals.", "Write it like 0..<3.")
            return nil
        }
        let upper = op == "..<" ? hi - 1 : hi
        guard upper - lo < Double(maxForEach) else {
            unsupported(seq, "This range is too long.", "Ranges can have at most \(maxForEach) items.")
            return nil
        }
        if upper < lo { return .array([]) }
        return .array(stride(from: lo, through: upper, by: 1).map { .number($0) })
    }

    func evalMember(_ m: MemberAccessExprSyntax, _ scope: Scope) -> Value? {
        let name = m.declName.baseName.text
        guard let base = m.base else { return .member(base: nil, name: name, arguments: []) }
        if let ref = base.as(DeclReferenceExprSyntax.self) {
            if ref.baseName.text == "self" { return scope.values[name] ?? unknown(name, m) }
            if scope.values[ref.baseName.text] == nil, ref.baseName.text.first?.isUppercase == true {
                return .member(base: ref.baseName.text, name: name, arguments: [])
            }
        }
        unsupported(m, "“\(snippet(m))” isn’t supported here.", "Use a literal value or a member like .blue or Color.blue.")
        return nil
    }

    func unknown(_ name: String, _ node: some SyntaxProtocol) -> Value? {
        add(.unknownName, "Unknown name “\(name)”.", "Declare it as a property of this struct.", loc(node))
        return nil
    }

    func evalCall(_ call: FunctionCallExprSyntax, _ scope: Scope) -> Value? {
        if call.trailingClosure != nil {
            unsupported(call, "Closures aren’t supported in values."); return nil
        }
        func arguments() -> [Argument]? {
            var out: [Argument] = []
            for a in call.arguments {
                guard let v = eval(a.expression, scope) else { return nil }
                out.append(Argument(label: a.label?.text, value: v))
            }
            return out
        }
        if let m = call.calledExpression.as(MemberAccessExprSyntax.self) {
            let name = m.declName.baseName.text
            guard let base = m.base else {
                return arguments().map { .member(base: nil, name: name, arguments: $0) }
            }
            if let ref = base.as(DeclReferenceExprSyntax.self), scope.values[ref.baseName.text] == nil,
               ref.baseName.text.first?.isUppercase == true {
                return arguments().map { .member(base: ref.baseName.text, name: name, arguments: $0) }
            }
            if let baseValue = eval(base, scope), case .member = baseValue {
                return arguments().map { .method(baseValue, name: name, arguments: $0) }
            } else if let baseValue = eval(base, scope), case .method = baseValue {
                return arguments().map { .method(baseValue, name: name, arguments: $0) }
            }
        }
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self), ref.baseName.text == "Color" {
            return arguments().map { .member(base: "Color", name: "init", arguments: $0) }
        }
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self),
           Gradients.kinds.contains(ref.baseName.text) || Gradients.helperTypes.contains(ref.baseName.text) {
            return arguments().map { .member(base: ref.baseName.text, name: "init", arguments: $0) }
        }
        unsupported(call, "“\(snippet(call))” isn’t supported here.",
                    "Use a literal value, a color such as .blue or Color(red: 0.1, green: 0.2, blue: 0.3), or a gradient such as LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom).")
        return nil
    }
}
