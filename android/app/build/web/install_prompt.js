let deferredPrompt;

window.addEventListener('load', () => {
    // إذا كان التطبيق يعمل كـ PWA، اعرض المحتوى
    if (window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true) {
        document.getElementById('pwa-install-prompt').style.display = 'none';
        document.getElementById('app-content').style.display = 'block';
    } else {
        // إذا كان في المتصفح، اخفي المحتوى واعرض شاشة التثبيت
        document.getElementById('pwa-install-prompt').style.display = 'flex';
        document.getElementById('app-content').style.display = 'none';
    }
});

window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredPrompt = e;
});

function installPWA() {
    if (!deferredPrompt) return;

    deferredPrompt.prompt();
    deferredPrompt.userChoice.then((choiceResult) => {
        if (choiceResult.outcome === 'accepted') {
            console.log('User accepted the install prompt');
        }
        deferredPrompt = null;
    });
} 