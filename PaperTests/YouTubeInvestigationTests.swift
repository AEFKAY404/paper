import AppKit
import Foundation
import Testing
import WebKit
@testable import Paper

/// Opt-in, signed-out live diagnostic. This records structure and playback state, not browsing data.
@MainActor
struct YouTubeInvestigationTests {
    @Test func signedOutVideoStructure() async throws {
        guard FileManager.default.fileExists(atPath: "/private/tmp/paper-run-youtube-investigation") else { return }

        let blocker = ContentBlockerEngine()
        blocker.setEnabled(true)
        await blocker.start()
        let session = WebKitSession(websiteDataStore: .nonPersistent(), blocker: blocker)
        let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 1100, height: 750),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = session.webView
        window.orderFront(nil)
        defer { session.close(); window.close() }

        let observePlayerResponses = """
        (() => {
          if (window.__paperFetchObserved) return;
          window.__paperFetchObserved = [];
          const originalFetch = window.fetch;
          window.fetch = async function(...args) {
            const response = await originalFetch.apply(this, args);
            try {
              const input = args[0];
              const url = new URL(input instanceof Request ? input.url : input, location.href);
              if (url.pathname.endsWith('/youtubei/v1/player')) {
                response.clone().json().then(body => {
                  window.__paperFetchObserved.push({
                    placements: Array.isArray(body.adPlacements) ? body.adPlacements.length : null,
                    slots: Array.isArray(body.adSlots) ? body.adSlots.length : null,
                    ads: Array.isArray(body.playerAds) ? body.playerAds.length : null,
                    hasStreamingData: !!body.streamingData,
                    hasVideoDetails: !!body.videoDetails
                  });
                }).catch(() => {});
              }
            } catch (_) {}
            return response;
          };
        })();
        """
        session.webView.configuration.userContentController.addUserScript(
            WKUserScript(source: observePlayerResponses, injectionTime: .atDocumentStart,
                         forMainFrameOnly: true, in: .page))

        var samples: [String] = []
        session.load(URL(string: "https://www.youtube.com/watch?v=trqa3ozcsig")!)
        for second in 0..<33 {
            try await Task.sleep(for: .seconds(1))
            if [5, 12, 19, 25, 31].contains(second) {
                let script = """
                (() => {
                  const player = window.ytInitialPlayerResponse;
                  const video = document.querySelector('video');
                  const api = document.querySelector('#movie_player');
                  window.__paperVideoProbe ??= video;
                  const details = {
                    title: document.title,
                    playerResponsePresent: !!player,
                    videoID: new URL(location.href).searchParams.get('v'),
                    playerResponseKeys: player ? Object.keys(player).filter(key => /ad/i.test(key)) : [],
                    adPlacements: Array.isArray(player?.adPlacements) ? player.adPlacements.length : null,
                    playerAds: Array.isArray(player?.playerAds) ? player.playerAds.length : null,
                    adBreaks: Array.isArray(player?.adBreaks) ? player.adBreaks.length : null,
                    apiAdState: typeof api?.getAdState === 'function' ? api.getAdState() : null,
                    apiResponseAdKeys: typeof api?.getPlayerResponse === 'function' ? Object.keys(api.getPlayerResponse() ?? {}).filter(key => /ad/i.test(key)) : [],
                    apiPlacements: Array.isArray(api?.getPlayerResponse?.()?.adPlacements) ? api.getPlayerResponse().adPlacements.length : null,
                    apiSlots: Array.isArray(api?.getPlayerResponse?.()?.adSlots) ? api.getPlayerResponse().adSlots.length : null,
                    playerFetches: window.__paperFetchObserved ?? [],
                    hasStreamingData: !!player?.streamingData,
                    hasVideoDetails: !!player?.videoDetails,
                    adShowing: !!document.querySelector('.ad-showing'),
                    adContainerCount: document.querySelectorAll('.video-ads,.ytp-ad-module,.ytp-ad-player-overlay').length,
                    videoCount: document.querySelectorAll('video').length,
                    sameVideoElement: video === window.__paperVideoProbe,
                    currentTime: video?.currentTime ?? null,
                    duration: video?.duration ?? null,
                    paused: video?.paused ?? null,
                    readyState: video?.readyState ?? null,
                    mediaSrcHost: (() => { try { return new URL(video?.currentSrc ?? '').hostname } catch { return null } })(),
                    resourceHosts: [...new Set(performance.getEntriesByType('resource').map(item => { try { return new URL(item.name).hostname } catch { return null } }))].filter(Boolean).slice(0, 40)
                  };
                  return JSON.stringify(details);
                })()
                """
                let result = try? await session.webView.evaluateJavaScript(script)
                print("PAPER_YOUTUBE_DIAGNOSTIC at=\(second + 1)s \(result ?? "unavailable")")
                samples.append("at=\(second + 1)s \(result ?? "unavailable")")
            }
        }
        Attachment.record(samples.joined(separator: "\n"), named: "youtube-structure.txt")
        if let image = await session.snapshot(maxWidth: 800) {
            Attachment.record(image, named: "youtube-signed-out.png", as: .png)
        }
        #expect(blocker.isActive)
    }
}
