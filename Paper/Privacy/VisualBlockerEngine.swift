import Foundation
import WebKit

/// Paper-owned DOM replacement, separate from content rules and cosmetic CSS.
/// Only fixed selectors and an exact sponsored label can classify a candidate.
enum VisualBlockerEngine {
    static let messageName = "paperVisualBlocker"
    static let maximumCandidatesPerBatch = 160
    static let maximumOverlaysPerPage = 24
    static let teardown = "window.__paperVisualBlocker?.stop()"

    static let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)

    private static let source = #"""
    (() => {
      if (window.__paperVisualBlocker || location.hostname === 'www.youtube.com' || location.hostname === 'youtube.com') return;
      const selectors = 'ins.adsbygoogle,[data-ad-slot],[data-testid="adBanner-wrapper"],shreddit-ad-post,[data-ad-interstitial],#ad-interstitial,[data-ad-label="Advertisement"]';
      const maxCandidates = 160, maxOverlays = 24, maxNodes = 2500, maxBatches = 120;
      const managed = new Map();
      const queue = new Set();
      let timer = 0, scanned = 0, replaced = 0, collapsed = 0, elapsed = 0, budgetExceeded = 0, batches = 0, stopped = false;
      const report = () => {
        try { window.webkit.messageHandlers.paperVisualBlocker.postMessage({scanned, replaced, collapsed, elapsed, budgetExceeded}); } catch (_) {}
      };
      const excluded = element => !!element.closest('dialog,[role="dialog"],[aria-modal="true"],form,[data-paper-blocked],.paper-blocked-slot');
      const classify = element => {
        if (element.hasAttribute('data-paper-blocked') || excluded(element)) return false;
        const tag = element.tagName.toLowerCase();
        if (tag === 'video' || tag === 'form' || tag === 'dialog') return false;
        const css = getComputedStyle(element);
        if (css.display === 'none' || css.visibility === 'hidden') return false;
        const rect = element.getBoundingClientRect();
        if (rect.width < 80 || rect.height < 35 || rect.width * rect.height > 1500000) return false;
        if (element.matches('ins.adsbygoogle,[data-ad-slot],[data-testid="adBanner-wrapper"],[data-ad-interstitial],#ad-interstitial,[data-ad-label="Advertisement"]')) return true;
        if (tag === 'shreddit-ad-post') {
          const label = element.querySelector('[aria-label], [data-testid="sponsored-label"], .sponsored');
          return !!label && /^(sponsored|promoted|advertisement)$/i.test((label.getAttribute('aria-label') || label.textContent || '').trim());
        }
        return false;
      };
      const replace = element => {
        if (replaced >= maxOverlays || !classify(element)) return;
        const height = Math.ceil(element.getBoundingClientRect().height);
        const width = Math.ceil(element.getBoundingClientRect().width);
        const oldStyle = element.getAttribute('style');
        const isInterstitial = element.matches('[data-ad-interstitial],#ad-interstitial') &&
          getComputedStyle(element).position === 'fixed' && width >= innerWidth * .8 && height >= innerHeight * .8;
        let releasedScrollLock = null;
        const original = document.createElement('span');
        original.setAttribute('data-paper-original', '');
        original.style.setProperty('display', 'none', 'important');
        while (element.firstChild) original.appendChild(element.firstChild);
        const slot = document.createElement('div');
        slot.className = 'paper-blocked-slot';
        slot.setAttribute('role', 'status');
        slot.setAttribute('aria-label', 'Blocked by Paper');
        slot.style.cssText = 'box-sizing:border-box;display:flex;align-items:flex-start;justify-content:space-between;width:100%;min-height:' + height + 'px;padding:9px 12px;background:rgba(130,130,130,.09);color:inherit;font:12px -apple-system,BlinkMacSystemFont,sans-serif;';
        const label = document.createElement('span'); label.textContent = 'Blocked by Paper';
        const close = document.createElement('button');
        close.type = 'button'; close.textContent = '×';
        close.setAttribute('aria-label', 'Collapse blocked content');
        close.style.cssText = 'border:0;background:transparent;color:inherit;font:18px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1;cursor:pointer;';
        close.addEventListener('click', event => {
          event.stopPropagation(); event.preventDefault();
          if (document.activeElement === close) close.blur();
          element.style.setProperty('display', 'none', 'important');
          if (isInterstitial && element.parentElement === document.body &&
              document.body.style.overflow === 'hidden' &&
              !document.querySelector('dialog[open],[role="dialog"],[aria-modal="true"]')) {
            releasedScrollLock = document.body.style.getPropertyValue('overflow');
            document.body.style.removeProperty('overflow');
            const state = managed.get(element); if (state) state.releasedScrollLock = releasedScrollLock;
          }
          collapsed += 1; report();
        });
        slot.append(label, close);
        element.append(original, slot);
        element.setAttribute('data-paper-blocked', 'true');
        element.style.setProperty('min-height', height + 'px', 'important');
        element.style.setProperty('min-width', width + 'px', 'important');
        managed.set(element, {original, slot, oldStyle, releasedScrollLock});
        replaced += 1;
      };
      const inspect = (root, budget) => {
        if (!root || root.nodeType !== 1 || root.closest('[data-paper-blocked],.paper-blocked-slot')) return;
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
        let element = root;
        while (element && budget.nodes < maxNodes && budget.candidates < maxCandidates && replaced < maxOverlays) {
          budget.nodes += 1;
          if (element.matches(selectors) && !element.closest('[data-paper-blocked],.paper-blocked-slot')) {
            budget.candidates += 1; scanned += 1; replace(element);
          }
          element = walker.nextNode();
        }
        if (element && (budget.nodes >= maxNodes || budget.candidates >= maxCandidates)) budgetExceeded += 1;
      };
      const flush = () => {
        timer = 0;
        if (++batches > maxBatches) {
          budgetExceeded += 1; queue.clear(); observer.disconnect(); report(); return;
        }
        const start = performance.now();
        let batch = 0;
        const budget = {nodes: 0, candidates: 0};
        for (const root of queue) {
          queue.delete(root);
          if (++batch > 32 || budget.nodes >= maxNodes || budget.candidates >= maxCandidates || replaced >= maxOverlays) {
            budgetExceeded += 1; break;
          }
          inspect(root, budget);
        }
        queue.clear(); elapsed += performance.now() - start; report();
      };
      const observer = new MutationObserver(records => {
        if (stopped || replaced >= maxOverlays) return;
        for (const record of records) {
          for (const node of record.addedNodes) {
            if (node.nodeType === 1 && queue.size < 32 && !node.closest('[data-paper-blocked],.paper-blocked-slot')) queue.add(node);
          }
        }
        if (queue.size && !timer) timer = setTimeout(flush, 80);
      });
      window.__paperVisualBlocker = {stop() {
        stopped = true; observer.disconnect(); clearTimeout(timer); queue.clear();
        for (const [element, state] of managed) {
          if (!element.isConnected) continue;
          state.slot.remove();
          while (state.original.firstChild) element.insertBefore(state.original.firstChild, state.original);
          state.original.remove();
          element.removeAttribute('data-paper-blocked');
          if (state.oldStyle === null) element.removeAttribute('style'); else element.setAttribute('style', state.oldStyle);
          if (state.releasedScrollLock && document.body && !document.body.style.overflow) {
            document.body.style.setProperty('overflow', state.releasedScrollLock);
          }
        }
        managed.clear(); delete window.__paperVisualBlocker;
      }};
      if (document.documentElement) {
        queue.add(document.documentElement); flush();
        observer.observe(document.documentElement, {childList:true, subtree:true});
      }
    })();
    """#
}
