const https = require('https');
const http = require('http');
const { URL } = require('url');

module.exports = (req, res) => {
    // 1. CORS Headers (Allow Everywhere)
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');

    // 2. Handle OPTIONS (Preflight)
    if (req.method === 'OPTIONS') {
        res.status(200).end();
        return;
    }

    // 3. Get Target URL
    const targetUrl = req.query.url;

    if (!targetUrl) {
        return res.status(400).json({ error: 'Missing url parameter' });
    }

    try {
        const parsedUrl = new URL(targetUrl);

        // Protocol-agnostic request handler
        const lib = parsedUrl.protocol === 'https:' ? https : http;

        const options = {
            method: req.method,
            headers: {
                // Forward User-Agent or spoof it
                'User-Agent': req.headers['user-agent'] || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': '*/*',
                'Accept-Encoding': 'identity', // Important: Disable compression for easy rewriting
                // Spoof Referer to trick servers
                'Referer': parsedUrl.origin + '/',
                'Origin': parsedUrl.origin
            },
            rejectUnauthorized: false // Allow self-signed/invalid certs (Crucial for IPTV)
        };

        const proxyReq = lib.request(targetUrl, options, (proxyRes) => {
            // Forward Status
            res.statusCode = proxyRes.statusCode;

            // Forward Headers (Filter dangerous/pointless ones)
            Object.keys(proxyRes.headers).forEach(key => {
                const lowerKey = key.toLowerCase();
                if (['content-encoding', 'content-length', 'host'].includes(lowerKey)) return; // Skip these

                // Rewrite Location header for Redirects
                if (lowerKey === 'location') {
                    const loc = proxyRes.headers[key];
                    const newLoc = loc.startsWith('http')
                        ? `/api/proxy?url=${encodeURIComponent(loc)}`
                        : `/api/proxy?url=${encodeURIComponent(new URL(loc, targetUrl).toString())}`;
                    res.setHeader(key, newLoc);
                    return;
                }

                res.setHeader(key, proxyRes.headers[key]);
            });

            // Check content type to decide on rewriting
            const contentType = proxyRes.headers['content-type'] || '';
            const isM3u8 = contentType.includes('mpegurl') || contentType.includes('hls') || (targetUrl.endsWith('.m3u8'));

            if (isM3u8) {
                // Buffer and Rewrite M3U8
                let bodyChunks = [];
                proxyRes.on('data', chunk => bodyChunks.push(chunk));
                proxyRes.on('end', () => {
                    try {
                        let body = Buffer.concat(bodyChunks).toString('utf8');

                        // Rewrite explicit URLs
                        body = body.replace(/(https?:\/\/[^\s"'\n]+)/g, (match) => {
                            return `/api/proxy?url=${encodeURIComponent(match)}`;
                        });

                        // Rewrite absolute paths (starting with /)
                        // This assumes they are relative to the *target origin*, not our proxy
                        // We must resolve them against targetUrl
                        // NOTE: This logic matches lines starting with / that are NOT comments
                        // But M3U8 lines are just paths. 

                        // We need a robust resolution for relative paths in M3U8.
                        // Best strategy: Resolve *every* line that is not a comment (#) and not empty
                        const lines = body.split('\n');
                        const rewrittenLines = lines.map(line => {
                            const trimmed = line.trim();
                            if (!trimmed || trimmed.startsWith('#')) return line;

                            // It's a URI line (absolute or relative)
                            try {
                                const resolved = new URL(trimmed, targetUrl).toString();
                                return `/api/proxy?url=${encodeURIComponent(resolved)}`;
                            } catch (e) {
                                return line;
                            }
                        });

                        const newBody = rewrittenLines.join('\n');

                        res.setHeader('Content-Length', Buffer.byteLength(newBody));
                        res.write(newBody);
                        res.end();
                    } catch (e) {
                        console.error('Error rewriting M3U8:', e);
                        res.end();
                    }
                });
            } else {
                // Binary/Other content: Pipe directly
                proxyRes.pipe(res);
            }
        });

        proxyReq.on('error', (e) => {
            console.error('Proxy Request Error:', e);
            if (!res.headersSent) res.status(502).json({ error: 'Upstream Error', details: e.message });
        });

        // Timeout handler
        proxyReq.setTimeout(9000, () => { // 9s timeout (Vercel hobby limit is 10s)
            proxyReq.destroy();
            if (!res.headersSent) res.status(504).json({ error: 'Timeout' });
        });

        proxyReq.end();

    } catch (e) {
        console.error('Handler Error:', e);
        res.status(500).json({ error: 'Internal Proxy Error' });
    }
};
