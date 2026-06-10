import AVKit
import ImageIO
import MarkdownUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct NativeFileViewerView: View {
    let page: WebPage
    let folderURL: URL
    let files: [WebPageProjectFile]
    var deletedPage: DeletedWebPage? = nil
    var hubSharePreviewCode: String? = nil
    let onRenameProject: (WebPage, String) -> Void
    let onDeletePage: () -> Void
    var onRestoreDeletedPage: (() -> Bool)? = nil
    var onPermanentlyDeletePage: (() -> Void)? = nil
    var onOpenProEntitlement: () -> Void = {}

    @EnvironmentObject private var proEntitlementStore: ProEntitlementStore
    @State private var previewPage: NativeFilePreviewItem?
    @State private var isRenameAlertPresented = false
    @State private var draftProjectTitle = ""
    @State private var isPermanentDeleteAlertPresented = false
    @State private var isRestoreErrorPresented = false
    @State private var sharePayload: SharePayload?
    @State private var isHubShareCodeSheetPresented = false
    @State private var hubShareCache: WebPageHubShareCache.ValidShare?
    @State private var isPreparingShare = false
    @State private var isSharePreparationOverlayVisible = false
    @State private var sharePreparationID: UUID?
    @State private var shareErrorMessage: String?
    @State private var isHubSharePreviewCodeCopied = false

    var body: some View {
        ZStack {
            AppPageBackground()

            if let directPreviewFile {
                NativeFilePreviewPageView(
                    url: folderURL.appendingPathComponent(directPreviewFile.relativePath, isDirectory: false),
                    projectRootURL: folderURL,
                    imageSequence: imageSequence(startingAt: directPreviewFile)
                )
            } else if files.isEmpty {
                emptyState
                    .padding(20)
            } else if showsImageGrid {
                imageGrid
            } else {
                fileList
            }

            if isSharePreparationOverlayVisible {
                sharePreparationOverlay
            }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !isReadOnlyPreview {
                    Menu {
                        nativeFileViewerActionsMenuContent
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.localized("更多操作"))
                }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(activityItems: [payload.url])
        }
        .sheet(isPresented: $isHubShareCodeSheetPresented) {
            HubShareCodeSheet(
                projectTitle: page.title,
                projectFolderURL: folderURL,
                cachedShare: hubShareCache,
                canUseExtendedRetention: proEntitlementStore.hasProEntitlement,
                onOpenProEntitlement: onOpenProEntitlement,
                onCacheChanged: { hubShareCache = $0 }
            ) {
                let projectFolderURL = folderURL
                let projectTitle = page.title
                return try await Task.detached(priority: .userInitiated) {
                    try WebPageShareExporter().shareURL(
                        forProjectFolder: projectFolderURL,
                        preferredName: projectTitle
                    )
                }.value
            }
        }
        .navigationDestination(isPresented: previewPageBinding) {
            if let previewPage {
                NativeFilePreviewPageView(
                    url: previewPage.url,
                    projectRootURL: folderURL,
                    imageSequence: previewPage.imageSequence
                )
            }
        }
        .alert(AppStrings.localized("重命名项目"), isPresented: $isRenameAlertPresented) {
            TextField(AppStrings.localized("项目名称"), text: $draftProjectTitle)
            Button(AppStrings.localized("取消"), role: .cancel) {
                resetRenameState()
            }
            Button(AppStrings.localized("保存")) {
                onRenameProject(page, draftProjectTitle)
                resetRenameState()
            }
            .disabled(normalizedDraftProjectTitle.isEmpty)
        }
        .background(SystemAlertTextFieldClearButtonInstaller(isActive: isRenameAlertPresented))
        .alert(
            AppStrings.localized("彻底删除网页？"),
            isPresented: $isPermanentDeleteAlertPresented
        ) {
            Button(AppStrings.localized("取消"), role: .cancel) {}
            Button(AppStrings.localized("彻底删除"), role: .destructive) {
                onPermanentlyDeletePage?()
            }
        } message: {
            Text(AppStrings.localized("这会永久删除这个网页及其本机文件，无法恢复。"))
        }
        .alert(AppStrings.localized("网页文件缺失"), isPresented: $isRestoreErrorPresented) {
            Button(AppStrings.localized("知道了"), role: .cancel) {}
        } message: {
            Text(AppStrings.localized("这个网页的入口文件已经不在本地网页文件夹中。"))
        }
        .alert(AppStrings.localized("无法准备分享文件"), isPresented: shareErrorBinding) {
            Button(AppStrings.localized("知道了"), role: .cancel) {
                shareErrorMessage = nil
            }
        } message: {
            Text(shareErrorMessage ?? "")
        }
        .task(id: page.id) {
            if !isReadOnlyPreview {
                await refreshHubShareCache()
            }
        }
        .onChange(of: hubSharePreviewCode) { _, _ in
            isHubSharePreviewCodeCopied = false
        }
        .safeAreaInset(edge: .bottom) {
            if isHubSharePreview {
                hubSharePreviewActionDock
            } else if isRecentlyDeletedViewer {
                recentlyDeletedActionDock
            }
        }
    }

    private var fileList: some View {
        List {
            ForEach(fileGroups) { group in
                Section {
                    ForEach(group.files) { file in
                        Button {
                            open(file)
                        } label: {
                            AppListItem(
                                title: file.fileName,
                                subtitle: subtitle(for: file),
                                showsChevron: true,
                                horizontalPadding: 0,
                                minimumHeight: nil
                            ) {
                                NativeFileKindIcon(kind: kind(for: file))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    if let title = group.title {
                        AppListSectionTitle(title)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 14, for: .scrollContent)
        .scrollContentBackground(.hidden)
    }

    private var imageGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 12)
                ],
                spacing: 14
            ) {
                ForEach(imageFiles) { file in
                    Button {
                        open(file)
                    } label: {
                        NativeImageThumbnailGridItem(
                            file: file,
                            url: folderURL.appendingPathComponent(file.relativePath, isDirectory: false)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
    }

    private var emptyState: some View {
        AppSurfaceCard(isProminent: true) {
            SectionHeader(AppStrings.localized("文件清单"), systemImage: "folder")
            Text(AppStrings.localized("这个压缩包里没有可预览的文件。"))
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var nativeFileViewerActionsMenuContent: some View {
        Button {
            performActionsMenuAction {
                startSharingFromActionsMenu()
            }
        } label: {
            Label(AppStrings.localized("分享"), systemImage: "square.and.arrow.up")
        }

        if AppDistribution.current.supportsHubShareAuthoring {
            Button {
                performActionsMenuAction {
                    startGeneratingHubCodeFromActionsMenu()
                }
            } label: {
                Label(
                    AppStrings.localized(hubShareCache == nil ? "生成暗号" : "查看暗号"),
                    systemImage: "key.fill"
                )
            }
        }

        Button {
            performActionsMenuAction {
                startRenamingFromActionsMenu()
            }
        } label: {
            Label(AppStrings.localized("重命名"), systemImage: "pencil")
        }
    }

    private var recentlyDeletedActionDock: some View {
        BottomActionDock {
            HStack(spacing: 12) {
                AppActionButton(AppStrings.localized("恢复"), systemImage: "arrow.uturn.backward", scene: .leaf) {
                    if onRestoreDeletedPage?() == false {
                        isRestoreErrorPresented = true
                    }
                }
                AppActionButton(AppStrings.localized("彻底删除"), systemImage: "trash", scene: .coral) {
                    isPermanentDeleteAlertPresented = true
                }
            }
        }
    }

    private var sharePreparationOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(AppStrings.localized("正在准备分享文件..."))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.surfaceBorder.opacity(0.4), lineWidth: 1)
        }
    }

    private var isRecentlyDeletedViewer: Bool {
        deletedPage != nil
    }

    private var isHubSharePreview: Bool {
        hubSharePreviewCode != nil
    }

    private var isReadOnlyPreview: Bool {
        isRecentlyDeletedViewer || isHubSharePreview
    }

    private var hubSharePreviewActionDock: some View {
        BottomActionDock {
            AppActionButton(
                isHubSharePreviewCodeCopied ? AppStrings.localized("已复制") : AppStrings.localized("复制暗号"),
                systemImage: isHubSharePreviewCodeCopied ? "checkmark" : "doc.on.doc",
                scene: .sky
            ) {
                guard let hubSharePreviewCode else { return }
                UIPasteboard.general.string = hubSharePreviewCode
                isHubSharePreviewCodeCopied = true
            }
        }
    }

    private var directPreviewFile: WebPageProjectFile? {
        guard files.count == 1, let file = files.first else {
            return nil
        }
        return file
    }

    private var imageFiles: [WebPageProjectFile] {
        files.filter { NativeFileKind.kind(for: $0) == .image }
            .sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
    }

    private var showsImageGrid: Bool {
        !files.isEmpty && imageFiles.count == files.count
    }

    private var normalizedDraftProjectTitle: String {
        draftProjectTitle
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var shareErrorBinding: Binding<Bool> {
        Binding {
            shareErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                shareErrorMessage = nil
            }
        }
    }

    private var previewPageBinding: Binding<Bool> {
        Binding {
            previewPage != nil
        } set: { isPresented in
            if !isPresented {
                previewPage = nil
            }
        }
    }

    private var fileGroups: [NativeFileDirectoryGroup] {
        let grouped = Dictionary(grouping: files) { file in
            Self.directoryPath(for: file.relativePath)
        }
        return grouped
            .map { directoryPath, files in
                NativeFileDirectoryGroup(
                    directoryPath: directoryPath,
                    files: files.sorted {
                        $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
                    }
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.directoryPath.isEmpty, rhs.directoryPath.isEmpty) {
                case (true, false):
                    return true
                case (false, true):
                    return false
                default:
                    return lhs.directoryPath.localizedStandardCompare(rhs.directoryPath) == .orderedAscending
                }
            }
    }

    private func open(_ file: WebPageProjectFile) {
        let url = folderURL.appendingPathComponent(file.relativePath, isDirectory: false)
        previewPage = NativeFilePreviewItem(
            url: url,
            imageSequence: imageSequence(startingAt: file)
        )
    }

    private func imageSequence(startingAt file: WebPageProjectFile) -> NativeImageSequence? {
        guard NativeFileKind.kind(for: file) == .image else { return nil }
        let images = imageFiles.map { imageFile in
            NativeImageSequenceItem(
                relativePath: imageFile.relativePath,
                url: folderURL.appendingPathComponent(imageFile.relativePath, isDirectory: false)
            )
        }
        guard images.count > 1 else { return nil }
        return NativeImageSequence(images: images, selectedRelativePath: file.relativePath)
    }

    private func subtitle(for file: WebPageProjectFile) -> String {
        let size = Self.formattedByteCount(file.byteCount)
        if file.relativePath == file.fileName {
            return size
        }
        return "\(file.relativePath) · \(size)"
    }

    private func kind(for file: WebPageProjectFile) -> NativeFileKind {
        NativeFileKind.kind(for: file)
    }

    private func startRenamingFromActionsMenu() {
        draftProjectTitle = page.title
        isRenameAlertPresented = true
    }

    private func startSharingFromActionsMenu() {
        prepareShare()
    }

    private func startGeneratingHubCodeFromActionsMenu() {
        isHubShareCodeSheetPresented = true
    }

    private func performActionsMenuAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            action()
        }
    }

    private func refreshHubShareCache() async {
        let projectFolderURL = folderURL
        let validShare = await Task.detached(priority: .utility) {
            WebPageHubShareCache.validShare(in: projectFolderURL)
        }.value
        guard !Task.isCancelled else { return }
        hubShareCache = validShare
    }

    private func prepareShare() {
        guard !isPreparingShare else { return }

        let projectFolderURL = folderURL
        let projectTitle = page.title
        let preparationID = UUID()
        sharePreparationID = preparationID
        isPreparingShare = true
        isSharePreparationOverlayVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if isPreparingShare, sharePreparationID == preparationID {
                isSharePreparationOverlayVisible = true
            }
        }

        Task {
            do {
                let shareURL = try await Task.detached(priority: .userInitiated) {
                    try WebPageShareExporter().shareURL(
                        forProjectFolder: projectFolderURL,
                        preferredName: projectTitle
                    )
                }.value
                finishPreparingShare()
                sharePayload = SharePayload(url: shareURL)
            } catch {
                finishPreparingShare()
                shareErrorMessage = AppStrings.localized("无法准备分享文件。")
            }
        }
    }

    private func finishPreparingShare() {
        isPreparingShare = false
        isSharePreparationOverlayVisible = false
        sharePreparationID = nil
    }

    private func resetRenameState() {
        isRenameAlertPresented = false
        draftProjectTitle = ""
    }

    private static func formattedByteCount(_ byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    private static func directoryPath(for relativePath: String) -> String {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard components.count > 1 else {
            return ""
        }
        return components.dropLast().joined(separator: "/")
    }
}

private struct NativeFileDirectoryGroup: Identifiable {
    let directoryPath: String
    let files: [WebPageProjectFile]

    var id: String {
        directoryPath
    }

    var title: String? {
        directoryPath.isEmpty ? nil : directoryPath
    }
}

private struct NativeFilePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    var imageSequence: NativeImageSequence?
}

private struct NativeImageSequence: Hashable {
    let images: [NativeImageSequenceItem]
    let selectedRelativePath: String

    var selectedIndex: Int {
        images.firstIndex { $0.relativePath == selectedRelativePath } ?? 0
    }
}

private struct NativeImageSequenceItem: Identifiable, Hashable {
    let relativePath: String
    let url: URL

    var id: String {
        relativePath
    }

    var fileName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }
}

private enum NativeFileKind {
    case image
    case video
    case audio
    case pdf
    case markdown
    case text
    case document
    case other

    static func kind(for file: WebPageProjectFile) -> NativeFileKind {
        let url = URL(fileURLWithPath: file.relativePath)
        return kind(
            for: WebPageSingleFileFormat.format(for: url, typeIdentifier: file.typeIdentifier)
        )
    }

    static func kind(for url: URL) -> NativeFileKind {
        kind(for: WebPageSingleFileFormat.format(for: url))
    }

    static func kind(for format: WebPageSingleFileFormat) -> NativeFileKind {
        switch format {
        case .html, .text:
            return .text
        case .markdown:
            return .markdown
        case .image:
            return .image
        case .video:
            return .video
        case .audio:
            return .audio
        case .pdf:
            return .pdf
        case .document:
            return .document
        case .file:
            return .other
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .markdown: return "text.document"
        case .text: return "doc.plaintext"
        case .document: return "doc.text"
        case .other: return "doc"
        }
    }

    var color: Color {
        switch self {
        case .image: return AppTheme.sky
        case .video: return AppTheme.aiPurple
        case .audio: return AppTheme.mint
        case .pdf: return AppTheme.coral
        case .markdown: return AppTheme.deepWater
        case .text: return AppTheme.deepWater
        case .document: return AppTheme.deepWater
        case .other: return AppTheme.textSecondary
        }
    }
}

private struct NativeFileKindIcon: View {
    let kind: NativeFileKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(kind.color.opacity(0.14))
            Image(systemName: kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(kind.color)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

private struct NativeImageThumbnailGridItem: View {
    let file: WebPageProjectFile
    let url: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .center, spacing: 7) {
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }

            Text(file.fileName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .task(id: url) {
            thumbnail = await NativeImageThumbnailLoader.thumbnail(for: url, maxPixelSize: 360)
        }
    }
}

private enum NativeImageThumbnailLoader {
    static func thumbnail(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
                return nil
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions as CFDictionary
            ) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

private struct NativeFilePreviewPageView: View {
    let url: URL
    let projectRootURL: URL
    var imageSequence: NativeImageSequence? = nil

    var body: some View {
        previewContent
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch NativeFileKind.kind(for: url) {
        case .image:
            if let imageSequence {
                NativeImageReaderView(sequence: imageSequence)
            } else if UIImage(contentsOfFile: url.path) != nil {
                NativeImagePreview(url: url)
            } else {
                NativeSystemFilePreviewPage(url: url)
            }
        case .video, .audio:
            NativeMediaPreview(url: url)
        case .markdown:
            NativeMarkdownDocumentView(url: url, projectRootURL: projectRootURL)
        case .text:
            NativePlainTextPreview(url: url)
        case .pdf, .document:
            NativeSystemFilePreviewPage(url: url)
        case .other:
            if NativePlainTextPreview.canPreview(url: url) {
                NativePlainTextPreview(url: url)
            } else {
                NativeSystemFilePreviewPage(url: url)
            }
        }
    }
}

private struct NativeImageReaderView: View {
    let sequence: NativeImageSequence
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int
    @State private var isChromeVisible = true

    init(sequence: NativeImageSequence) {
        self.sequence = sequence
        _selectedIndex = State(initialValue: sequence.selectedIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            VerticalNativeImagePager(
                images: sequence.images,
                selectedIndex: $selectedIndex
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isChromeVisible.toggle()
                }
            }
            .ignoresSafeArea()

            if isChromeVisible {
                chromeBar
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!isChromeVisible)
        .background(Color.black)
    }

    private var chromeBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.34), in: Circle())
            }
            .accessibilityLabel(AppStrings.localized("返回"))

            VStack(alignment: .leading, spacing: 2) {
                Text(currentImage.fileName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(pageCountText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.72), .black.opacity(0.42), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private var currentImage: NativeImageSequenceItem {
        sequence.images[safe: selectedIndex] ?? sequence.images[0]
    }

    private var pageCountText: String {
        String(
            format: AppStrings.localized("imageReader.pageCountFormat"),
            selectedIndex + 1,
            sequence.images.count
        )
    }
}

private struct VerticalNativeImagePager: UIViewControllerRepresentable {
    let images: [NativeImageSequenceItem]
    @Binding var selectedIndex: Int
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .vertical
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        if let initialController = context.coordinator.controller(for: selectedIndex) {
            controller.setViewControllers([initialController], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard let targetController = context.coordinator.controller(for: selectedIndex) else {
            pageViewController.setViewControllers([], direction: .forward, animated: false)
            return
        }

        let currentIndex = context.coordinator.currentIndex(in: pageViewController)
        guard currentIndex != selectedIndex else { return }
        let direction: UIPageViewController.NavigationDirection = selectedIndex > currentIndex ? .forward : .reverse
        pageViewController.setViewControllers([targetController], direction: direction, animated: true)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: VerticalNativeImagePager
        private var controllers: [Int: NativeImageReaderHostingController] = [:]

        init(parent: VerticalNativeImagePager) {
            self.parent = parent
        }

        func controller(for index: Int) -> NativeImageReaderHostingController? {
            guard parent.images.indices.contains(index) else { return nil }
            let page = NativeImageReaderPage(url: parent.images[index].url, onTap: parent.onTap)
            if let controller = controllers[index] {
                controller.rootView = page
                return controller
            }
            let controller = NativeImageReaderHostingController(index: index, rootView: page)
            controller.view.backgroundColor = .black
            controllers[index] = controller
            return controller
        }

        func currentIndex(in pageViewController: UIPageViewController) -> Int {
            guard let controller = pageViewController.viewControllers?.first as? NativeImageReaderHostingController else {
                return parent.selectedIndex
            }
            return controller.index
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let controller = viewController as? NativeImageReaderHostingController else { return nil }
            return self.controller(for: controller.index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let controller = viewController as? NativeImageReaderHostingController else { return nil }
            return self.controller(for: controller.index + 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed else { return }
            parent.selectedIndex = currentIndex(in: pageViewController)
        }
    }
}

private final class NativeImageReaderHostingController: UIHostingController<NativeImageReaderPage> {
    let index: Int

    init(index: Int, rootView: NativeImageReaderPage) {
        self.index = index
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct NativeImageReaderPage: View {
    let url: URL
    let onTap: () -> Void
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                ZoomableNativeImageView(image: image, onTap: onTap)
            } else if didFail {
                Text(AppStrings.localized("无法预览这个文件。"))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .task(id: url) {
            didFail = false
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)
            }.value
            didFail = image == nil
        }
    }
}

private struct NativeImagePreview: View {
    let url: URL

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                ZoomableNativeImageView(image: image)
                    .background(Color.black.opacity(0.92))
            } else {
                Text(AppStrings.localized("无法预览这个文件。"))
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

private struct NativeMediaPreview: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        NativeMediaPlayerView(player: player)
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                player.play()
            }
            .onDisappear {
                player.pause()
            }
    }
}

private struct NativeMediaPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context _: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.showsPlaybackControls = true
    }
}

private struct ZoomableNativeImageView: UIViewRepresentable {
    let image: UIImage
    var onTap: (() -> Void)? = nil

    func makeUIView(context _: Context) -> ZoomableImageScrollView {
        ZoomableImageScrollView()
    }

    func updateUIView(_ scrollView: ZoomableImageScrollView, context _: Context) {
        scrollView.onSingleTap = onTap
        scrollView.setImage(image)
    }
}

private final class ZoomableImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var currentImage: UIImage?
    private var lastBoundsSize: CGSize = .zero
    var onSingleTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = UIColor.black.withAlphaComponent(0.92)
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        decelerationRate = .fast

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)

        let singleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTapRecognizer.numberOfTapsRequired = 1
        let doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        singleTapRecognizer.require(toFail: doubleTapRecognizer)
        addGestureRecognizer(singleTapRecognizer)
        addGestureRecognizer(doubleTapRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        guard currentImage !== image else { return }
        currentImage = image
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        lastBoundsSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard currentImage != nil, bounds.size != .zero else { return }
        if lastBoundsSize != bounds.size {
            configureZoomScaleForCurrentBounds()
            lastBoundsSize = bounds.size
        }
        centerImageIfNeeded()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageIfNeeded()
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard currentImage != nil else { return }
        if zoomScale > minimumZoomScale * 1.08 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }

        let targetScale = min(max(minimumZoomScale * 2.2, 2), maximumZoomScale)
        let tapPoint = recognizer.location(in: imageView)
        let zoomSize = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
        let zoomRect = CGRect(
            x: tapPoint.x - zoomSize.width / 2,
            y: tapPoint.y - zoomSize.height / 2,
            width: zoomSize.width,
            height: zoomSize.height
        )
        zoom(to: zoomRect, animated: true)
    }

    private func configureZoomScaleForCurrentBounds() {
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }

        let widthScale = bounds.width / imageView.bounds.width
        let heightScale = bounds.height / imageView.bounds.height
        let fitScale = min(widthScale, heightScale)
        let initialScale = min(fitScale, 1)

        minimumZoomScale = initialScale
        maximumZoomScale = max(initialScale * 8, 4)
        zoomScale = initialScale
        contentSize = CGSize(
            width: imageView.bounds.width * initialScale,
            height: imageView.bounds.height * initialScale
        )
    }

    private func centerImageIfNeeded() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }
}

private struct NativePlainTextPreview: View {
    let url: URL
    @State private var text: String?

    var body: some View {
        Group {
            if let text {
                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(AppTheme.contentPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(16)
                }
                .background(AppTheme.pageGradient)
            } else {
                Text(AppStrings.localized("无法以纯文本预览这个文件。"))
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .onAppear {
            text = NativeTextFilePreviewReader.previewText(from: url)
        }
    }

    static func canPreview(url: URL) -> Bool {
        NativeTextFilePreviewReader.previewText(from: url, maximumByteCount: 4096) != nil
    }
}

private struct NativeMarkdownDocumentView: View {
    let url: URL
    let projectRootURL: URL
    @State private var markdown: String?
    @State private var previewPage: NativeFilePreviewItem?

    var body: some View {
        ZStack {
            AppPageBackground()

            if let markdown {
                ScrollView {
                    Markdown(
                        markdown,
                        baseURL: baseURL,
                        imageBaseURL: baseURL
                    )
                    .markdownTheme(Self.htmlKeepMarkdownTheme)
                    .environment(\.openURL, OpenURLAction { targetURL in
                        handleOpenURL(targetURL)
                    })
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
                }
                .scrollContentBackground(.hidden)
            } else {
                Text(AppStrings.localized("无法以纯文本预览这个文件。"))
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .task(id: url) {
            markdown = NativeTextFilePreviewReader.previewText(from: url)
                .map(NativeMarkdownContentNormalizer.markdownForPreview)
        }
        .navigationDestination(isPresented: previewPageBinding) {
            if let previewPage {
                NativeFilePreviewPageView(url: previewPage.url, projectRootURL: projectRootURL)
            }
        }
    }

    private var baseURL: URL {
        url.deletingLastPathComponent()
    }

    private var previewPageBinding: Binding<Bool> {
        Binding {
            previewPage != nil
        } set: { isPresented in
            if !isPresented {
                previewPage = nil
            }
        }
    }

    private func handleOpenURL(_ targetURL: URL) -> OpenURLAction.Result {
        guard !targetURL.relativeString.hasPrefix("#") else {
            return .handled
        }

        if let localURL = resolvedLocalFileURL(for: targetURL) {
            openLocalFile(localURL)
            return .handled
        }

        switch targetURL.scheme?.lowercased() {
        case "http", "https", "mailto", "tel":
            return .systemAction
        default:
            return .discarded
        }
    }

    private func openLocalFile(_ fileURL: URL) {
        previewPage = NativeFilePreviewItem(url: fileURL)
    }

    private func resolvedLocalFileURL(for targetURL: URL) -> URL? {
        let candidateURL: URL
        if targetURL.isFileURL {
            candidateURL = targetURL
        } else if targetURL.scheme == nil {
            guard let relativePath = Self.relativePath(from: targetURL), !relativePath.isEmpty else {
                return nil
            }
            candidateURL = URL(fileURLWithPath: relativePath, relativeTo: baseURL)
        } else {
            return nil
        }

        return existingFileURL(matching: candidateURL)
    }

    private func existingFileURL(matching candidateURL: URL) -> URL? {
        for fileURL in candidateFileURLs(for: candidateURL) {
            guard isInsideProjectRoot(fileURL) else {
                continue
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    if let indexURL = existingDirectoryIndexURL(in: fileURL) {
                        return indexURL
                    }
                } else {
                    return fileURL
                }
            }
        }
        return nil
    }

    private func candidateFileURLs(for candidateURL: URL) -> [URL] {
        let fileURL = candidateURL.standardizedFileURL
        var candidates = [fileURL]
        if fileURL.pathExtension.isEmpty {
            candidates.append(fileURL.appendingPathExtension("md"))
            candidates.append(fileURL.appendingPathExtension("markdown"))
        }
        return candidates
    }

    private func existingDirectoryIndexURL(in directoryURL: URL) -> URL? {
        let names = ["README.md", "README.markdown", "index.md", "index.markdown", "index.html", "index.htm"]
        return names
            .map { directoryURL.appendingPathComponent($0, isDirectory: false) }
            .first { FileManager.default.fileExists(atPath: $0.path) && isInsideProjectRoot($0) }
    }

    private func isInsideProjectRoot(_ fileURL: URL) -> Bool {
        let rootPath = projectRootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private static func relativePath(from url: URL) -> String? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           !components.path.isEmpty {
            return components.path
        }
        let rawValue = url.relativeString
        guard !rawValue.hasPrefix("#") else {
            return nil
        }
        return rawValue
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .removingPercentEncoding
    }

    private static let htmlKeepMarkdownTheme = Theme.gitHub
        .text {
            ForegroundColor(AppTheme.contentPrimary)
            BackgroundColor(nil)
            FontSize(16)
        }
}

private enum NativeMarkdownContentNormalizer {
    static func markdownForPreview(_ markdown: String) -> String {
        convertHTMLAnchorLinksOutsideFencedCode(in: markdown)
    }

    private static func convertHTMLAnchorLinksOutsideFencedCode(in markdown: String) -> String {
        var result = ""
        var cursor = markdown.startIndex
        var isInsideFencedCode = false

        while cursor < markdown.endIndex {
            let lineEnd = markdown[cursor...].firstIndex(of: "\n")
                .map { markdown.index(after: $0) } ?? markdown.endIndex
            let line = String(markdown[cursor..<lineEnd])

            if isFencedCodeDelimiter(line) {
                isInsideFencedCode.toggle()
                result += line
            } else if isInsideFencedCode {
                result += line
            } else {
                result += convertHTMLAnchorLinks(in: line)
            }

            cursor = lineEnd
        }

        return result
    }

    private static func isFencedCodeDelimiter(_ line: String) -> Bool {
        let leadingSpaces = line.prefix { $0 == " " }.count
        guard leadingSpaces <= 3 else { return false }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func convertHTMLAnchorLinks(in text: String) -> String {
        let pattern = #"<a\b[^>]*>.*?</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var lastLocation = 0
        for match in matches {
            let range = match.range
            if range.location > lastLocation {
                result += nsText.substring(with: NSRange(location: lastLocation, length: range.location - lastLocation))
            }

            let anchorHTML = nsText.substring(with: range)
            result += markdownLink(fromHTMLAnchor: anchorHTML) ?? anchorHTML
            lastLocation = range.location + range.length
        }

        if lastLocation < nsText.length {
            result += nsText.substring(from: lastLocation)
        }

        return result
    }

    private static func markdownLink(fromHTMLAnchor anchorHTML: String) -> String? {
        guard let openingRange = anchorHTML.range(
            of: #"<\s*a\b[^>]*>"#,
            options: [.caseInsensitive, .regularExpression]
        ),
              let closingRange = anchorHTML.range(
                of: #"</\s*a\s*>"#,
                options: [.caseInsensitive, .regularExpression],
                range: openingRange.upperBound..<anchorHTML.endIndex
              ) else {
            return nil
        }

        let openingTag = String(anchorHTML[openingRange])
        guard let href = htmlAttributes(in: openingTag)["href"].map(decodeBasicHTMLEntities)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !href.isEmpty else {
            return nil
        }

        let rawLabel = String(anchorHTML[openingRange.upperBound..<closingRange.lowerBound])
        let label = markdownLinkLabel(fromHTML: rawLabel)
        guard !label.isEmpty else { return nil }

        return "[\(markdownEscapedLinkLabel(label))](<\(markdownEscapedLinkDestination(href))>)"
    }

    private static func htmlAttributes(in tagText: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }

        let nsText = tagText as NSString
        var result: [String: String] = [:]
        for match in regex.matches(in: tagText, range: NSRange(location: 0, length: nsText.length)) {
            guard match.numberOfRanges == 3 else { continue }

            let name = nsText.substring(with: match.range(at: 1)).lowercased()
            var value = nsText.substring(with: match.range(at: 2))
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[name] = value
        }
        return result
    }

    private static func markdownLinkLabel(fromHTML html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return decodeBasicHTMLEntities(withoutTags)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func markdownEscapedLinkLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func markdownEscapedLinkDestination(_ destination: String) -> String {
        destination
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: ">", with: "%3E")
    }

    private static func decodeBasicHTMLEntities(_ text: String) -> String {
        let namedDecoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&apos;", with: "'", options: .caseInsensitive)

        return decodeNumericHTMLEntities(in: namedDecoded)
    }

    private static func decodeNumericHTMLEntities(in text: String) -> String {
        let pattern = #"&#(x?[0-9A-Fa-f]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var lastLocation = 0
        for match in matches {
            let fullRange = match.range(at: 0)
            if fullRange.location > lastLocation {
                result += nsText.substring(with: NSRange(location: lastLocation, length: fullRange.location - lastLocation))
            }

            let rawNumber = nsText.substring(with: match.range(at: 1))
            result += decodedNumericEntity(rawNumber) ?? nsText.substring(with: fullRange)
            lastLocation = fullRange.location + fullRange.length
        }

        if lastLocation < nsText.length {
            result += nsText.substring(from: lastLocation)
        }

        return result
    }

    private static func decodedNumericEntity(_ rawNumber: String) -> String? {
        let value: UInt32?
        if rawNumber.lowercased().hasPrefix("x") {
            value = UInt32(rawNumber.dropFirst(), radix: 16)
        } else {
            value = UInt32(rawNumber, radix: 10)
        }

        guard let value, let scalar = UnicodeScalar(value) else {
            return nil
        }
        return String(scalar)
    }
}

private enum NativeTextFilePreviewReader {
    static func previewText(
        from url: URL,
        maximumByteCount: Int = 5 * 1024 * 1024
    ) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        let fileSize = Int((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let readLimit = min(max(fileSize, 1), maximumByteCount)
        guard let data = try? handle.read(upToCount: readLimit), !data.isEmpty else {
            return ""
        }
        guard let decoded = decodedText(from: data) else {
            return nil
        }
        if fileSize > maximumByteCount {
            return decoded + "\n\n..."
        }
        return decoded
    }

    private static func decodedText(from data: Data) -> String? {
        guard !looksBinary(data) else {
            return nil
        }

        let encodings: [String.Encoding] = [
            .utf8,
            .unicode,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1
        ]
        return encodings.compactMap { encoding in
            String(data: data, encoding: encoding)
        }.first
    }

    private static func looksBinary(_ data: Data) -> Bool {
        var controlByteCount = 0
        for byte in data {
            if byte == 0 {
                return true
            }
            if byte < 0x09 || (byte > 0x0D && byte < 0x20) {
                controlByteCount += 1
            }
        }
        return controlByteCount > max(8, data.count / 100)
    }
}

private struct NativeSystemFilePreviewPage: View {
    let url: URL

    var body: some View {
        NativeSystemFilePreview(url: url)
            .ignoresSafeArea(edges: .bottom)
    }
}

private struct NativeSystemFilePreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
