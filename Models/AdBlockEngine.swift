import SwiftUI
import WebKit

// MARK: - Ad Block Engine
class AdBlockEngine: ObservableObject {
    @Published var totalBlockedAds: Int = 0
    @Published var isEnabled: Bool = true
    @Published var showBanner: Bool = false
    @Published var lastBlockedDomain: String = ""
    
    // Set for O(1) domain lookups in navigation delegate
    private static let blockedDomainSet: Set<String> = Set(blockedDomains.map { $0.replacingOccurrences(of: "/", with: "") })
    
    // MARK: - Fast Domain Check
    func isBlockedDomain(_ host: String) -> Bool {
        for domain in Self.blockedDomainSet {
            if host.contains(domain) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Blocked Ad Domains (100+)
    static let blockedDomains: [String] = [
        // Google Ads
        "googleads.g.doubleclick.net",
        "pagead2.googlesyndication.com",
        "adservice.google.com",
        "www.googleadservices.com",
        "googleadservices.com",
        "tpc.googlesyndication.com",
        "ad.doubleclick.net",
        "stats.g.doubleclick.net",
        "cm.g.doubleclick.net",
        "securepubads.g.doubleclick.net",
        
        // Facebook / Meta
        "www.facebook.com/tr",
        "connect.facebook.net",
        "pixel.facebook.com",
        "an.facebook.com",
        "staticxx.facebook.com",
        
        // Amazon Ads
        "aax-us-east.amazon-adsystem.com",
        "z-na.amazon-adsystem.com",
        "fls-na.amazon-adsystem.com",
        "aax-us-iad.amazon-adsystem.com",
        
        // Ad Networks
        "ads.pubmatic.com",
        "hbopenbid.pubmatic.com",
        "t.pubmatic.com",
        "image6.pubmatic.com",
        "ads.yahoo.com",
        "advertising.yahoo.com",
        "adtech.yahooinc.com",
        "ad.turn.com",
        "cdn.taboola.com",
        "trc.taboola.com",
        "api.taboola.com",
        "nr.taboola.com",
        "cdn.outbrain.com",
        "amplify.outbrain.com",
        "widgets.outbrain.com",
        "log.outbrain.com",
        "ads.twitter.com",
        "analytics.twitter.com",
        "static.ads-twitter.com",
        "t.co",
        
        // Tracking & Analytics
        "www.google-analytics.com",
        "google-analytics.com",
        "ssl.google-analytics.com",
        "analytics.google.com",
        "bat.bing.com",
        "c.bing.com",
        "clarity.ms",
        "www.clarity.ms",
        "static.hotjar.com",
        "script.hotjar.com",
        "vars.hotjar.com",
        "in.hotjar.com",
        
        // Media Ads
        "imasdk.googleapis.com",
        "s0.2mdn.net",
        "ad.youtube.com",
        "ade.googlesyndication.com",
        
        // Pop-up / Overlay Networks
        "cdn.popin.cc",
        "app.popin.cc",
        "cdn.moengage.com",
        "sdk.moengage.com",
        "cdn.onesignal.com",
        "onesignal.com",
        "cdn.pushwoosh.com",
        "cp.pushwoosh.com",
        "pushnews.io",
        
        // Ad Exchanges
        "ib.adnxs.com",
        "secure.adnxs.com",
        "acdn.adnxs.com",
        "prebid.adnxs.com",
        "ads.rubiconproject.com",
        "fastlane.rubiconproject.com",
        "pixel.rubiconproject.com",
        "ads.openx.net",
        "u.openx.net",
        "rtb.openx.net",
        "c.amazon-adsystem.com",
        "s.amazon-adsystem.com",
        
        // Mobile Ad Networks
        "ads.mopub.com",
        "app.adjust.com",
        "s2s.adjust.com",
        "view.adjust.com",
        "app.appsflyer.com",
        "sdk.appsflyer.com",
        "t.appsflyer.com",
        "conversions.appsflyer.com",
        "cdn.branch.io",
        "api.branch.io",
        "app.link",
        
        // Other Trackers
        "cdn.krxd.net",
        "beacon.krxd.net",
        "usermatch.krxd.net",
        "cdn.segment.com",
        "api.segment.io",
        "cdn.mxpnl.com",
        "decide.mixpanel.com",
        "api-js.mixpanel.com",
        "cr.frontend.weborama.fr",
        "cdn.cookielaw.org",
        "geolocation.onetrust.com",
        "cdn.tt.omtrdc.net",
        "dpm.demdex.net",
        "fast.a]]pmiflyer.com",
        
        // Criteo
        "dis.eu.criteo.com",
        "static.criteo.net",
        "sslwidget.criteo.com",
        "gum.criteo.com",
        
        // Misc
        "adserver.adtechus.com",
        "cdn.districtm.io",
        "match.adsrvr.org",
        "insight.adsrvr.org",
        "platform.linkedin.com",
        "snap.licdn.com",
        "px.ads.linkedin.com"
    ]
    
    // MARK: - Content Blocking JavaScript
    /// Main ad-blocking script that removes ad elements and intercepts requests
    static let adBlockScript: String = """
    (function() {
        'use strict';
        
        // ===== CONFIGURATION =====
        const BLOCKED_DOMAINS = \(blockedDomainsJSON);
        
        const AD_SELECTORS = [
            // Generic ad containers
            '[id*="ad-"]', '[id*="ad_"]', '[id*="ads-"]', '[id*="ads_"]',
            '[class*="ad-container"]', '[class*="ad_container"]',
            '[class*="ad-wrapper"]', '[class*="ad_wrapper"]',
            '[class*="adsbygoogle"]', '[class*="ad-slot"]',
            '[class*="ad-banner"]', '[class*="ad_banner"]',
            '[class*="advertisement"]', '[class*="sponsored"]',
            // Google Ads
            'ins.adsbygoogle', '.adsbygoogle',
            // iFrames from ad networks
            'iframe[src*="doubleclick"]',
            'iframe[src*="googlesyndication"]',
            'iframe[src*="amazon-adsystem"]',
            'iframe[src*="ad."]',
            'iframe[src*="ads."]',
            // Pop-up overlays
            '[class*="popup"]', '[class*="pop-up"]',
            '[class*="overlay-ad"]', '[class*="interstitial"]',
            '[class*="modal-ad"]',
            // Video pre-roll
            '[class*="video-ad"]', '[class*="preroll"]',
            '[class*="ad-video"]', '.ytp-ad-module',
            '.ytp-ad-overlay-container', '.ytp-ad-text-overlay',
            '.video-ads', '.ad-showing',
            // Cookie/consent popups (optional aggressive)
            '[class*="cookie-banner"]', '[class*="consent-banner"]',
            '[id*="cookie-banner"]', '[id*="consent-popup"]'
        ];
        
        let blockedCount = 0;
        
        // ===== ELEMENT REMOVAL =====
        function removeAdElements() {
            let removed = 0;
            AD_SELECTORS.forEach(selector => {
                try {
                    document.querySelectorAll(selector).forEach(el => {
                        if (el && el.parentNode) {
                            el.style.display = 'none';
                            el.remove();
                            removed++;
                        }
                    });
                } catch(e) {}
            });
            
            if (removed > 0) {
                blockedCount += removed;
                reportBlocked(removed);
            }
        }
        
        // ===== NETWORK INTERCEPTION =====
        // Override XMLHttpRequest to block ad requests
        const origXHROpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
            if (isBlockedURL(url)) {
                blockedCount++;
                reportBlocked(1);
                return;
            }
            return origXHROpen.apply(this, arguments);
        };
        
        // Override fetch to block ad requests
        const origFetch = window.fetch;
        window.fetch = function(input, init) {
            const url = typeof input === 'string' ? input : input?.url || '';
            if (isBlockedURL(url)) {
                blockedCount++;
                reportBlocked(1);
                return Promise.reject(new Error('CyberBrowser: Ad blocked'));
            }
            return origFetch.apply(this, arguments);
        };
        
        // Override window.open to block pop-ups
        const origWindowOpen = window.open;
        window.open = function(url) {
            if (!url || isBlockedURL(url)) {
                blockedCount++;
                reportBlocked(1);
                return null;
            }
            return origWindowOpen.apply(this, arguments);
        };
        
        // ===== URL CHECK =====
        function isBlockedURL(url) {
            if (!url) return false;
            const urlLower = url.toLowerCase();
            return BLOCKED_DOMAINS.some(domain => urlLower.includes(domain));
        }
        
        // ===== REPORT TO NATIVE =====
        function reportBlocked(count) {
            try {
                window.webkit.messageHandlers.adBlocked.postMessage({
                    count: count,
                    total: blockedCount,
                    url: window.location.href
                });
            } catch(e) {}
        }
        
        // ===== MUTATION OBSERVER =====
        // Watch for dynamically injected ads
        const observer = new MutationObserver(mutations => {
            let shouldClean = false;
            mutations.forEach(mutation => {
                mutation.addedNodes.forEach(node => {
                    if (node.nodeType === 1) {
                        // Check if the added node matches ad selectors
                        AD_SELECTORS.forEach(selector => {
                            try {
                                if (node.matches && node.matches(selector)) {
                                    node.remove();
                                    blockedCount++;
                                    shouldClean = true;
                                }
                                // Check children
                                if (node.querySelectorAll) {
                                    node.querySelectorAll(selector).forEach(el => {
                                        el.remove();
                                        blockedCount++;
                                        shouldClean = true;
                                    });
                                }
                            } catch(e) {}
                        });
                    }
                });
            });
            if (shouldClean) {
                reportBlocked(0);
            }
        });
        
        observer.observe(document.documentElement, {
            childList: true,
            subtree: true
        });
        
        // ===== STYLE INJECTION =====
        // Hide elements via CSS before they even render
        const cssRules = AD_SELECTORS.map(s => s + ' { display: none !important; visibility: hidden !important; height: 0 !important; overflow: hidden !important; }').join('\\n');
        const style = document.createElement('style');
        style.textContent = cssRules;
        (document.head || document.documentElement).appendChild(style);
        
        // ===== INITIAL CLEANUP =====
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', removeAdElements);
        } else {
            removeAdElements();
        }
        
        // Delayed second cleanup (MutationObserver handles the rest)
        setTimeout(removeAdElements, 2000);
        
        console.log('[CyberBrowser] Ad-block engine initialized');
    })();
    """
    
    // MARK: - Tracker Blocking Script
    static let trackerBlockScript: String = """
    (function() {
        'use strict';
        
        // Block common tracking scripts from loading
        const origCreateElement = document.createElement.bind(document);
        document.createElement = function(tag) {
            const element = origCreateElement(tag);
            if (tag.toLowerCase() === 'script') {
                const origSetAttribute = element.setAttribute.bind(element);
                element.setAttribute = function(name, value) {
                    if (name === 'src' && value) {
                        const blockedPatterns = [
                            'google-analytics', 'googletagmanager',
                            'facebook.net', 'connect.facebook',
                            'hotjar.com', 'clarity.ms',
                            'segment.com', 'mixpanel.com',
                            'amplitude.com', 'fullstory.com',
                            'mouseflow.com', 'crazyegg.com'
                        ];
                        const valLower = value.toLowerCase();
                        if (blockedPatterns.some(p => valLower.includes(p))) {
                            window.webkit.messageHandlers.adBlocked.postMessage({
                                count: 1,
                                total: 0,
                                url: window.location.href
                            });
                            return;
                        }
                    }
                    return origSetAttribute(name, value);
                };
            }
            return element;
        };
        
        console.log('[CyberBrowser] Tracker blocker initialized');
    })();
    """
    
    // MARK: - Video Ad Skip Script (YouTube etc.)
    static let videoAdSkipScript: String = """
    (function() {
        'use strict';
        
        // YouTube specific ad handling
        function skipYouTubeAds() {
            // Skip button
            const skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
            if (skipBtn) {
                skipBtn.click();
                window.webkit.messageHandlers.adBlocked.postMessage({
                    count: 1, total: 0, url: window.location.href
                });
            }
            
            // Remove ad overlays
            const adOverlays = document.querySelectorAll('.ytp-ad-overlay-container, .ytp-ad-text-overlay, .video-ads');
            adOverlays.forEach(el => {
                el.remove();
                window.webkit.messageHandlers.adBlocked.postMessage({
                    count: 1, total: 0, url: window.location.href
                });
            });
            
            // Speed through video ads
            const video = document.querySelector('video');
            const adShowing = document.querySelector('.ad-showing');
            if (video && adShowing) {
                video.currentTime = video.duration || 0;
                video.playbackRate = 16;
            }
        }
        
        // Run periodically for YouTube
        if (window.location.hostname.includes('youtube')) {
            setInterval(skipYouTubeAds, 500);
        }
        
        console.log('[CyberBrowser] Video ad skip initialized');
    })();
    """
    
    // MARK: - Helper
    private static var blockedDomainsJSON: String {
        let data = try! JSONSerialization.data(withJSONObject: blockedDomains, options: [])
        return String(data: data, encoding: .utf8)!
    }
    
    // MARK: - WKUserScript Creation
    func createUserScripts() -> [WKUserScript] {
        guard isEnabled else { return [] }
        
        return [
            WKUserScript(
                source: Self.adBlockScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ),
            WKUserScript(
                source: Self.trackerBlockScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ),
            WKUserScript(
                source: Self.videoAdSkipScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        ]
    }
    
    // MARK: - Handle blocked ad message from JS
    private var bannerHideWorkItem: DispatchWorkItem?
    
    func handleBlockedAd(count: Int, domain: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.totalBlockedAds += max(count, 1)
            self.lastBlockedDomain = domain
            self.showBanner = true
            
            // Cancel previous timer to avoid flicker
            self.bannerHideWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.showBanner = false
                }
            }
            self.bannerHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }
    }
    
    func resetCount() {
        totalBlockedAds = 0
    }
}
