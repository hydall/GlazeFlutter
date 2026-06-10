class VirtualScrollHeightCache {
    constructor(getItemLength, getColumns, estimateHeight) {
        this.getItemLength = getItemLength;
        this.getColumns = getColumns;
        this.estimateHeight = estimateHeight;
        this.itemHeights = new Map();
        this.prefixSumCache = null;
        this.prefixSumDirty = true;
    }

    invalidate() {
        this.prefixSumDirty = true;
    }

    ensure() {
        if (!this.prefixSumDirty && this.prefixSumCache) return this.prefixSumCache;

        const count = this.getItemLength();
        const cols = this.getColumns();
        const sums = [0];

        for (let i = 0; i < count; i += cols) {
            let rowHeight = 0;
            for (let j = 0; j < cols && i + j < count; j++) {
                const h = this.itemHeights.get(i + j) || this.estimateHeight;
                if (h > rowHeight) rowHeight = h;
            }
            sums.push(sums[sums.length - 1] + rowHeight);
        }

        this.prefixSumCache = sums;
        this.prefixSumDirty = false;
        return sums;
    }

    getHeightUpTo(index) {
        const sums = this.ensure();
        const cols = this.getColumns();
        const rowIdx = Math.floor(index / cols);
        return rowIdx < sums.length ? sums[rowIdx] : sums[sums.length - 1];
    }

    getTotalHeight() {
        const sums = this.ensure();
        return sums[sums.length - 1];
    }

    getRenderedContentHeight(start, end) {
        const sums = this.ensure();
        const cols = this.getColumns();
        const startRow = Math.floor(start / cols);
        const endRow = Math.floor(end / cols);
        const s = startRow < sums.length ? sums[startRow] : 0;
        const e = endRow < sums.length ? sums[endRow] : sums[sums.length - 1];
        return e - s;
    }

    setHeight(index, height) {
        if (height > 0 && this.itemHeights.get(index) !== height) {
            this.itemHeights.set(index, height);
            this.invalidate();
        }
    }

    getHeight(index) {
        return this.itemHeights.get(index) || this.estimateHeight;
    }

    hasHeight(index) {
        return this.itemHeights.has(index);
    }

    findRowAtScrollTop(scrollTop) {
        const sums = this.ensure();
        for (let r = 0; r < sums.length - 1; r++) {
            if (sums[r + 1] > scrollTop) return r;
        }
        return -1;
    }

    pruneStale() {
        const count = this.getItemLength();
        for (const key of this.itemHeights.keys()) {
            if (key >= count) this.itemHeights.delete(key);
        }
    }

    shiftKeys(amount, startIndex = 0) {
        const newHeights = new Map();
        for (const [key, height] of this.itemHeights.entries()) {
            if (key >= startIndex) {
                if (key + amount >= 0) {
                    newHeights.set(key + amount, height);
                }
            } else {
                newHeights.set(key, height);
            }
        }
        this.itemHeights = newHeights;
        this.invalidate();
    }

    clear() {
        this.itemHeights.clear();
        this.invalidate();
    }

    computeSpacers(start, end) {
        this.pruneStale();
        const sums = this.ensure();
        const cols = this.getColumns();

        const startRow = Math.floor(start / cols);
        const top = startRow < sums.length ? sums[startRow] : 0;

        let rowStart = end;
        if (cols > 1) {
            rowStart = Math.ceil(end / cols) * cols;
        }
        const endRow = Math.floor(rowStart / cols);
        const totalRows = sums.length - 1;
        const bottom = endRow < totalRows ? sums[totalRows] - sums[Math.min(endRow, totalRows)] : 0;

        return { top, bottom };
    }

    computeTargetTop(renderStart, targetIndex, cols) {
        const alignedIndex = Math.floor(targetIndex / cols) * cols;
        let targetTop = 0;
        for (let i = renderStart; i < alignedIndex; i += cols) {
            let rowHeight = 0;
            for (let j = 0; j < cols && i + j < alignedIndex; j++) {
                const h = this.getHeight(i + j);
                if (h > rowHeight) rowHeight = h;
            }
            targetTop += rowHeight;
        }
        return targetTop;
    }
}

class UseVirtualScroll {
    constructor(container, options = {}) {
        this.container = container;
        this.options = options;
        this.items = [];
        this.itemMap = new Map();
        
        this.getBuffer = () => this.options.buffer ?? 10;
        this.estimateHeight = this.options.estimateHeight ?? 80;
        
        this.renderStart = 0;
        this.renderEnd = 20;
        this.paddingTop = 0;
        this.paddingBottom = 0;
        this.columns = 1;
        
        this.isScrolling = false;
        this.isProgrammaticScrolling = false;
        this.scrollTimeout = null;
        this.scrollRaf = null;
        this.mounted = true;
        
        this.visibleIndices = new Set();
        this.realVisibleIndices = new Set();
        
        this.observer = null;
        this.realObserver = null;
        
        this.cache = new VirtualScrollHeightCache(
            () => this.items.length,
            () => this.columns,
            this.estimateHeight
        );
        
        this.topSpacer = document.createElement('div');
        this.topSpacer.className = 'vl-spacer vl-spacer-top';
        this.bottomSpacer = document.createElement('div');
        this.bottomSpacer.className = 'vl-spacer vl-spacer-bottom';
        this.container.appendChild(this.topSpacer);
        this.container.appendChild(this.bottomSpacer);
        
        this._scrollToBottomPending = false;
        this._pendingScrollToId = null;

        this.initObservers();
        
        this._onContainerScroll = this._onContainerScroll.bind(this);
        this.container.addEventListener('scroll', this._onContainerScroll, { passive: true });
    }

    // --- API parity with VirtualList ---

    clear() {
        this._clearDOM();
        this.items = [];
        this.itemMap.clear();
        this.cache.clear();
        this.renderStart = 0;
        this.renderEnd = 20;
        this.paddingTop = 0;
        this.paddingBottom = 0;
        this.topSpacer.style.height = '0px';
        this.bottomSpacer.style.height = '0px';
    }

    setMessagesBatch(ids, elements) {
        this._clearDOM();
        this.items = [];
        this.itemMap.clear();
        this.cache.clear();
        
        for (let i = 0; i < ids.length; i++) {
            const el = elements[i];
            el.dataset.index = i;
            el.dataset.vlId = ids[i];
            const item = { id: ids[i], el, index: i };
            this.items.push(item);
            this.itemMap.set(ids[i], item);
            this.cache.setHeight(i, this._estimateHeight(el));
        }
        
        this.refresh({ startAtBottom: true });
    }

    append(id, el) {
        if (this.itemMap.has(id)) {
            this.update(id, el);
            return;
        }
        const idx = this.items.length;
        el.dataset.index = idx;
        el.dataset.vlId = id;
        const item = { id, el, index: idx };
        this.items.push(item);
        this.itemMap.set(id, item);
        this.cache.setHeight(idx, this._estimateHeight(el));
        
        this._onItemsChanged('append');
    }

    prepend(id, el) {
        if (this.itemMap.has(id)) {
            this.update(id, el);
            return;
        }
        this.items.unshift({ id, el, index: 0 });
        this.itemMap.set(id, this.items[0]);
        for(let i = 0; i < this.items.length; i++) {
            this.items[i].index = i;
            this.items[i].el.dataset.index = i;
        }
        this.cache.shiftKeys(1);
        this.cache.setHeight(0, this._estimateHeight(el));
        this._onItemsChanged('prepend');
    }

    update(id, el) {
        const item = this.itemMap.get(id);
        if (!item) return;
        el.dataset.index = item.index;
        el.dataset.vlId = id;
        
        const wasInDOM = item.el.parentNode === this.container;
        if (wasInDOM) {
            this.observer.unobserve(item.el);
            this.realObserver.unobserve(item.el);
            this.container.replaceChild(el, item.el);
            this.observer.observe(el);
            this.realObserver.observe(el);
        }
        item.el = el;
        this.cache.setHeight(item.index, 0); // trigger re-measure
    }

    remove(id) {
        const item = this.itemMap.get(id);
        if (!item) return;
        const deletedIndex = item.index;
        
        if (item.el.parentNode === this.container) {
            this.observer.unobserve(item.el);
            this.realObserver.unobserve(item.el);
            item.el.remove();
        }
        this.itemMap.delete(id);
        this.items = this.items.filter(it => it.id !== id);
        for(let i = 0; i < this.items.length; i++) {
            this.items[i].index = i;
            this.items[i].el.dataset.index = i;
        }
        
        this.cache.shiftKeys(-1, deletedIndex + 1);
        
        if (deletedIndex < this.renderStart) {
            this.renderStart = Math.max(0, this.renderStart - 1);
            this.renderEnd = Math.max(0, this.renderEnd - 1);
        } else if (deletedIndex < this.renderEnd) {
            this.renderEnd = Math.max(0, this.renderEnd - 1);
        }
        
        this._onItemsChanged('remove');
    }

    scrollToBottom(behavior = 'auto') {
        const count = this.items.length;
        if (count === 0) return;
        
        let effectiveBehavior = behavior;
        if (this.container.scrollHeight - this.container.scrollTop - this.container.clientHeight > 3000) {
            effectiveBehavior = 'auto';
        }
        
        const vh = this.container.clientHeight || 800;
        const estInView = Math.max(20, Math.ceil(vh / this.estimateHeight) + this.getBuffer());
        
        this.renderStart = Math.max(0, count - estInView);
        this.renderEnd = count;
        this.visibleIndices.clear();
        this.realVisibleIndices.clear();
        this.updateSpacers();
        this.renderDOM();
        
        this.isProgrammaticScrolling = true;
        setTimeout(() => {
            requestAnimationFrame(() => {
                if (!this.mounted) return;
                if (effectiveBehavior === 'smooth') {
                    this.container.scrollTo({ top: this.container.scrollHeight, behavior: 'smooth' });
                    setTimeout(() => { this.isProgrammaticScrolling = false; }, 500);
                } else {
                    this.container.scrollTop = this.container.scrollHeight;
                    setTimeout(() => { 
                        this.container.scrollTop = this.container.scrollHeight;
                        this.isProgrammaticScrolling = false; 
                    }, 150);
                }
            });
        }, 50);
    }

    scrollToTop() {
        this.isProgrammaticScrolling = true;
        this.container.scrollTop = 0;
        setTimeout(() => { this.isProgrammaticScrolling = false; }, 150);
    }

    scrollToMessage(id, highlight = false) {
        const item = this.itemMap.get(id);
        if (!item) return;
        this.scrollToIndex(item.index, 'smooth');
        // Mirror Vue: briefly flash the message the user navigated to (e.g.
        // from a tapped "new message" notification). Wait for scrollToIndex to
        // (re)render the row so the element exists before flashing it.
        if (highlight) setTimeout(() => this.flashMessage(id), 400);
    }

    flashMessage(id) {
        const item = this.itemMap.get(id);
        const el = item && item.el;
        if (!el) return;
        el.classList.remove('message-flash-highlight');
        // Force reflow so re-adding the class restarts the animation.
        void el.offsetWidth;
        el.classList.add('message-flash-highlight');
        setTimeout(() => el.classList.remove('message-flash-highlight'), 2000);
    }

    scrollToIndex(index, behavior = 'auto') {
        const count = this.items.length;
        if (count === 0) return;
        index = Math.max(0, Math.min(index, count - 1));
        
        this.isProgrammaticScrolling = true;
        
        if (index >= this.renderStart && index < this.renderEnd) {
            const item = this.items[index];
            if (item && item.el) {
                const cRect = this.container.getBoundingClientRect();
                const elRect = item.el.getBoundingClientRect();
                const targetTop = this.container.scrollTop + (elRect.top - cRect.top) - (cRect.height / 2) + (elRect.height / 2);
                this.container.scrollTo({ top: Math.max(0, targetTop), behavior });
            }
            setTimeout(() => { this.isProgrammaticScrolling = false; }, behavior === 'smooth' ? 300 : 50);
            return;
        }
        
        let newStart = Math.max(0, index - this.getBuffer());
        let newEnd = Math.min(count, index + this.getBuffer() + 1);
        this.renderStart = newStart;
        this.renderEnd = newEnd;
        this.visibleIndices.clear();
        this.realVisibleIndices.clear();
        this.cache.invalidate();
        this.updateSpacers();
        this.renderDOM();
        
        setTimeout(() => {
            let targetTop = this.paddingTop + this.cache.computeTargetTop(this.renderStart, index, this.columns);
            const itemH = this.cache.getHeight(index);
            targetTop = targetTop - (this.container.clientHeight / 2) + (itemH / 2);
            this.container.scrollTo({ top: Math.max(0, targetTop), behavior });
            setTimeout(() => { this.isProgrammaticScrolling = false; }, behavior === 'smooth' ? 300 : 50);
        }, 50);
    }

    getMessageCount() { return this.items.length; }
    hasMessage(id) { return this.itemMap.has(id); }

    isNearBottom(threshold = 100) {
        const { scrollTop, scrollHeight, clientHeight } = this.container;
        return scrollHeight - scrollTop - clientHeight < threshold;
    }
    isNearTop(threshold = 100) {
        return this.container.scrollTop < threshold;
    }

    pendingScrollToBottom() { this._scrollToBottomPending = true; }
    pendingScrollToMessage(id) { this._pendingScrollToId = id; }

    _estimateHeight(el) {
        if (el.offsetHeight > 0) return el.offsetHeight;
        if (el.classList.contains('date-separator')) return 32;
        const role = el.classList.contains('message-user') ? 'user' :
                     el.classList.contains('message-system') ? 'system' : 'assistant';
        const content = el.querySelector('.message-content');
        if (content && content.shadowRoot) {
            const shadowDiv = content.shadowRoot.querySelector('.glaze-message');
            if (shadowDiv) {
                const textLen = (el.dataset.rawText || '').length;
                const hasCode = shadowDiv.querySelector('pre, .code-block-wrapper');
                const hasImg = shadowDiv.querySelector('img, .janitor-img-wrapper');
                if (hasImg) return 320;
                if (hasCode) return 250;
                if (textLen > 2000) return 500;
                if (textLen > 500) return 250;
                return 120;
            }
        }
        return role === 'system' ? 60 : 120;
    }

    // --- Internal Virtual Scroll Logic ---

    _clearDOM() {
        for (const item of this.items) {
            if (item.el.parentNode === this.container) {
                this.observer.unobserve(item.el);
                this.realObserver.unobserve(item.el);
                item.el.remove();
            }
        }
        this.visibleIndices.clear();
        this.realVisibleIndices.clear();
    }

    _onItemsChanged(type) {
        const newLen = this.items.length;
        this.cache.invalidate();
        this.cache.pruneStale();

        if (type === 'append') {
            const wasAtBottom = this.isNearBottom(100);
            if (wasAtBottom || this._scrollToBottomPending) {
                this.renderEnd = newLen;
                const vh = this.container.clientHeight || 800;
                const estInView = Math.max(20, Math.ceil(vh / this.estimateHeight) + this.getBuffer());
                this.renderStart = Math.max(0, newLen - estInView);
                
                setTimeout(() => {
                    if (this.mounted) this.scrollToBottom('auto');
                }, 50);
            } else {
                if (newLen > this.renderEnd) this.renderEnd = newLen;
            }
        } else if (type === 'prepend') {
            this.renderStart += 1;
            this.renderEnd += 1;
        }
        
        this.updateSpacers();
        this.renderDOM();
        
        if (this._scrollToBottomPending) {
            this._scrollToBottomPending = false;
            this.scrollToBottom('auto');
        }
        if (this._pendingScrollToId) {
            const id = this._pendingScrollToId;
            this._pendingScrollToId = null;
            const item = this.itemMap.get(id);
            if (item) this.scrollToIndex(item.index);
        }
    }

    refresh({ startAtBottom = true } = {}) {
        this.cache.clear();
        this.visibleIndices.clear();
        this.realVisibleIndices.clear();
        const count = this.items.length;
        const vh = this.container.clientHeight || 800;
        const estInView = Math.max(20, Math.ceil(vh / this.estimateHeight) + this.getBuffer());
        if (startAtBottom) {
            this.renderStart = Math.max(0, count - estInView);
            this.renderEnd = count;
        } else {
            this.renderStart = 0;
            this.renderEnd = Math.min(estInView, count);
        }
        this.updateSpacers();
        this.renderDOM();
        setTimeout(() => this.updateSpacers(), 100);
    }

    updateSpacers() {
        const { top, bottom } = this.cache.computeSpacers(this.renderStart, this.renderEnd);
        this.paddingTop = top;
        this.paddingBottom = bottom;
        this.topSpacer.style.height = `${top}px`;
        this.bottomSpacer.style.height = `${bottom}px`;
    }

    renderDOM() {
        for (let i = 0; i < this.items.length; i++) {
            const item = this.items[i];
            const inRange = i >= this.renderStart && i < this.renderEnd;
            const inDOM = item.el.parentNode === this.container;
            if (!inRange && inDOM) {
                this.observer.unobserve(item.el);
                this.realObserver.unobserve(item.el);
                item.el.remove();
            }
        }
        
        let insertBefore = this.bottomSpacer;
        for (let i = this.renderEnd - 1; i >= this.renderStart; i--) {
            const item = this.items[i];
            if (!item) continue;
            if (item.el.parentNode !== this.container) {
                this.container.insertBefore(item.el, insertBefore);
                this.observer.observe(item.el);
                this.realObserver.observe(item.el);
            }
            insertBefore = item.el;
        }
    }

    updateWindow() {
        if (this.visibleIndices.size === 0) return;
        const indices = Array.from(this.visibleIndices).sort((a, b) => a - b);
        const minVis = indices[0];
        const maxVis = indices[indices.length - 1];
        const total = this.items.length;
        
        let newStart = Math.max(0, minVis - this.getBuffer());
        let newEnd = Math.min(total, maxVis + this.getBuffer() + 1);
        
        if (this.columns > 1) {
            newStart = Math.floor(newStart / this.columns) * this.columns;
            newEnd = Math.ceil(newEnd / this.columns) * this.columns;
            newEnd = Math.min(total, newEnd);
        }
        
        if (newStart !== this.renderStart || newEnd !== this.renderEnd) {
            this.renderStart = newStart;
            this.renderEnd = newEnd;
            this.updateSpacers();
            this.renderDOM();
        }
    }

    initObservers() {
        if (this.observer) this.observer.disconnect();
        this.observer = new IntersectionObserver((entries) => {
            if (!this.mounted) return;
            let changed = false;
            entries.forEach(entry => {
                const idx = parseInt(entry.target.dataset.index);
                if (isNaN(idx)) return;
                if (entry.boundingClientRect.height > 0) {
                    this.cache.setHeight(idx, entry.boundingClientRect.height);
                }
                if (entry.isIntersecting) {
                    this.visibleIndices.add(idx);
                    changed = true;
                } else {
                    this.visibleIndices.delete(idx);
                    changed = true;
                }
            });
            if (changed) this.updateWindow();
        }, { root: this.container, threshold: 0.01, rootMargin: '1000px' });

        if (this.realObserver) this.realObserver.disconnect();
        this.realObserver = new IntersectionObserver((entries) => {
            if (!this.mounted) return;
            entries.forEach(entry => {
                const idx = parseInt(entry.target.dataset.index);
                if (isNaN(idx)) return;
                if (entry.isIntersecting) {
                    this.realVisibleIndices.add(idx);
                } else {
                    this.realVisibleIndices.delete(idx);
                }
            });
        }, { root: this.container, threshold: [0, 0.1, 0.5, 1.0] });
    }

    _onContainerScroll() {
        if (this.isProgrammaticScrolling) return;
        this.isScrolling = true;
        clearTimeout(this.scrollTimeout);
        this.scrollTimeout = setTimeout(() => { this.isScrolling = false; }, 150);
        
        if (this.scrollRaf) return;
        this.scrollRaf = requestAnimationFrame(() => {
            this.scrollRaf = null;
            if (!this.mounted) return;
            
            const scrollTop = this.container.scrollTop;
            const clientHeight = this.container.clientHeight;
            const renderedTop = this.paddingTop;
            const renderedHeight = this.cache.getRenderedContentHeight(this.renderStart, this.renderEnd);
            const renderedBottom = renderedTop + renderedHeight;
            const scrollBuffer = 2000;
            
            if (scrollTop < renderedTop - scrollBuffer || scrollTop + clientHeight > renderedBottom + scrollBuffer) {
                const count = this.items.length;
                const targetRow = this.cache.findRowAtScrollTop(scrollTop);
                const targetIndex = targetRow >= 0 ? targetRow * this.columns : Math.max(0, count - 1);
                
                let newStart = Math.max(0, targetIndex - this.getBuffer());
                const sums = this.cache.ensure();
                let hSum = 0;
                let r = Math.floor(targetIndex / this.columns);
                while (hSum < clientHeight + 1000 && r * this.columns < count) {
                    hSum += sums[r + 1] - sums[r];
                    r++;
                }
                let newEnd = Math.min(count, r * this.columns + this.getBuffer());
                
                if (this.columns > 1) {
                    newStart = Math.floor(newStart / this.columns) * this.columns;
                    newEnd = Math.ceil(newEnd / this.columns) * this.columns;
                    newEnd = Math.min(count, newEnd);
                }
                
                if (newStart !== this.renderStart || newEnd !== this.renderEnd) {
                    this.renderStart = newStart;
                    this.renderEnd = newEnd;
                    this.visibleIndices.clear();
                    this.realVisibleIndices.clear();
                    this.updateSpacers();
                    this.renderDOM();
                }
            }
        });
    }

    destroy() {
        this.mounted = false;
        if (this.observer) this.observer.disconnect();
        if (this.realObserver) this.realObserver.disconnect();
        this.container.removeEventListener('scroll', this._onContainerScroll);
    }
}
