import AVKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct NativeFileViewerView: View {
    let page: WebPage
    let folderURL: URL
    let files: [WebPageProjectFile]
    var deletedPage: DeletedWebPage? = nil
    let onRenameProject: (WebPage, String) -> Void
    let onDeletePage: () -> Void
    var onRestoreDeletedPage: (() -> Bool)? = nil
    var onPermanentlyDeletePage: (() -> Void)? = nil

    @State private var imagePreview: NativeFilePreviewItem?
    @State private var mediaPreview: NativeFilePreviewItem?
    @State private var textPreview: NativeFilePreviewItem?
    @State private var systemPreview: NativeFilePreviewItem?
    @State private var isActionsPopoverPresented = false
    @State private var isRenameAlertPresented = false
    @State private var draftProjectTitle = ""
    @State private var isDeleteAlertPresented = false
    @State private var isPermanentDeleteAlertPresented = false
    @State private var isRestoreErrorPresented = false
    @State private var sharePayload: SharePayload?
    @State private var isPreparingShare = false
    @State private var isSharePreparationOverlayVisible = false
    @State private var sharePreparationID: UUID?
    @State private var shareErrorMessage: String?

    var body: some View {
        ZStack {
            AppPageBackground()

            if files.isEmpty {
                emptyState
                    .padding(20)
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
                if !isRecentlyDeletedViewer {
                    Button {
                        isActionsPopoverPresented = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.localized("更多操作"))
                    .popover(
                        isPresented: $isActionsPopoverPresented,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
                        actionsPopover
                    }
                }
            }
        }
        .sheet(item: $imagePreview) { item in
            NativeImagePreview(url: item.url)
        }
        .sheet(item: $mediaPreview) { item in
            NativeMediaPreview(url: item.url)
        }
        .sheet(item: $textPreview) { item in
            NativePlainTextPreview(url: item.url)
        }
        .sheet(item: $systemPreview) { item in
            NativeSystemFilePreview(url: item.url)
        }
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(activityItems: [payload.url])
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
        .alert(AppStrings.localized("删除网页？"), isPresented: $isDeleteAlertPresented) {
            Button(AppStrings.localized("取消"), role: .cancel) {}
            Button(AppStrings.localized("删除"), role: .destructive) {
                onDeletePage()
            }
        } message: {
            Text(AppStrings.localized("这会将网页移到最近删除，之后可以在设置中恢复。"))
        }
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
        .safeAreaInset(edge: .bottom) {
            if isRecentlyDeletedViewer {
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

    private var emptyState: some View {
        AppSurfaceCard(isProminent: true) {
            SectionHeader(AppStrings.localized("文件清单"), systemImage: "folder")
            Text(AppStrings.localized("这个压缩包里没有可预览的文件。"))
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var actionsPopover: some View {
        VStack(spacing: 0) {
            ViewerActionPopoverRow(
                title: AppStrings.localized("分享"),
                systemImage: "square.and.arrow.up"
            ) {
                isActionsPopoverPresented = false
                startSharingAfterActionsPopoverDismiss()
            }
            Divider()
                .padding(.leading, 52)

            ViewerActionPopoverRow(
                title: AppStrings.localized("重命名"),
                systemImage: "pencil"
            ) {
                isActionsPopoverPresented = false
                startRenamingAfterActionsPopoverDismiss()
            }
            Divider()
                .padding(.leading, 52)

            ViewerActionPopoverRow(
                title: AppStrings.localized("删除"),
                systemImage: "trash",
                role: .destructive
            ) {
                isActionsPopoverPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isDeleteAlertPresented = true
                }
            }
        }
        .padding(.vertical)
        .frame(width: min(UIScreen.main.bounds.width - 32, 260))
        .fixedSize(horizontal: false, vertical: true)
        .presentationCompactAdaptation(.popover)
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
        switch kind(for: file) {
        case .image:
            if UIImage(contentsOfFile: url.path) != nil {
                imagePreview = NativeFilePreviewItem(url: url)
            } else {
                systemPreview = NativeFilePreviewItem(url: url)
            }
        case .audio, .video:
            mediaPreview = NativeFilePreviewItem(url: url)
        case .text:
            textPreview = NativeFilePreviewItem(url: url)
        case .other:
            if NativePlainTextPreview.canPreview(url: url) {
                textPreview = NativeFilePreviewItem(url: url)
            } else {
                systemPreview = NativeFilePreviewItem(url: url)
            }
        case .pdf, .document:
            systemPreview = NativeFilePreviewItem(url: url)
        }
    }

    private func subtitle(for file: WebPageProjectFile) -> String {
        let size = Self.formattedByteCount(file.byteCount)
        if file.relativePath == file.fileName {
            return size
        }
        return "\(file.relativePath) · \(size)"
    }

    private func kind(for file: WebPageProjectFile) -> NativeFileKind {
        let type = file.typeIdentifier.flatMap(UTType.init) ??
            UTType(filenameExtension: URL(fileURLWithPath: file.relativePath).pathExtension)
        guard let type else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .text) || type.conforms(to: .json) || type.conforms(to: .xml) || Self.isKnownTextExtension(file.relativePath) {
            return .text
        }
        return .other
    }

    private func startRenamingAfterActionsPopoverDismiss() {
        draftProjectTitle = page.title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isRenameAlertPresented = true
        }
    }

    private func startSharingAfterActionsPopoverDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            prepareShare()
        }
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

    private static func isKnownTextExtension(_ relativePath: String) -> Bool {
        let ext = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        return [
            "txt", "text", "lrc", "md", "markdown", "csv", "tsv", "log",
            "json", "xml", "yaml", "yml", "ini", "conf", "cfg",
            "srt", "ass", "ssa", "vtt", "css", "js", "mjs", "ts"
        ].contains(ext)
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
}

private enum NativeFileKind {
    case image
    case video
    case audio
    case pdf
    case text
    case document
    case other

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
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

private struct NativeImagePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("关闭")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct NativeMediaPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        NavigationStack {
            NativeMediaPlayerView(player: player)
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppStrings.localized("关闭")) {
                            player.pause()
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    player.play()
                }
                .onDisappear {
                    player.pause()
                }
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

    func makeUIView(context _: Context) -> ZoomableImageScrollView {
        ZoomableImageScrollView()
    }

    func updateUIView(_ scrollView: ZoomableImageScrollView, context _: Context) {
        scrollView.setImage(image)
    }
}

private final class ZoomableImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var currentImage: UIImage?
    private var lastBoundsSize: CGSize = .zero

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
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?

    var body: some View {
        NavigationStack {
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
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("关闭")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            text = Self.previewText(from: url)
        }
    }

    static func canPreview(url: URL) -> Bool {
        previewText(from: url, maximumByteCount: 4096) != nil
    }

    private static func previewText(
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
