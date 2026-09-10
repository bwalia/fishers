import SwiftUI
import CoreImage.CIFilterBuiltins
import AVFoundation

/// The club's own code, big enough to be scanned across a table at the toss.
struct ClubQRView: View {
    let club: Club

    @State private var code: ClubQRCode?
    @State private var teams: [Team] = []
    @State private var selectedTeamId: UUID?
    @State private var teamCode: ClubQRCode?
    @State private var isRotating = false
    @State private var message: String?

    private var shown: ClubQRCode? { selectedTeamId == nil ? code : teamCode }

    var body: some View {
        List {
            Section {
                if let shown {
                    VStack(spacing: 14) {
                        QRImage(payload: shown.payload)
                            .frame(width: 240, height: 240)
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color.secondary.opacity(0.2))
                            )
                        Text(shown.identity.displayName)
                            .font(FishersTheme.headline)
                        Text("Show this to the other captain. They scan it when they start the match.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("QR code for \(shown.identity.displayName)")
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }

            if !teams.isEmpty {
                Section("Which side") {
                    Picker("Side", selection: $selectedTeamId) {
                        Text(club.name).tag(UUID?.none)
                        ForEach(teams) { team in
                            Text(team.name).tag(UUID?.some(team.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }

            if let shown {
                Section {
                    ShareLink(item: shown.payload) {
                        Label("Share the link", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = shown.payload
                        message = "Copied."
                    } label: {
                        Label("Copy the link", systemImage: "doc.on.doc")
                    }
                } footer: {
                    Text(shown.payload)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await rotate() }
                } label: {
                    if isRotating {
                        HStack { ProgressView(); Text("Minting a new code…") }
                    } else {
                        Label("Retire this code", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isRotating)
            } footer: {
                Text("Only if it has been shared too widely. The old code stops working immediately.")
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .fishersList()
        .navigationTitle("Club QR code")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: selectedTeamId) { _, _ in Task { await loadTeamCode() } }
    }

    private func load() async {
        code = try? await FishersAPI.clubQRCode(clubId: club.id)
        teams = (try? await FishersAPI.teams(clubId: club.id)) ?? []
    }

    private func loadTeamCode() async {
        guard let teamId = selectedTeamId else { return }
        teamCode = try? await FishersAPI.teamQRCode(teamId: teamId)
    }

    private func rotate() async {
        isRotating = true
        defer { isRotating = false }
        do {
            code = try await FishersAPI.rotateClubQRCode(clubId: club.id)
            selectedTeamId = nil
            message = "New code minted. The old one no longer works."
        } catch {
            message = error.localizedDescription
        }
    }
}

/// A QR code drawn on the device — no network, so it works at a ground with no
/// signal, which is exactly where it is needed.
struct QRImage: View {
    let payload: String

    var body: some View {
        if let image = render() {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private func render() -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        // Medium correction: readable even with a thumb over a corner.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Point the camera at the other club's code.
struct QRScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void
    var onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFound: onFound, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onFound: (String) -> Void
        let onFailure: (String) -> Void
        private var hasFound = false

        init(onFound: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onFound = onFound
            self.onFailure = onFailure
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput objects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            // One reading is enough; a QR code in view fires many times a second.
            guard !hasFound,
                  let object = objects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue
            else { return }
            hasFound = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onFound(value)
        }
    }

    final class ScannerController: UIViewController {
        var coordinator: Coordinator?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configure()
        }

        private func configure() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                coordinator?.onFailure("No camera available on this device.")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                coordinator?.onFailure("Could not start the camera.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.layer.bounds
            view.layer.addSublayer(layer)
            preview = layer

            Task.detached { [session] in
                session.startRunning()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.layer.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.stopRunning()
        }
    }
}
