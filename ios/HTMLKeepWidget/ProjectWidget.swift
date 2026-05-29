import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct ProjectWidgetProjectEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "网页项目"
    static var defaultQuery = ProjectWidgetProjectQuery()

    let id: UUID
    let title: String

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }

    init(project: ProjectWidgetProject) {
        self.init(id: project.id, title: project.title)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct ProjectWidgetProjectQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProjectWidgetProjectEntity] {
        let snapshot = ProjectWidgetShared.readSnapshot()
        return snapshot.projects
            .filter { identifiers.contains($0.id) }
            .map(ProjectWidgetProjectEntity.init(project:))
    }

    func suggestedEntities() async throws -> [ProjectWidgetProjectEntity] {
        let snapshot = ProjectWidgetShared.readSnapshot()
        return ProjectWidgetShared.projectsAvailableForWidgetConfiguration(in: snapshot)
            .map(ProjectWidgetProjectEntity.init(project:))
    }
}

enum ProjectWidgetIconSizeMode: String, AppEnum {
    case automatic
    case standard
    case large

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "图标尺寸"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "自动"),
        .standard: DisplayRepresentation(title: "标准"),
        .large: DisplayRepresentation(title: "大图")
    ]
}

struct ProjectWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "网页入口"
    static var description = IntentDescription("打开一个指定的网页项目。")

    @Parameter(title: "网页项目")
    var project: ProjectWidgetProjectEntity?

    @Parameter(title: "图标尺寸", default: .automatic)
    var iconSizeMode: ProjectWidgetIconSizeMode?

    init() {
        self.project = nil
        self.iconSizeMode = .automatic
    }

    init(
        project: ProjectWidgetProjectEntity? = nil,
        iconSizeMode: ProjectWidgetIconSizeMode? = .automatic
    ) {
        self.project = project
        self.iconSizeMode = iconSizeMode
    }
}

struct ProjectWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: ProjectWidgetConfigurationIntent
    let project: ProjectWidgetProject?
    let state: ProjectWidgetState
}

enum ProjectWidgetState: Hashable {
    case unconfigured
    case ready
    case syncing
    case unavailable
    case missing
    case proEntitlementRequired
}

struct ProjectWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProjectWidgetEntry {
        ProjectWidgetEntry(
            date: .now,
            configuration: ProjectWidgetConfigurationIntent(),
            project: .preview,
            state: .ready
        )
    }

    func snapshot(
        for configuration: ProjectWidgetConfigurationIntent,
        in context: Context
    ) async -> ProjectWidgetEntry {
        entry(for: configuration)
    }

    func timeline(
        for configuration: ProjectWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<ProjectWidgetEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func entry(for configuration: ProjectWidgetConfigurationIntent) -> ProjectWidgetEntry {
        guard let selectedProject = configuration.project else {
            return ProjectWidgetEntry(date: .now, configuration: configuration, project: nil, state: .unconfigured)
        }

        let snapshot = ProjectWidgetShared.readSnapshot()
        guard let project = snapshot.projects.first(where: { $0.id == selectedProject.id }) else {
            return ProjectWidgetEntry(date: .now, configuration: configuration, project: nil, state: .missing)
        }

        let state: ProjectWidgetState
        if ProjectWidgetShared.bindingAccess(
            for: project.id,
            activeProjectIDs: Set(snapshot.projects.map(\.id))
        ) == .requiresProEntitlement {
            state = .proEntitlementRequired
        } else if project.loadStatus.isCloudPackageUnavailable {
            state = .syncing
        } else if project.isOpenable {
            state = .ready
        } else {
            state = .unavailable
        }

        return ProjectWidgetEntry(date: .now, configuration: configuration, project: project, state: state)
    }
}

struct ProjectWidgetEntryView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: ProjectWidgetEntry

    var body: some View {
        let paint = ProjectWidgetPaint.resolve(from: entry.project?.safeAreaTopBackground, colorScheme: colorScheme)

        rootContent(foreground: paint.foreground, foregroundIsDark: paint.foregroundIsDark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) {
                paint.background
            }
            .widgetURL(widgetURL)
    }

    @ViewBuilder
    private func rootContent(foreground: Color, foregroundIsDark: Bool) -> some View {
        if let project = entry.project,
           effectiveIconSizeMode(for: project) == .large,
           entry.state != .missing,
           entry.state != .proEntitlementRequired {
            if let image = ProjectWidgetIconLoader.image(for: project) {
                largeImageIconContent(project: project, image: image)
            } else {
                largeFallbackIconContent(project: project, foreground: foreground)
            }
        } else {
            content(foreground: foreground, foregroundIsDark: foregroundIsDark)
                .padding(14)
        }
    }

    private func effectiveIconSizeMode(for project: ProjectWidgetProject) -> ProjectWidgetIconSizeMode {
        let configuredMode = entry.configuration.iconSizeMode ?? .automatic
        switch configuredMode {
        case .automatic:
            return project.usesCustomIcon ? .large : .standard
        case .standard, .large:
            return configuredMode
        }
    }

    @ViewBuilder
    private func content(foreground: Color, foregroundIsDark: Bool) -> some View {
        switch entry.state {
        case .unconfigured:
            unconfiguredContent(foreground: foreground, foregroundIsDark: foregroundIsDark)
        case .ready, .syncing, .unavailable:
            if let project = entry.project {
                configuredContent(project: project, foreground: foreground)
            } else {
                unavailableContent(foreground: foreground, foregroundIsDark: foregroundIsDark)
            }
        case .missing:
            unavailableContent(foreground: foreground, foregroundIsDark: foregroundIsDark)
        case .proEntitlementRequired:
            proEntitlementRequiredContent(foreground: foreground)
        }
    }

    private func unconfiguredContent(foreground: Color, foregroundIsDark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("请设置网页")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            VStack(alignment: .leading, spacing: 7) {
                ProjectWidgetInstructionStep(
                    index: 1,
                    title: "长按当前小组件",
                    foreground: foreground,
                    numberForeground: foregroundIsDark ? .white : .black.opacity(0.88)
                )
                ProjectWidgetInstructionStep(
                    index: 2,
                    title: "点击“编辑小组件”",
                    foreground: foreground,
                    numberForeground: foregroundIsDark ? .white : .black.opacity(0.88)
                )
                ProjectWidgetInstructionStep(
                    index: 3,
                    title: "选择网页项目",
                    foreground: foreground,
                    numberForeground: foregroundIsDark ? .white : .black.opacity(0.88)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func configuredContent(project: ProjectWidgetProject, foreground: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                projectIconContent(project: project, foreground: foreground)

                statusBadge(foreground: foreground)
                    .offset(x: 32, y: -30)
            }

            Text(verbatim: project.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func projectIconContent(project: ProjectWidgetProject, foreground: Color) -> some View {
        if let image = ProjectWidgetIconLoader.image(for: project) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(foreground.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 4)
        } else {
            Image(systemName: project.fallbackSymbolName)
                .font(.system(size: 58, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(foreground)
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 4)
                .frame(width: 72, height: 72)
        }
    }

    private func unavailableContent(foreground: Color, foregroundIsDark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("请重新选择网页")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            VStack(alignment: .leading, spacing: 7) {
                ProjectWidgetInstructionStep(
                    index: 1,
                    title: "长按当前小组件",
                    foreground: foreground,
                    numberForeground: foregroundIsDark ? .white : .black.opacity(0.88)
                )
                ProjectWidgetInstructionStep(
                    index: 2,
                    title: "点击“编辑小组件”",
                    foreground: foreground,
                    numberForeground: foregroundIsDark ? .white : .black.opacity(0.88)
                )
                ProjectWidgetInstructionStep(
                    index: 3,
                    title: "选择网页项目",
                    foreground: foreground,
                    numberForeground: foregroundIsDark ? .white : .black.opacity(0.88)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func proEntitlementRequiredContent(foreground: Color) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(foreground)

            Text("开通 Pro 权益，解锁更多小组件")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(foreground.opacity(0.88))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.74)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func largeImageIconContent(project: ProjectWidgetProject, image: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            if entry.state == .syncing || entry.state == .unavailable {
                Rectangle()
                    .fill(.black.opacity(0.18))
            }

            VStack {
                Spacer()

                largeTitleFade(bottomOpacity: 0.46)
            }

            VStack {
                Spacer()

                largeTitle(project.title)
            }

            statusBadge(foreground: .white)
                .padding(10)
        }
    }

    private func largeFallbackIconContent(project: ProjectWidgetProject, foreground: Color) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let iconSize = min(max(side * 0.48, 68), 80)

            ZStack(alignment: .topTrailing) {
                Image(systemName: project.fallbackSymbolName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(foreground)
                    .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 5)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)

                if entry.state == .syncing || entry.state == .unavailable {
                    Rectangle()
                        .fill(.black.opacity(0.12))
                }

                VStack {
                    Spacer()

                    largeTitleFade(bottomOpacity: 0.38)
                }

                VStack {
                    Spacer()

                    largeTitle(project.title)
                }

                statusBadge(foreground: .white)
                    .padding(10)
            }
        }
    }

    private func largeTitleFade(bottomOpacity: Double) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(bottomOpacity * 0.28), location: 0.46),
                .init(color: .black.opacity(bottomOpacity), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 48)
    }

    private func largeTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.82)
            .shadow(color: .black.opacity(0.38), radius: 0.28, x: 0, y: 0.5)
            .shadow(color: .black.opacity(0.30), radius: 1.25, x: 0, y: 0.95)
            .shadow(color: .black.opacity(0.20), radius: 3.2, x: 0, y: 1.8)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
    }

    @ViewBuilder
    private func statusBadge(foreground: Color) -> some View {
        switch entry.state {
        case .syncing:
            ProgressView()
                .controlSize(.mini)
                .tint(foreground)
                .padding(5)
                .background(.ultraThinMaterial, in: Circle())
        case .unavailable:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(5)
                .background(.ultraThinMaterial, in: Circle())
        case .proEntitlementRequired:
            Image(systemName: "crown.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(foreground)
                .padding(5)
                .background(.ultraThinMaterial, in: Circle())
        case .ready, .unconfigured, .missing:
            EmptyView()
        }
    }

    private var widgetURL: URL {
        if entry.state == .proEntitlementRequired {
            return ProjectWidgetShared.proEntitlementURL
        }

        if let project = entry.project {
            return ProjectWidgetShared.openProjectURL(
                projectID: project.id,
                safeAreaTopBackground: project.safeAreaTopBackground
            )
        }

        if let id = entry.configuration.project?.id {
            return ProjectWidgetShared.openProjectURL(projectID: id)
        }

        return ProjectWidgetShared.homeURL
    }
}

private struct ProjectWidgetInstructionStep: View {
    let index: Int
    let title: LocalizedStringKey
    let foreground: Color
    let numberForeground: Color

    var body: some View {
        HStack(spacing: 7) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(numberForeground)
                .frame(width: 17, height: 17)
                .background(foreground.opacity(0.92), in: Circle())

            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private enum ProjectWidgetIconLoader {
    static func image(for project: ProjectWidgetProject) -> UIImage? {
        guard let iconFileName = project.iconFileName,
              let url = ProjectWidgetShared.iconURL(fileName: iconFileName) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }
}

struct ProjectEntryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: ProjectWidgetShared.widgetKind,
            intent: ProjectWidgetConfigurationIntent.self,
            provider: ProjectWidgetProvider()
        ) { entry in
            ProjectWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("网页入口")
        .description("打开一个指定的网页项目。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
struct HTMLKeepWidget: WidgetBundle {
    var body: some Widget {
        ProjectEntryWidget()
    }
}

private extension ProjectWidgetProject {
    static let preview = ProjectWidgetProject(
        id: UUID(),
        title: "我的网页",
        kind: .html,
        loadStatus: .ready,
        isOpenable: true,
        usesCustomIcon: false,
        safeAreaTopBackground: "linear-gradient(135deg, #6DD5FA, #FFFFFF)",
        iconFileName: nil,
        fallbackSymbolName: "doc.text.fill",
        updatedAt: .now
    )
}
