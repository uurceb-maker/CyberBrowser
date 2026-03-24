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

                    ageGatePage
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack(spacing: 12) {
                    if page > 0 {
                        Button("Geri") {
                            moveToPage(max(page - 1, 0))
                        }
                        .buttonStyle(.bordered)
                        .tint(.white.opacity(0.25))
                    }

                    Spacer()

                    Button(page == 3 ? "Basla" : "Ileri") {
                        if page < 3 {
                            moveToPage(min(page + 1, 3))
                        } else if isAgeAccepted {
                            completeOnboarding()
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
        .onAppear {
            isAgeAccepted = ageGateConfirmed
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

    private var ageGatePage: some View {
        VStack(spacing: 18) {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundColor(.cyberYellow)

                Text("Yas Dogrulama")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.cyberWhite)

                Text("Uygulamayi kullanmak icin en az 17 yasinda oldugunuzu onaylamaniz gerekir.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.cyberMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.cyberYellow.opacity(0.24), lineWidth: 1)
            )

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    isAgeAccepted.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isAgeAccepted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isAgeAccepted ? .cyberGreen : .cyberMuted)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("17+ oldugumu onayliyorum")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.cyberWhite)

                        Text("Onay verdikten sonra uygulamaya devam edebilirsiniz.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.cyberMuted)
                    }

                    Spacer()
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isAgeAccepted ? Color.cyberGreen.opacity(0.55) : Color.cyberYellow.opacity(0.2),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)

            if !isAgeAccepted {
                Text("Devam etmek icin once onay kutusunu etkinlestirin.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.cyberRed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func moveToPage(_ newPage: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            page = newPage
        }
    }

    private func completeOnboarding() {
        ageGateConfirmed = true
        onboardingCompleted = true
    }
}

#Preview {
    OnboardingView()
}
