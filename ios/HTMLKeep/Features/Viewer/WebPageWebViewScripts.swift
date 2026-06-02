import Foundation
import CryptoKit

extension WebPageWebView {
    static func runtimeStorageScript(projectFolderURL: URL) -> String {
        let bootstrap = WebPageRuntimeStorage.localStorageBootstrapState(in: projectFolderURL)
        let itemsData = (try? JSONSerialization.data(withJSONObject: bootstrap.items, options: [.sortedKeys])) ?? Data("{}".utf8)
        let itemsJSON = String(data: itemsData, encoding: .utf8) ?? "{}"
        let hasSnapshot = bootstrap.hasSnapshot ? "true" : "false"
        let snapshotVersion = Self.javascriptSingleQuotedEscaped(Self.sha256HexDigest(for: itemsData))
        let messageName = WebPageRuntimeStorage.localStorageMessageName

        return #"""
        (function() {
            if (window.__htmlAnywhereRuntimeStorageInstalled) {
                return;
            }
            window.__htmlAnywhereRuntimeStorageInstalled = true;

            var hasSnapshot = \#(hasSnapshot);
            var initialItems = \#(itemsJSON);
            var snapshotVersion = '\#(snapshotVersion)';
            var sessionSnapshotKey = '__htmlAnywhereLocalStorageSnapshotVersion';

            function restoreLocalStorage() {
                try {
                    if (!hasSnapshot || sessionStorage.getItem(sessionSnapshotKey) === snapshotVersion) {
                        return;
                    }
                    if (hasSnapshot) {
                        localStorage.clear();
                    }
                    Object.keys(initialItems || {}).forEach(function(key) {
                        var value = initialItems[key];
                        if (typeof value === 'string' && localStorage.getItem(key) !== value) {
                            localStorage.setItem(key, value);
                        }
                    });
                    sessionStorage.setItem(sessionSnapshotKey, snapshotVersion);
                } catch (error) {}
            }

            function collectLocalStorage() {
                try {
                    var items = {};
                    for (var index = 0; index < localStorage.length; index += 1) {
                        var key = localStorage.key(index);
                        if (key !== null) {
                            items[key] = localStorage.getItem(key) || '';
                        }
                    }
                    window.webkit.messageHandlers.\#(messageName).postMessage({ items: items });
                } catch (error) {}
            }

            var captureTimer = null;
            function scheduleCapture() {
                if (captureTimer !== null) {
                    clearTimeout(captureTimer);
                }
                captureTimer = setTimeout(function() {
                    captureTimer = null;
                    collectLocalStorage();
                }, 250);
            }

            window.__htmlAnywhereCaptureLocalStorage = collectLocalStorage;
            restoreLocalStorage();

            try {
                var originalSetItem = Storage.prototype.setItem;
                var originalRemoveItem = Storage.prototype.removeItem;
                var originalClear = Storage.prototype.clear;

                Storage.prototype.setItem = function() {
                    var result = originalSetItem.apply(this, arguments);
                    if (this === window.localStorage) {
                        scheduleCapture();
                    }
                    return result;
                };

                Storage.prototype.removeItem = function() {
                    var result = originalRemoveItem.apply(this, arguments);
                    if (this === window.localStorage) {
                        scheduleCapture();
                    }
                    return result;
                };

                Storage.prototype.clear = function() {
                    var result = originalClear.apply(this, arguments);
                    if (this === window.localStorage) {
                        scheduleCapture();
                    }
                    return result;
                };
            } catch (error) {}

            window.addEventListener('pagehide', collectLocalStorage);
            document.addEventListener('visibilitychange', function() {
                if (document.visibilityState === 'hidden') {
                    collectLocalStorage();
                }
            });
            setTimeout(collectLocalStorage, 0);
        })();
        """#
    }

    static func scrollMetricsScript(messageName: String) -> String {
        let messageName = javascriptSingleQuotedEscaped(messageName)

        return #"""
        (function() {
            if (window.__htmlAnywhereScrollMetricsInstalled) {
                return;
            }
            window.__htmlAnywhereScrollMetricsInstalled = true;

            var messageName = '\#(messageName)';
            var animationFrame = null;
            var lastScrollableElement = null;

            function internalScrollableElement(target) {
                if (!target || target === window || target === document || target.nodeType !== 1) {
                    return null;
                }

                var rootScroller = document.scrollingElement || document.documentElement || document.body;
                if (target === rootScroller || target === document.documentElement || target === document.body) {
                    return null;
                }

                var canScrollVertically = target.scrollHeight > target.clientHeight + 1;
                return canScrollVertically && typeof target.scrollTop === 'number' ? target : null;
            }

            function postScrollMetrics() {
                animationFrame = null;
                var element = internalScrollableElement(lastScrollableElement);
                if (!element) {
                    lastScrollableElement = null;
                    return;
                }
                var offsetY = Math.max(Number(element.scrollTop) || 0, 0);
                try {
                    var handlers = window.webkit && window.webkit.messageHandlers;
                    if (handlers && handlers[messageName]) {
                        handlers[messageName].postMessage({ offsetY: offsetY });
                    }
                } catch (error) {}
            }

            function scheduleScrollMetrics(event) {
                var element = event && event.target ? internalScrollableElement(event.target) : null;
                if (!element) {
                    return;
                }
                lastScrollableElement = element;
                if (animationFrame !== null) {
                    return;
                }
                if (typeof window.requestAnimationFrame === 'function') {
                    animationFrame = window.requestAnimationFrame(postScrollMetrics);
                } else {
                    animationFrame = window.setTimeout(postScrollMetrics, 16);
                }
            }

            window.addEventListener('scroll', scheduleScrollMetrics, true);
            document.addEventListener('scroll', scheduleScrollMetrics, true);
        })();
        """#
    }

    static func topOverlayPreferenceScript(messageName: String) -> String {
        let messageName = javascriptSingleQuotedEscaped(messageName)

        return #"""
        (function() {
            if (window.__htmlAnywhereTopOverlayPreferenceInstalled) {
                return;
            }
            window.__htmlAnywhereTopOverlayPreferenceInstalled = true;

            var messageName = '\#(messageName)';
            var lastPreference = null;
            var pendingTimer = null;

            function numericTop(value) {
                if (!value || value === 'auto') {
                    return null;
                }
                var number = Number.parseFloat(value);
                return Number.isFinite(number) ? number : null;
            }

            function visiblePinnedElement(element, style) {
                if (!element || element === document.documentElement || element === document.body) {
                    return false;
                }
                if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') {
                    return false;
                }

                var rect = element.getBoundingClientRect();
                if (rect.width < 24 || rect.height < 16) {
                    return false;
                }

                var viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
                if (viewportWidth > 0 && rect.width < Math.min(viewportWidth * 0.35, 240)) {
                    return false;
                }

                return true;
            }

            function hasTopPinnedElement() {
                if (!document.body || typeof window.getComputedStyle !== 'function') {
                    return false;
                }

                var elements = document.body.getElementsByTagName('*');
                for (var index = 0; index < elements.length; index += 1) {
                    var element = elements[index];
                    var style = window.getComputedStyle(element);
                    var position = style.position;
                    if (position !== 'sticky' && position !== '-webkit-sticky' && position !== 'fixed') {
                        continue;
                    }

                    var top = numericTop(style.top);
                    if (top === null || top > 1) {
                        continue;
                    }

                    if (visiblePinnedElement(element, style)) {
                        return true;
                    }
                }

                return false;
            }

            function postPreference(force) {
                pendingTimer = null;
                var nextPreference = hasTopPinnedElement();
                if (!force && nextPreference === lastPreference) {
                    return;
                }
                lastPreference = nextPreference;
                try {
                    var handlers = window.webkit && window.webkit.messageHandlers;
                    if (handlers && handlers[messageName]) {
                        handlers[messageName].postMessage({ prefersTopSafeArea: nextPreference });
                    }
                } catch (error) {}
            }

            function schedulePreferencePost(force) {
                if (pendingTimer !== null) {
                    window.clearTimeout(pendingTimer);
                }
                pendingTimer = window.setTimeout(function() {
                    postPreference(force);
                }, 80);
            }

            schedulePreferencePost(true);
            window.setTimeout(function() { schedulePreferencePost(false); }, 300);
            window.setTimeout(function() { schedulePreferencePost(false); }, 1000);
            window.addEventListener('load', function() { schedulePreferencePost(false); }, { once: true });
            window.addEventListener('resize', function() { schedulePreferencePost(false); });

            if (typeof MutationObserver !== 'undefined') {
                var observer = new MutationObserver(function() {
                    schedulePreferencePost(false);
                });
                observer.observe(document.documentElement, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    attributeFilter: ['class', 'style', 'hidden']
                });
            }
        })();
        """#
    }

    private static func sha256HexDigest(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func javascriptSingleQuotedEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

}
