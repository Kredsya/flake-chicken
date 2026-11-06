'use strict';
self.addEventListener('push', event => {
  event.waitUntil((async () => {
    let data;
    try { data = event.data.json(); } catch (_) { return; }
    if (!data.id || !data.title) return;
    await self.registration.showNotification(data.title, {
      body: data.body, tag: data.id, renotify: false,
      icon: '/icons/Icon-192.png', badge: '/icons/Icon-192.png',
      data: {appointmentId: data.appointmentId}
    });
    const clients = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const client of clients) client.postMessage({type: 'appointments-changed'});
  })());
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil((async () => {
    const clients = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const client of clients) if (new URL(client.url).origin === self.location.origin) {
      client.postMessage({type: 'appointments-changed'}); return client.focus();
    }
    return self.clients.openWindow('/');
  })());
});
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
