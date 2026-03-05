import Foundation

enum PrivacyPolicy {
    static let turkish: String = """
    # Gizlilik Politikasi (TR)

    CyberBrowser sifir kayit (no-log) yaklasimini benimser.

    - Gezinme gecmisi sunuculara gonderilmez.
    - Uygulama ici reklam engelleme cihazda calisir.
    - Ucuncu taraf analytics veya crash SDK'si kullanilmaz.
    - Proxy ayarlari yalnizca kullanicinin cihazinda saklanir.
    """

    static let english: String = """
    # Privacy Policy (EN)

    CyberBrowser follows a zero-log approach.

    - Browsing history is not uploaded to remote servers.
    - Ad-blocking logic runs on-device.
    - No third-party analytics or crash SDK is included.
    - Proxy configuration is stored locally on the user device only.
    """
}
