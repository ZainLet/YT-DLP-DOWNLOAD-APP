import SwiftUI
import AppKit

// A real behind-window material: the desktop remains visible through a dark frosted surface.
private final class StudioBackdropView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.appearance = NSAppearance(named: .darkAqua)
        window?.styleMask.insert(.fullSizeContentView)
    }
}

private struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = StudioBackdropView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct Panel<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(24)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.68), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(contrast == .increased ? 0.32 : 0.09), lineWidth: 1))
    }
}

private struct GlassAction: ViewModifier {
    var prominent = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 30, weight: .semibold)).tracking(-0.6)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

private struct OptionMenu: View {
    let title: String
    @Binding var selection: String
    let values: [String]
    var label: (String) -> String = { $0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Menu {
                ForEach(values, id: \.self) { value in
                    Button { selection = value } label: {
                        if selection == value { Label(label(value), systemImage: "checkmark") }
                        else { Text(label(value)) }
                    }
                }
            } label: {
                HStack { Text(label(selection)).lineLimit(1); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
                    .font(.system(size: 13, weight: .medium)).padding(.horizontal, 13).frame(height: 38)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.07)))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 36)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(title).accessibilityValue(label(selection))
        }
    }
}

struct ContentView: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var urls = ""
    @State private var options = DownloadOptions()
    @State private var directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/YTDLP Studio").path
    @State private var selectedTab = 0
    @State private var filter = "Todos"
    @State private var showFormats = false
    @State private var showInstagramLogin = false
    @State private var showStoryPicker = false
    @State private var instagramURL = ""
    @State private var pendingInstagramURL = ""
    @State private var storyItems: [InstagramStory] = []
    @State private var selectedStoryIDs: Set<String> = []
    @State private var loadingStories = false
    @State private var storyError = ""
    @State private var advanced = false
    @FocusState private var linksFocused: Bool

    private var links: [String] { urls.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    private var invalidLinks: Bool { links.contains { let u = URL(string: $0); return !["https", "http"].contains(u?.scheme?.lowercased() ?? "") || u?.host == nil } }
    private var canAdd: Bool { !links.isEmpty && !invalidLinks && !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor).ignoresSafeArea() }
            else { WindowBackdrop().ignoresSafeArea(); Color.black.opacity(0.64).ignoresSafeArea().allowsHitTesting(false) }
            TabView(selection: $selectedTab) {
                downloadPage.tabItem { Label("Baixar", systemImage: "arrow.down.to.line") }.tag(0)
                instagramPage.tabItem { Label("Instagram", systemImage: "camera") }.tag(3)
                activityPage.tabItem { Label("Atividade", systemImage: "waveform.path") }.tag(1)
                completedPage.tabItem { Label("Concluídos", systemImage: "checkmark.circle") }.tag(2)
            }
        }
        .frame(minWidth: 740, minHeight: 620)
        .sheet(isPresented: $showFormats, onDismiss: { manager.cancelProbe() }) {
            FormatsSheet(manager: manager) { format in
                options.selector = format.selector
                if !format.hasVideo { options.kind = .audio; options.container = "best" }
                else { options.kind = .video; options.container = "auto" }
                advanced = true
            }
        }
        .sheet(isPresented: $showStoryPicker, onDismiss: {
            if loadingStories { manager.cancelStoryProbe(); loadingStories = false }
        }) {
            InstagramStoryPickerSheet(stories: storyItems, selectedIDs: $selectedStoryIDs,
                                      loading: loadingStories, error: storyError,
                                      cancel: { showStoryPicker = false },
                                      download: {
                                          let selected = storyItems.filter { selectedStoryIDs.contains($0.id) }
                                          if !pendingInstagramURL.isEmpty {
                                              var instagramOptions = options
                                              instagramOptions.instagramSessionUsername = manager.instagramSessionUsername
                                              manager.addInstagramStories(selected, url: pendingInstagramURL, options: instagramOptions, directory: directory)
                                              instagramURL = ""
                                              pendingInstagramURL = ""
                                              showStoryPicker = false
                                              selectedTab = 1
                                          }
                                      })
        }
        .sheet(isPresented: $showInstagramLogin) {
            InstagramLoginSheet(manager: manager) { showInstagramLogin = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .studioNavigate)) { notification in
            if let tab = notification.object as? Int { selectedTab = tab; if tab == 0 { linksFocused = true } }
        }
    }

    private var downloadPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        SectionTitle(title: "Tudo pronto para baixar.", subtitle: "Vídeos e músicas, do link para o seu Mac.")
                        Spacer(minLength: 16)
                        Label("No seu Mac", systemImage: "lock.shield").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    if geometry.size.width >= 900 {
                        HStack(alignment: .top, spacing: 20) { composer.frame(maxWidth: .infinity); exportOptions.frame(width: 296) }
                    } else {
                        VStack(spacing: 20) { composer; exportOptions }
                    }
                    recentActivity
                }
                .frame(maxWidth: 1140).padding(32).frame(maxWidth: .infinity)
            }.scrollContentBackground(.hidden)
        }
    }

    private var instagramPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionTitle(title: "Stories, do seu jeito.", subtitle: "Liste o conteúdo disponível e escolha exatamente o que salvar.")
                HStack(alignment: .top, spacing: 20) {
                    Panel {
                        VStack(alignment: .leading, spacing: 18) {
                            Label("Link do Instagram", systemImage: "link").font(.system(size: 15, weight: .semibold))
                            TextField("https://www.instagram.com/perfil/", text: $instagramURL)
                                .textFieldStyle(.roundedBorder).font(.system(size: 14))
                                .onSubmit { openInstagramPicker() }
                            Text("Use um perfil ou um link direto de Story. O app exibirá a lista antes de iniciar o download.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button(action: openInstagramPicker) {
                                HStack { Image(systemName: "list.bullet.rectangle"); Text("Listar Stories"); Spacer(); Text("⌘↵").font(.system(size: 11)).opacity(0.65) }
                                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                            }.modifier(GlassAction(prominent: true)).controlSize(.large)
                                .keyboardShortcut(.return, modifiers: .command)
                                .disabled(!instagramURLIsValid)
                        }
                    }.frame(maxWidth: .infinity)
                    Panel {
                        VStack(alignment: .leading, spacing: 18) {
                            Label("Acesso e destino", systemImage: "lock.shield").font(.system(size: 15, weight: .semibold))
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(manager.instagramSessionUsername.isEmpty ? "Nenhuma conta conectada" : "@\(manager.instagramSessionUsername)")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Sessão local do Instaloader").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(manager.instagramSessionUsername.isEmpty ? "Conectar…" : "Trocar…") { showInstagramLogin = true }
                                    .buttonStyle(.borderless).font(.system(size: 12))
                            }
                            Text("A senha não é armazenada nem enviada para o backend. O Instaloader salva apenas a sessão local necessária para consultar Stories.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Label("Destino", systemImage: "folder").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary); Spacer(); Button("Alterar…", action: chooseFolder).buttonStyle(.borderless).font(.system(size: 12)) }
                                TextField("Pasta de destino", text: $directory).textFieldStyle(.roundedBorder).font(.system(size: 12))
                            }
                        }
                    }.frame(width: 296)
                }
                Panel {
                    HStack(spacing: 14) {
                        Image(systemName: "checklist").font(.system(size: 24, weight: .light)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Seleção antes do download").font(.system(size: 13, weight: .medium))
                            Text("Depois da consulta, marque apenas os Stories que quer baixar. Perfis e links diretos usam o mesmo seletor.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
            }.frame(maxWidth: 1140, alignment: .leading).padding(32).frame(maxWidth: .infinity)
        }.scrollContentBackground(.hidden)
    }

    private var composer: some View {
        Panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Seus links", systemImage: "link").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(links.isEmpty ? "Um por linha" : "\(links.count) \(links.count == 1 ? "link" : "links")").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $urls).font(.system(size: 14)).scrollContentBackground(.hidden)
                        .focused($linksFocused).padding(10).accessibilityLabel("Links para baixar")
                    if urls.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Cole os links aqui").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                            Text(verbatim: "https://youtube.com/watch?v=…").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.padding(16).allowsHitTesting(false)
                    }
                }
                .frame(height: 214)
                .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(linksFocused ? Color.accentColor.opacity(0.7) : .white.opacity(0.07)))
                if invalidLinks { Label("Use links completos começando com https://", systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange) }
                HStack {
                    Button { pasteLinks() } label: { Label("Colar links", systemImage: "doc.on.clipboard") }
                        .modifier(GlassAction()).controlSize(.large)
                    Spacer()
                    Button { showFormats = true; if let first = links.first { manager.loadFormats(url: first, options: options) } } label: {
                        Label("Formatos do link…", systemImage: "slider.horizontal.3")
                    }.buttonStyle(.borderless).disabled(links.isEmpty || invalidLinks).help("Consultar todas as resoluções, formatos e codecs disponíveis no primeiro link")
                }
                Divider().opacity(0.5)
                Label("Adicione vários links de uma vez. A fila cuida do resto.", systemImage: "square.stack.3d.up")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var exportOptions: some View {
        Panel {
            VStack(alignment: .leading, spacing: 18) {
                Label("Como salvar", systemImage: "slider.horizontal.3").font(.system(size: 15, weight: .semibold))
                Picker("Tipo de mídia", selection: Binding(get: { options.kind }, set: { kind in
                    options.kind = kind; options.container = kind == .video ? "mp4" : "mp3"; options.selector = ""
                })) {
                    Label("Vídeo", systemImage: "play.rectangle").tag(MediaKind.video)
                    Label("Áudio", systemImage: "music.note").tag(MediaKind.audio)
                }.pickerStyle(.segmented).labelsHidden()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Instagram e Stories", systemImage: "camera").font(.system(size: 12, weight: .semibold))
                    Text("Use a aba Instagram para conectar uma conta e escolher Stories individualmente. A sessão própria do Instaloader permanece no Mac.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                OptionMenu(title: "Formato", selection: $options.container,
                           values: options.kind == .video ? DownloadCommand.videoContainers : DownloadCommand.audioContainers,
                           label: { ["auto": "Original · sem remux", "best": "Original · melhor áudio", "vorbis": "OGG · Vorbis", "alac": "ALAC · sem perdas", "flac": "FLAC · sem perdas", "wav": "WAV · sem perdas"][$0] ?? $0.uppercased() })
                if options.kind == .video {
                    OptionMenu(title: "Resolução máxima", selection: $options.resolution,
                               values: ["best", "4320", "2160", "1440", "1080", "720", "480", "360", "240", "144"],
                               label: { ["best": "Melhor disponível", "4320": "8K · 4320p", "2160": "4K · 2160p", "1440": "2K · 1440p", "1080": "Full HD · 1080p", "720": "HD · 720p"][$0] ?? "\($0)p" })
                } else {
                    OptionMenu(title: "Qualidade de conversão", selection: $options.audioQuality,
                               values: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "320K", "256K", "192K", "160K", "128K", "96K", "64K"],
                               label: { $0 == "0" ? "Melhor qualidade · VBR 0" : $0.hasSuffix("K") ? "\($0.dropLast()) kbps" : "VBR \($0)" })
                }
                DisclosureGroup("Codecs e opções avançadas", isExpanded: $advanced) {
                    VStack(spacing: 14) {
                        if options.kind == .video {
                            OptionMenu(title: "Codec de vídeo da fonte", selection: $options.videoCodec, values: DownloadCommand.videoCodecs, label: codecLabel)
                            OptionMenu(title: "Quadros por segundo", selection: $options.fps, values: ["any", "120", "60", "50", "30", "25", "24"], label: { $0 == "any" ? "Automático" : "Até \($0) fps" })
                        }
                        OptionMenu(title: "Codec de áudio da fonte", selection: $options.audioCodec, values: DownloadCommand.audioCodecs, label: codecLabel)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Seletor yt-dlp (opcional)").font(.system(size: 12)).foregroundStyle(.secondary)
                            TextField("Ex.: 137+140 ou bv+ba/b", text: $options.selector).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                                .help("Substitui os filtros de resolução e codec. Aceita a sintaxe completa de seleção do yt-dlp.")
                        }
                        Text("Codecs filtram a fonte disponível. O formato pode converter o áudio; o vídeo é remuxado sem recodificar. O seletor manual substitui os filtros.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 12)
                }.font(.system(size: 12, weight: .medium))
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Label("Destino", systemImage: "folder").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary); Spacer(); Button("Alterar…", action: chooseFolder).buttonStyle(.borderless).font(.system(size: 12)) }
                    TextField("Pasta de destino", text: $directory).textFieldStyle(.roundedBorder).font(.system(size: 12)).help(directory)
                }
                Button(action: add) {
                    HStack { Image(systemName: "arrow.down"); Text(links.count > 1 ? "Baixar \(links.count) arquivos" : "Iniciar download"); Spacer(minLength: 4); Text("⌘↵").font(.system(size: 11)).opacity(0.65) }.frame(maxWidth: .infinity).padding(.vertical, 5)
                }.modifier(GlassAction(prominent: true)).controlSize(.large).keyboardShortcut(.return, modifiers: .command).disabled(!canAdd)
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Última atividade").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Ver tudo", systemImage: "arrow.right") { selectedTab = 1 }.buttonStyle(.borderless).font(.system(size: 12))
            }
            if manager.jobs.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) { Text("Sua fila começa aqui").font(.system(size: 13, weight: .medium)); Text("Os próximos downloads aparecem neste espaço.").font(.system(size: 12)).foregroundStyle(.secondary) }
                    Spacer()
                    Text("Até 2 simultâneos").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(20).frame(maxWidth: .infinity).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) { ForEach(Array(manager.jobs.prefix(2))) { job in JobRow(job: job) { manager.cancel(job) } } }
            }
        }
    }

    private var activityPage: some View {
        let jobs = manager.jobs.filter { job in
            switch filter {
            case "Baixando": return job.isActive
            case "Na fila": return job.status == "Na fila"
            case "Falhas": return job.status == "Falhou"
            default: return job.status != "Concluído"
            }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionTitle(title: "Cada download, no seu tempo.", subtitle: "Acompanhe o progresso e o que vem a seguir.")
                HStack(spacing: 32) {
                    metric("Baixando", value: manager.activeCount, symbol: "arrow.down.circle", color: .accentColor)
                    metric("Na fila", value: manager.queuedCount, symbol: "clock", color: .secondary)
                    metric("Concluídos", value: manager.doneCount, symbol: "checkmark.circle", color: .green)
                    Spacer()
                }.padding(.vertical, 6)
                Picker("Filtrar downloads", selection: $filter) { ForEach(["Todos", "Baixando", "Na fila", "Falhas"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 400)
                if jobs.isEmpty {
                    EmptyDownloads(symbol: "tray.and.arrow.down", title: "Tudo em dia", subtitle: "Adicione novos links para começar sua próxima fila.") { selectedTab = 0; linksFocused = true }
                } else {
                    Panel { LazyVStack(spacing: 0) { ForEach(jobs) { job in JobRow(job: job) { manager.cancel(job) } } } }
                }
            }.frame(maxWidth: 1140, alignment: .leading).padding(32).frame(maxWidth: .infinity)
        }.scrollContentBackground(.hidden)
    }

    private var completedPage: some View {
        let done = manager.jobs.filter { $0.status == "Concluído" }
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    SectionTitle(title: "Prontos para dar play.", subtitle: "Seus downloads finalizados, reunidos em um lugar.")
                    Spacer()
                    Text("\(done.count) \(done.count == 1 ? "arquivo" : "arquivos")").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8)
                }
                if done.isEmpty { EmptyDownloads(symbol: "checkmark.seal", title: "Sua coleção começa aqui", subtitle: "Quando um download terminar, você vai encontrá-lo aqui.") { selectedTab = 0; linksFocused = true } }
                else { Panel { LazyVStack(spacing: 0) { ForEach(done) { job in JobRow(job: job) {} } } } }
            }.frame(maxWidth: 1140, alignment: .leading).padding(32).frame(maxWidth: .infinity)
        }.scrollContentBackground(.hidden)
    }

    private func metric(_ title: String, value: Int, symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 21)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) { Text("\(value)").font(.system(size: 24, weight: .semibold)).monospacedDigit(); Text(title).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
    }

    private func codecLabel(_ value: String) -> String {
        ["any": "Automático · melhor disponível", "h264": "H.264 / AVC", "hevc": "H.265 / HEVC", "av1": "AV1", "mpeg2": "MPEG-2", "mpeg4": "MPEG-4", "prores": "ProRes"] [value] ?? value.uppercased()
    }
    private func pasteLinks() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        urls += (urls.isEmpty || urls.hasSuffix("\n") ? "" : "\n") + text
        linksFocused = true
    }
    private func add() {
        guard canAdd else { return }
        if links.count == 1, InstagramCommand.username(for: links[0]) != nil {
            openInstagramPicker(for: links[0])
            return
        }
        manager.add(urls: links, options: options, directory: directory)
        urls = ""
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1)) { selectedTab = 1 }
    }
    private var instagramURLIsValid: Bool {
        guard let url = URL(string: instagramURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased()) && InstagramCommand.username(for: url.absoluteString) != nil
    }
    private func openInstagramPicker() {
        openInstagramPicker(for: instagramURL)
    }
    private func openInstagramPicker(for rawURL: String) {
        let requestedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: requestedURL), InstagramCommand.username(for: requestedURL) != nil else { return }
        pendingInstagramURL = url.absoluteString
        storyItems = []; selectedStoryIDs = []; storyError = ""; loadingStories = !manager.instagramSessionUsername.isEmpty; showStoryPicker = true
        guard !manager.instagramSessionUsername.isEmpty else {
            storyError = "Conecte sua conta do Instagram antes de listar Stories."
            return
        }
        manager.loadInstagramStories(url: requestedURL) { items, error in
            storyItems = items
            let requestedID = InstagramCommand.storyID(for: requestedURL)
            selectedStoryIDs = requestedID.map { Set([$0]) } ?? Set(items.map(\.id))
            storyError = error ?? ""
            loadingStories = false
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Usar esta pasta"; panel.directoryURL = URL(fileURLWithPath: NSString(string: directory).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url { directory = url.path }
    }
}

private struct EmptyDownloads: View {
    let symbol: String
    let title: String
    let subtitle: String
    var action: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.secondary).padding(.bottom, 6)
            Text(title).font(.system(size: 19, weight: .semibold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            Button("Adicionar links", systemImage: "plus", action: action).modifier(GlassAction()).controlSize(.large).padding(.top, 6)
        }.frame(maxWidth: .infinity).padding(.vertical, 76)
    }
}

private struct JobRow: View {
    let job: DownloadJob
    let cancel: () -> Void
    private var formatLabel: String {
        if !job.file.isEmpty { return URL(fileURLWithPath: job.file).pathExtension.uppercased() }
        return ["auto", "best"].contains(job.options.container) ? "Original" : job.options.container.uppercased()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: job.options.kind == .audio ? "music.note" : "play.rectangle")
                .font(.system(size: 22, weight: .regular)).foregroundStyle(.secondary)
                .frame(width: 48, height: 48).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 7) {
                Text(job.title.isEmpty ? job.url : job.title).font(.system(size: 13, weight: .medium)).lineLimit(1).help(job.url)
                HStack(spacing: 7) {
                    Text(formatLabel)
                    Text("·")
                    Text(job.status)
                    if !job.speed.isEmpty && job.isActive { Text("· \(job.speed)") }
                    if !job.eta.isEmpty && job.isActive { Text("· \(job.eta) restantes") }
                }.font(.system(size: 11)).foregroundStyle(job.status == "Falhou" ? .orange : .secondary)
                if job.isActive {
                    HStack { ProgressView(value: job.progress, total: 100).tint(.accentColor); Text("\(Int(job.progress))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 36) }
                }
                if job.status == "Falhou" { Text(job.error).font(.system(size: 12)).foregroundStyle(.orange).lineLimit(3).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if job.isActive || job.status == "Na fila" {
                Button(action: cancel) { Image(systemName: "xmark").frame(width: 28, height: 28) }.buttonStyle(.borderless).help("Cancelar download").accessibilityLabel("Cancelar download")
            } else if job.status == "Concluído" {
                Button {
                    if !job.file.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: job.file)]) }
                    else { NSWorkspace.shared.open(URL(fileURLWithPath: job.directory)) }
                } label: { Image(systemName: "folder").frame(width: 28, height: 28) }.buttonStyle(.borderless).help("Mostrar no Finder").accessibilityLabel("Mostrar no Finder")
            }
        }.padding(.vertical, 16)
    }
}

private struct InstagramLoginSheet: View {
    @ObservedObject var manager: DownloadManager
    let close: () -> Void
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsTwoFactor = false
    @State private var busy = false
    @State private var error = ""

    private var canSubmit: Bool {
        needsTwoFactor ? !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var checkpointURL: URL? {
        guard let start = error.range(of: "/auth_platform/") else { return nil }
        let suffix = error[start.lowerBound...]
        let end = suffix.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\r" }) ?? suffix.endIndex
        return URL(string: "https://www.instagram.com" + suffix[..<end])
    }

    private var loginErrorTitle: String {
        checkpointURL == nil ? "Não foi possível conectar" : "O Instagram pediu uma verificação"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Conectar Instagram").font(.system(size: 24, weight: .semibold))
                    Text(needsTwoFactor ? "Digite o código enviado pelo Instagram." : "A conexão é feita diretamente pelo Instaloader.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancelar", action: close).keyboardShortcut(.cancelAction)
            }
            if needsTwoFactor {
                TextField("Código de autenticação", text: $code).textFieldStyle(.roundedBorder).font(.system(size: 14))
                    .onSubmit { submit() }
            } else {
                TextField("Usuário do Instagram", text: $username).textFieldStyle(.roundedBorder).font(.system(size: 14))
                SecureField("Senha", text: $password).textFieldStyle(.roundedBorder).font(.system(size: 14))
            }
            if !error.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(loginErrorTitle, systemImage: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let checkpointURL {
                        Button("Copiar link de verificação") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(checkpointURL.absoluteString, forType: .string)
                        }.buttonStyle(.borderless).font(.system(size: 12, weight: .medium))
                    }
                }
            }
            Text("A senha é enviada apenas ao processo local do Instaloader para autenticar. Depois, o app guarda somente o arquivo de sessão local com permissões restritas.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(needsTwoFactor ? "Confirmar código" : "Entrar", action: submit)
                    .modifier(GlassAction(prominent: true)).disabled(!canSubmit || busy)
            }
        }
        .padding(28).frame(width: 520).preferredColorScheme(.dark)
    }

    private func submit() {
        error = ""; busy = true
        if needsTwoFactor {
            manager.submitInstagramTwoFactor(code: code) { result in
                if case .failed(let message) = result { error = message; busy = false }
            }
        } else {
            manager.loginInstagram(username: username, password: password) { result in
                switch result {
                case .twoFactorRequired: needsTwoFactor = true; busy = false
                case .authenticated: password = ""; busy = false; close()
                case .failed(let message): error = message; busy = false
                }
            }
        }
    }
}

private struct InstagramStoryPickerSheet: View {
    let stories: [InstagramStory]
    @Binding var selectedIDs: Set<String>
    let loading: Bool
    let error: String
    let cancel: () -> Void
    let download: () -> Void
    private var allSelected: Bool { !stories.isEmpty && selectedIDs.count == stories.count }

    private func storyDate(_ story: InstagramStory) -> String {
        let date = Date(timeIntervalSince1970: story.timestamp)
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Escolha os Stories").font(.system(size: 24, weight: .semibold))
                    Text("Marque somente as mídias que deseja salvar no Mac.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancelar", action: cancel).keyboardShortcut(.cancelAction)
            }
            if loading {
                VStack(spacing: 14) { ProgressView(); Text("Buscando Stories disponíveis…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !error.isEmpty && stories.isEmpty {
                ContentUnavailableView("Não foi possível listar os Stories", systemImage: "camera.slash", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(stories.count) \(stories.count == 1 ? "Story disponível" : "Stories disponíveis")")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button(allSelected ? "Desmarcar todos" : "Selecionar todos") {
                        selectedIDs = allSelected ? [] : Set(stories.map(\.id))
                    }.buttonStyle(.borderless).font(.system(size: 12))
                }
                List(stories) { story in
                    Toggle(isOn: Binding(get: { selectedIDs.contains(story.id) }, set: { checked in
                        if checked { selectedIDs.insert(story.id) } else { selectedIDs.remove(story.id) }
                    })) {
                        HStack(spacing: 12) {
                            Image(systemName: story.kind == "Vídeo" ? "video" : "photo")
                                .frame(width: 30, height: 30).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(story.kind).font(.system(size: 13, weight: .medium))
                                Text(storyDate(story)).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(story.shortcode).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.checkbox).padding(.vertical, 5)
                }.listStyle(.inset)
                HStack {
                    if !error.isEmpty { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange) }
                    Spacer()
                    Button("Baixar \(selectedIDs.count) selecionado\(selectedIDs.count == 1 ? "" : "s")", action: download)
                        .modifier(GlassAction(prominent: true)).disabled(selectedIDs.isEmpty)
                }
            }
        }
        .padding(28).frame(width: 640, height: 540).preferredColorScheme(.dark)
    }
}

private struct FormatsSheet: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selection: String?
    let choose: (SourceFormat) -> Void
    private var filtered: [SourceFormat] {
        manager.formats.filter { search.isEmpty || "\($0.id) \($0.ext) \($0.resolution) \($0.videoCodec) \($0.audioCodec)".localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Text("Formatos do link").font(.system(size: 24, weight: .semibold)); Text(manager.formatTitle.isEmpty ? "Todas as opções fornecidas pelo site." : manager.formatTitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if manager.loadingFormats {
                VStack(spacing: 16) { ProgressView(); Text("Consultando resoluções, formatos e codecs…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !manager.formatError.isEmpty {
                ContentUnavailableView("Não foi possível consultar", systemImage: "exclamationmark.triangle", description: Text(manager.formatError))
            } else {
                TextField("Buscar resolução, codec, formato ou ID", text: $search).textFieldStyle(.roundedBorder)
                Table(filtered, selection: $selection) {
                    TableColumn("ID", value: \.id).width(70)
                    TableColumn("Formato") { Text($0.ext.uppercased()) }.width(70)
                    TableColumn("Resolução", value: \.resolution).width(130)
                    TableColumn("Vídeo", value: \.videoCodec)
                    TableColumn("Áudio", value: \.audioCodec)
                    TableColumn("Tamanho") { format in Text(format.filesize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—") }.width(85)
                }
                HStack {
                    Text("Vídeo sem áudio recebe a melhor faixa de áudio disponível.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Usar formato") { if let format = manager.formats.first(where: { $0.id == selection }) { choose(format); dismiss() } }
                        .modifier(GlassAction(prominent: true)).disabled(selection == nil)
                }
            }
        }.padding(28).frame(width: 920, height: 620).preferredColorScheme(.dark)
    }
}
