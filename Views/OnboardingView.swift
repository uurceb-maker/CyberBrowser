import SwiftUI

struct OnboardingView: View {
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("ageGateConfirmed") private var ageGateConfirmed = false

    @State private var page = 0
    @State private var isAgeAccepted = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.cyberBlack.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                TabView(selection: $page) {
                    onboardingCard(
                        title: "Reklamsiz gezin",
                        subtitle: "WKContentRuleList ile sayfa ici reklamlar ve trackerlar engellenir.",
                        systemImage: "shield.lefthalf.filled"
                    )
                    .tag(0)

                    onboardingCard(
                        title: "Gizliliginiz bizde",
                        subtitle: "No-Log yaklasimi ile gezinme verileri cihaz disina aktarilmaz.",
                        systemImage: "lock.shield"
                    )
                    .tag(1)

                    onboardingCard(
                        title: "Sinirsiz erisim",
                        subtitle: "Proxy altyapisi ile baglanti yonetimi uygulama icinden yapilir.",
                        systemImage: "globe"
                    )
                    .tag(2)

                    VStack(spacing: 14) {
                        onboardingCard(
                            title: "Yas Dogrulama",
                            subtitle: "Uygulamayi kullanmak icin en az 17 yasinda olmalisiniz.",
                            systemImage: "checkmark.seal"
                        )

                        Toggle("17+ oldugumu onayliyorum", isOn: $isAgeAccepted)
                            .tint(.cyberYellow)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.cyberWhite)
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack(spacing: 12) {
                    if page > 0 {
                        Button("Geri") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                page -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.25))
                    }

                    Spacer()

                    Button(page == 3 ? "Basla" : "Ileri") {
                        if page < 3 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                page += 1
                            }
                        } else if isAgeAccepted {
                            ageGateConfirmed = true
                            onboardingCompleted = true
                        }
                    }
                    .disabled(page == 3 && !isAgeAccepted)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyberYellow)
                    .foregroundColor(.black)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .padding(.top, 20)
        }
    }

    private func onboardingCard(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.cyberYellow)

            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.cyberWhite)

            Text(subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.cyberMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(26)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.cyberYellow.opacity(0.24), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    OnboardingView()
}
