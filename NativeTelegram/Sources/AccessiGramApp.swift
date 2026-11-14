import SwiftUI

@main
struct AccessiGramNativeApp: App {
    @UIApplicationDelegateAdaptor(SystemNotificationManager.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var service = TelegramService.shared

    var body: some Scene {
        WindowGroup {
            RootScreen()
                .environmentObject(service)
                .environment(\.locale, Locale(identifier: "zh_TW"))
                .task {
                    service.start()
                    SystemNotificationManager.shared.refreshAuthorizationStatus()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        SystemNotificationManager.shared.refreshAuthorizationStatus()
                    }
                }
        }
    }
}

struct RootScreen: View {
    @EnvironmentObject private var service: TelegramService
    var body: some View {
        Group {
            if service.authStage == .ready {
                NativeConversationsView(service: service)
            } else {
                AuthorizationScreen()
            }
        }
        .alert("Telegram 提示", isPresented: Binding(
            get: { !service.errorMessage.isEmpty },
            set: { if !$0 { service.errorMessage = "" } }
        )) {
            Button("確定") { service.errorMessage = "" }
        } message: { Text(service.errorMessage) }
    }
}

struct AuthorizationScreen: View {
    @EnvironmentObject private var service: TelegramService
    @State private var apiID = ""
    @State private var apiHash = ""
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                switch service.authStage {
                case .credentials:
                    Section {
                        TextField("API ID", text: $apiID)
                            .accessibilityLabel("Telegram API ID")
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        SecureField("API Hash", text: $apiHash)
                            .accessibilityLabel("Telegram API Hash")
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("儲存並連線") {
                            service.configure(id: Int(apiID) ?? 0, hash: apiHash)
                        }
                        .disabled(apiID.isEmpty || apiHash.isEmpty)
                    } header: { Text("Telegram 應用程式金鑰") }
                    footer: {
                        Text("第一次登入需在 my.telegram.org 取得自己的 API ID 和 API Hash。金鑰只存放在本機鑰匙圈。")
                    }
                    Link("前往 Telegram API 開發頁面", destination: URL(string: "https://my.telegram.org")!)
                case .phone:
                    Section("以手機號碼登入") {
                        TextField("國際格式手機號碼，例如 +8869…", text: $phone)
                            .accessibilityLabel("手機號碼，含國碼")
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                        Button("取得驗證碼") { service.phone(phone) }
                            .disabled(phone.isEmpty)
                        Button("改用 QR Code 登入") { service.startQR() }
                    }
                case .code:
                    Section("輸入 Telegram 驗證碼") {
                        TextField("驗證碼", text: $code)
                            .accessibilityLabel("Telegram 驗證碼")
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("驗證並登入") { service.code(code) }.disabled(code.isEmpty)
                    }
                case .password:
                    Section("兩步驟驗證密碼") {
                        if !service.passwordHint.isEmpty { Text("提示：\(service.passwordHint)") }
                        SecureField("密碼", text: $password)
                            .accessibilityLabel("兩步驟驗證密碼")
                        Button("登入") { service.password(password) }.disabled(password.isEmpty)
                    }
                case .email:
                    Section("驗證電子郵件") {
                        TextField("電子郵件", text: $email)
                            .accessibilityLabel("驗證電子郵件地址")
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                        Button("繼續") { service.email(email) }
                    }
                case .emailCode:
                    Section("輸入電子郵件驗證碼") {
                        TextField("驗證碼", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("驗證") { service.emailCode(code) }
                    }
                case .qr:
                    Section("使用已登入的 Telegram 掃描") {
                        if !service.qrLink.isEmpty {
                            QRCodeView(content: service.qrLink)
                            Text("在另一台已登入的 Telegram 裝置中，開啟裝置管理並掃描上方的 QR Code。")
                            Button("複製登入連結") {
                                UIPasteboard.general.string = service.qrLink
                                UIAccessibility.post(notification: .announcement, argument: "已複製登入連結")
                            }
                            .accessibilityHint("可供另一台裝置使用")
                        } else {
                            ProgressView("準備 QR Code 中")
                        }
                    }
                case .unknown:
                    Section {
                        ProgressView("正在連線 Telegram…")
                        Button("重新取得登入狀態") { service.command("getAuthorizationState") }
                    }
                case .ready:
                    EmptyView()
                }
            }
            .navigationTitle("Accessi Gram")
        }
    }
}

