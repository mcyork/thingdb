class PiSetupApp {
    constructor() {
        this.init();
    }
    
    init() {
        this.setupEventListeners();
        this.setupPWA();
        this.detectPlatform();
    }
    
    detectPlatform() {
        const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
        const isAndroid = /Android/.test(navigator.userAgent);
        
        // Update app store links based on platform
        if (isIOS) {
            document.querySelector('a[href*="play.google.com"]').style.display = 'none';
        } else if (isAndroid) {
            document.querySelector('a[href*="apps.apple.com"]').style.display = 'none';
        }
    }
    
    setupEventListeners() {
        document.getElementById('open-btberrywifi-btn').addEventListener('click', () => this.openBTBerryWifi());
        document.getElementById('check-status-btn').addEventListener('click', () => this.showServiceInfo());
        document.getElementById('install-pwa-btn').addEventListener('click', () => this.installPWA());
    }
    
    setupPWA() {
        // Check if PWA is already installed
        if (window.matchMedia('(display-mode: standalone)').matches) {
            console.log('PWA is running in standalone mode');
        }
        
        // Listen for beforeinstallprompt event
        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            this.deferredPrompt = e;
            this.showInstallPrompt();
        });
        
        // Listen for appinstalled event
        window.addEventListener('appinstalled', () => {
            console.log('PWA was installed');
            this.hideInstallPrompt();
        });
    }
    
    showInstallPrompt() {
        const prompt = document.getElementById('pwa-install-prompt');
        prompt.style.display = 'block';
    }
    
    hideInstallPrompt() {
        const prompt = document.getElementById('pwa-install-prompt');
        prompt.style.display = 'none';
    }
    
    async installPWA() {
        if (this.deferredPrompt) {
            this.deferredPrompt.prompt();
            const { outcome } = await this.deferredPrompt.userChoice;
            if (outcome === 'accepted') {
                console.log('User accepted PWA installation');
            }
            this.deferredPrompt = null;
        }
    }
    
    openBTBerryWifi() {
        const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
        const isAndroid = /Android/.test(navigator.userAgent);
        
        let url;
        
        if (isIOS) {
            // Try to open BTBerryWifi app on iOS
            url = 'btwifiset://';
        } else if (isAndroid) {
            // Android intent for BTBerryWifi
            url = 'intent://btwifiset/#Intent;scheme=btwifiset;package=com.nksan.btwifiset;end';
        } else {
            // Desktop - open app store
            url = 'https://play.google.com/store/apps/details?id=com.nksan.btwifiset';
        }
        
        try {
            // Try to open the app
            window.location.href = url;
            
            // Fallback: try alternative schemes after a delay
            setTimeout(() => {
                if (isIOS) {
                    // Try alternative iOS schemes
                    const alternativeSchemes = [
                        'btwifiset://',
                        'btberrywifi://',
                        'nksan://'
                    ];
                    
                    alternativeSchemes.forEach((scheme, index) => {
                        setTimeout(() => {
                            console.log(`Trying alternative scheme: ${scheme}`);
                            window.location.href = scheme;
                        }, index * 500);
                    });
                }
            }, 1000);
            
            // Show fallback message
            setTimeout(() => {
                this.showStatus('If BTBerryWifi didn\'t open automatically, please open it manually from your app drawer.', 'info');
            }, 3000);
            
        } catch (error) {
            console.error('Error opening BTBerryWifi:', error);
            this.showStatus('Please open BTBerryWifi manually from your app drawer.', 'info');
        }
    }
    
    showServiceInfo() {
        this.showStatus('BTBerryWifi service should be running on your Pi. To check status, run: systemctl status btwifiset.service', 'info');
    }
    
    showStatus(message, type = 'info') {
        const statusDiv = document.getElementById('status-messages');
        const statusContent = document.getElementById('status-content');
        
        statusContent.textContent = message;
        statusDiv.className = `alert alert-${type}`;
        statusDiv.style.display = 'block';
        
        // Auto-hide after 8 seconds for success/info, 12 seconds for warnings
        const hideDelay = type === 'warning' ? 12000 : 8000;
        setTimeout(() => {
            statusDiv.style.display = 'none';
        }, hideDelay);
    }
}

// Initialize the app when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new PiSetupApp();
});
