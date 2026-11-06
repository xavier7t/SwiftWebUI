# SwiftWebUI: MVP1 Implementation Plan

SwiftWebUI is a macOS tool for web developers. They write SwiftUI-style code and see it rendered as a web page right away.

## MVP1 goal

A developer can create a project, edit SwiftUI-style files, watch the preview update as they type, and export the result as a static website.

## Key decisions

- **Interpret, don't compile.** The app parses code with SwiftSyntax, converts it to a view tree, renders that tree to HTML/CSS, and displays it in a `WKWebView`. Compiling Swift to WebAssembly is left out because it is likely to take seconds per change and would require users to install a toolchain and SDK.
- **Keep the renderer replaceable.** The view tree is the boundary between parsing and output, so a compiled backend could be added later without rewriting the app.
- **Support a defined subset of Swift.** Anything outside the subset produces a clear, line-specific error. It is never silently ignored.
- **Tooling.** Xcode 27.1 and Swift 6.4, with a native macOS app built in SwiftUI and AppKit where needed.

## Scope

### Supported in MVP1

- **Layout views:** `VStack`, `HStack`, `ZStack`, `Spacer`, `List`, `ForEach`
- **Content views:** `Text`, `Image`, `Button`, `Link`
- **Modifiers:** padding, font, foreground color, background, frame, corner radius
- **Composition:** custom `View` structs, including across files in a project
- **State:** simple `@State` values with `Button` actions that change them

### Not in MVP1

Multiple pages and routing, packages, deployment, Git integration, AI features, autocomplete, and arbitrary Swift logic.

## Phases

| # | Phase | Result |
|---|---|---|
| 1 | App shell and layout | Three-pane window with placeholders |
| 2 | Project model and file sidebar | Real project files can be managed |
| 3 | Code editor | Files can be edited and saved |
| 4 | Parser and view tree | Code becomes a tested view tree |
| 5 | Renderer and live preview | Typing updates the preview |
| 6 | Onboarding | Projects can be created and reopened |
| 7 | Export and MVP polish | A site can be exported |

---

## Phase 1: App shell and layout

Create the app and its main window so that later phases have a place to plug in. Nothing here depends on real project data.

### Implementation plan

1. Create a macOS SwiftUI app project named SwiftWebUI, with the app sandbox enabled.
2. Create a local Swift package for core logic, separate from the app target, so parsing and rendering can be tested without the UI.
3. Build the main window with three resizable panes: sidebar, editor, and preview.
4. Add placeholder content to each pane.
5. Add a toolbar with sidebar and preview visibility toggles.
6. Set minimum pane widths, and keep pane sizes between launches.

### AI automatic verification

- `xcodebuild build` for the app scheme succeeds.
- `swift test` passes in the core package.
- The core package does not import SwiftUI or AppKit.
- The sandbox entitlement is present in the built app.

### Human verification

- The panes resize smoothly and the layout feels like a native Mac app.
- The toggles behave as expected, and pane sizes are restored after relaunch.

---

## Phase 2: Project model and file sidebar

Define what a project is on disk and show it in the sidebar. The editor needs real files to open, so this comes before Phase 3.

### Implementation plan

1. Define the project format: a normal folder containing a small manifest file and a sources folder, with a defined entry view.
2. Implement project loading and creation in the core package.
3. Implement file operations: create, rename, delete (moving items to the Trash), and move.
4. Build the sidebar as a tree of files and folders, with file selection.
5. Add a context menu and keyboard shortcuts for the file operations.
6. Watch the project folder so that outside changes appear in the sidebar.
7. Handle invalid names, name collisions, and missing manifests with clear messages.

### AI automatic verification

- Unit tests cover project load and creation, plus every file operation, against temporary folders.
- Unit tests cover invalid names, name collisions, and missing manifests.
- A test confirms that an outside file change triggers a refresh.
- `xcodebuild build` succeeds.

### Human verification

- Sidebar interactions match Finder and Xcode conventions.
- Files added or removed in Finder appear in the sidebar promptly.

---

## Phase 3: Code editor

Build the editor and test it on its own before any preview exists.

### Implementation plan

1. Wrap `NSTextView` for use in the SwiftUI layout, using a monospaced font.
2. Open the file selected in the sidebar, keeping undo history per open file.
3. Add line numbers.
4. Add Swift syntax highlighting using SwiftSyntax, in both light and dark mode.
5. Add automatic indentation and bracket handling.
6. Autosave after a short pause and when switching files.
7. Detect outside changes to an open file, and reload it, or ask the user if there are unsaved edits.
8. Expose the current text as a stream of changes for Phase 5.

### AI automatic verification

- Unit tests cover mapping syntax tokens to highlight categories.
- Unit tests cover autosave timing and outside-change handling.
- A performance test highlights a 2,000-line file within one frame budget for incremental edits (about 16 ms).
- `xcodebuild build` succeeds.

### Human verification

- Typing feels immediate, including in a large file.
- Highlighting looks good in both light and dark mode.
- Undo, selection, and copy and paste behave as they do in a native Mac editor.

---

## Phase 4: Parser and view tree

Convert source code into a view tree. This is the riskiest part of the MVP, and it needs no UI, so it can be fully covered by unit tests.

### Implementation plan

1. Define the view tree types: node kind, arguments, modifiers, children, and source location.
2. Write down the supported views and modifiers as a single registry, which later phases also use.
3. Use SwiftSyntax to find `View` structs and their `body` in a file.
4. Convert view initializers, trailing closures, and modifier chains into tree nodes.
5. Resolve custom `View` structs across project files, and detect circular references.
6. Support literal values, stored properties, and `@State` declarations, including simple `Button` actions.
7. Support `ForEach` over literal arrays and ranges.
8. Report unsupported syntax, unknown views, and unknown modifiers as errors with line and column numbers.
9. Keep valid parts of the tree when part of a file has an error, where possible.

### AI automatic verification

- Each supported view and modifier has a fixture test comparing source to the expected tree.
- Each error type has a test that checks the message and location.
- Tests cover multi-file resolution and circular references.
- Incomplete code, as occurs mid-typing, never causes a crash, confirmed by a test that parses every prefix of the sample fixtures.
- A performance test parses a 500-line project in under 50 ms.

### Human verification

- Error messages are understandable and suggest what to do next.
- The supported subset is enough to build a realistic landing page.

---

## Phase 5: Renderer and live preview

Generate HTML/CSS from the view tree and connect the editor to the preview. This is where the product's core promise comes together.

### Implementation plan

1. Map each view to semantic HTML and CSS, with stacks and `Spacer` using flexbox and `ZStack` using grid.
2. Map each modifier to CSS, applying modifiers in order, as SwiftUI does.
3. Generate a small JavaScript runtime that handles `@State` and `Button` actions.
4. Display the result in a `WKWebView`, with network access limited to what the page needs.
5. Connect editor changes to parse and render with a very short debounce, off the main thread, discarding outdated results.
6. Update the existing page in place where possible, to avoid flicker and keep scroll position.
7. Keep the last good render on screen when the code has errors.
8. Show errors inline in the editor and in a compact list that jumps to the line when clicked.

### AI automatic verification

- Snapshot tests compare generated HTML/CSS for each view and modifier.
- A `WKWebView` test checks computed layout and styles for key fixtures.
- A test clicks a `Button` in the rendered page and confirms the `@State` update.
- A test confirms outdated results are discarded and the last good render is kept on error.
- A performance test confirms a keystroke reaches the updated preview in under 150 ms on a 500-line project.

### Human verification

- The preview feels instant while typing, without flicker or lost scroll position.
- Rendered output looks reasonably close to what a SwiftUI developer expects.
- Rendered output looks correct in Safari, Chrome, and Firefox.

---

## Phase 6: Onboarding

Add the entry point to the app. It depends on the project model, and because it hasn't been designed yet, this phase builds a simple functional version that a later design can replace.

### Implementation plan

1. Create a welcome window with a new project button and a recent projects list.
2. Build the new project flow: name, location, and creation from a default template that previews immediately.
3. Add an open existing project action.
4. Store recent projects with security-scoped bookmarks so they can be reopened in the sandbox.
5. Show missing recent projects clearly, with the option to remove them from the list.
6. Show the welcome window at launch and when the last project window closes.
7. Support multiple project windows, and add File menu commands for new, open, and recent projects.

### AI automatic verification

- Unit tests cover adding, ordering, limiting, and removing recent projects.
- A test covers handling of missing projects and stale bookmarks.
- A test confirms the default template parses and renders with no errors.
- A UI test creates a project and reaches the main window.

### Human verification

- A new user can go from launch to a working preview without help.
- Recent projects reopen after relaunching the sandboxed app.
- Design review: the placeholder onboarding is acceptable for MVP1.

---

## Phase 7: Export and MVP polish

Complete the path from new project to usable output, and fix the rough edges that would block a first release.

### Implementation plan

1. Add an export command that writes a static site (HTML, CSS, JavaScript, and assets) to a chosen folder.
2. Copy referenced images into the export, and report any that are missing.
3. Add two or three starter templates to the new project flow.
4. Add a preview width toggle for mobile, tablet, and desktop sizes.
5. Add a short in-app reference listing supported views and modifiers, generated from the registry.
6. Review empty and failure states: no file selected, empty project, unreadable file, and failed export.
7. Set up signing and notarization for distribution outside the Mac App Store.

### AI automatic verification

- A test exports each template and confirms the expected files exist and all asset references resolve.
- A test loads each export in a `WKWebView` with no console errors.
- A test confirms the in-app reference matches the registry.
- A full end-to-end UI test covers create, edit, preview, and export.
- A release build succeeds, and `spctl` accepts the notarized app.

### Human verification

- An exported site works when hosted on a real static host.
- A notarized build installs and opens on a separate Mac.
- A few web developers try the app, and their feedback decides the priorities for MVP2.

---

## Main risks

| Risk | Mitigation |
|---|---|
| Users expect full Swift support | Clear errors and an in-app list of what's supported |
| Mid-typing code often fails to parse | Keep the last good render, and test every prefix of the fixtures |
| SwiftUI layout doesn't map exactly to CSS | Aim for "close and predictable", and document known differences |
| `@State` grows into a full language interpreter | Limit MVP1 to simple values and actions |
| The name may conflict with an existing open-source project | Check before any public announcement |

## MVP1 is done when

- All phase verification checks pass.
- A developer can go from launch to an exported landing page without help.
- Preview updates feel instant on a typical project (target: under 150 ms).
