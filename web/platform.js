/* Installation identity and system notifications; no private key leaves this origin. */
(() => {
  'use strict';
  let identityPromise, listener = () => {}, source;
  const bytes = value => new Uint8Array(value);
  const b64 = value => btoa(String.fromCharCode(...bytes(value)));
  const unb64 = value => bytes(Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0)));
  const changed = () => listener();
  async function identityRecord() {
    if (!isSecureContext || !crypto.subtle) throw new Error('HTTPS가 필요해요.');
    const db = await new Promise((resolve, reject) => {
      const open = indexedDB.open('flake-chicken-identity-v1', 1);
      open.onupgradeneeded = () => open.result.createObjectStore('identity');
      open.onsuccess = () => resolve(open.result);
      open.onerror = () => reject(open.error);
    });
    const read = () => new Promise((resolve, reject) => {
      const tx = db.transaction('identity', 'readonly');
      const req = tx.objectStore('identity').get('installation');
      req.onsuccess = () => resolve(req.result); req.onerror = () => reject(req.error);
    });
    let record = await read();
    if (!record) {
      const pair = await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, false, ['sign', 'verify']);
      const candidate = {salt: crypto.getRandomValues(new Uint8Array(32)), privateKey: pair.privateKey, publicKey: pair.publicKey};
      // Atomic insert: a second first-run tab must use the winning key, never overwrite it.
      await new Promise((resolve, reject) => {
        const tx = db.transaction('identity', 'readwrite');
        const req = tx.objectStore('identity').add(candidate, 'installation');
        req.onerror = event => { if (req.error.name === 'ConstraintError') { event.preventDefault(); event.stopPropagation(); } };
        tx.oncomplete = resolve; tx.onabort = () => reject(tx.error);
      });
      record = await read();
    }
    db.close();
    if (!record?.privateKey || record.privateKey.extractable) throw new Error('기기 키를 확인해주세요.');
    const spki = bytes(await crypto.subtle.exportKey('spki', record.publicKey));
    const prefix = new TextEncoder().encode('flake-chicken-identity-v1\0');
    const material = new Uint8Array(prefix.length + record.salt.length + spki.length);
    material.set(prefix); material.set(record.salt, prefix.length); material.set(spki, prefix.length + record.salt.length);
    const digest = bytes(await crypto.subtle.digest('SHA-256', material));
    return {...record, uid: [...digest].map(x => x.toString(16).padStart(2, '0')).join(''), spki};
  }
  const identity = () => identityPromise ??= identityRecord().catch(error => { identityPromise = null; throw error; });
  async function registration() { return navigator.serviceWorker.register('/push-sw.js', {scope: '/'}); }
  window.flakePlatform = {
    async identity() {
      const record = await identity();
      return {uid: record.uid, salt: b64(record.salt), publicKey: b64(record.spki), platform: 'web'};
    },
    async sign(payload) {
      const record = await identity();
      return b64(await crypto.subtle.sign({name: 'ECDSA', hash: 'SHA-256'}, record.privateKey, new TextEncoder().encode(payload)));
    },
    async notifications({publicKey, request}) {
      if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window) || !isSecureContext) {
        return {supported: false, enabled: false, message: /iPhone|iPad|iPod/.test(navigator.userAgent) ? '홈 화면에 추가한 웹앱에서 알림을 켤 수 있어요.' : '이 브라우저에서는 시스템 알림을 지원하지 않아요.'};
      }
      let permission = Notification.permission;
      if (request && permission === 'default') permission = await Notification.requestPermission();
      if (permission !== 'granted') return {supported: true, enabled: false, message: permission === 'denied' ? '브라우저 설정에서 알림 권한을 허용해주세요.' : ''};
      const reg = await registration();
      await navigator.serviceWorker.ready;
      let sub = await reg.pushManager.getSubscription();
      if (!sub && request) sub = await reg.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: unb64(publicKey)});
      return {supported: true, enabled: !!sub, kind: 'web', payload: sub?.toJSON()};
    },
    async disableNotifications() {
      const reg = await navigator.serviceWorker.getRegistration('/');
      const sub = await reg?.pushManager.getSubscription();
      if (sub) await sub.unsubscribe();
    },
    listen(callback) { listener = callback; navigator.serviceWorker?.addEventListener('message', changed); },
    startEvents(origin) {
      source?.close(); source = new EventSource(origin + '/api/events', {withCredentials: true});
      source.addEventListener('changed', changed);
      // The API client renews the cookie on its next foreground poll if the session expired.
    },
    async openUrl(url) { window.open(url, '_blank', 'noopener,noreferrer'); },
    dispose() { source?.close(); navigator.serviceWorker?.removeEventListener('message', changed); listener = () => {}; }
  };
})();
