/**
 * Cloudflare Worker for DNS Registration
 * Handles automated DNS record creation for Inventory Pi devices
 */

// Environment variables (set via wrangler or dashboard):
// CF_API_TOKEN - Your Cloudflare API token for DNS management
// ZONE_ID - Zone ID for your domain (e.g., inv.esoup.net)
// LEAF_CERT_HASH - SHA256 hash of device certificate (optional security)

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

/**
 * Rate limiting using Cloudflare KV (optional)
 */
async function checkRateLimit(serial) {
  if (typeof RATE_LIMIT_KV === 'undefined') {
    return true; // KV not configured, skip rate limiting
  }
  
  const key = `rate:${serial}`;
  const lastRequest = await RATE_LIMIT_KV.get(key);
  
  if (lastRequest) {
    const timeSince = Date.now() - parseInt(lastRequest);
    if (timeSince < 3600000) { // 1 hour
      return false;
    }
  }
  
  await RATE_LIMIT_KV.put(key, Date.now().toString(), {
    expirationTtl: 3600
  });
  
  return true;
}

/**
 * Verify device certificate (optional security feature)
 */
async function verifyCertificate(certHeader) {
  if (!certHeader || typeof LEAF_CERT_HASH === 'undefined') {
    return true; // Skip verification if not configured
  }
  
  // Simple verification: check certificate hash
  const encoder = new TextEncoder();
  const data = encoder.encode(certHeader);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  
  return hashHex === LEAF_CERT_HASH;
}

/**
 * Create or update DNS record
 */
async function createOrUpdateDNSRecord(hostname, tunnelId) {
  const apiUrl = `https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records`;
  
  // Check if record already exists
  const existingCheck = await fetch(
    `${apiUrl}?name=${hostname}`,
    {
      headers: {
        'Authorization': `Bearer ${CF_API_TOKEN}`,
        'Content-Type': 'application/json'
      }
    }
  );
  
  if (!existingCheck.ok) {
    throw new Error(`Failed to check existing DNS records: ${existingCheck.status} ${await existingCheck.text()}`);
  }
  
  const existing = await existingCheck.json();
  
  if (!existing.success) {
    throw new Error(`DNS query failed: ${JSON.stringify(existing.errors)}`);
  }
  
  console.log(`DNS query result for ${hostname}:`, JSON.stringify(existing, null, 2));
  
  const recordData = {
    type: 'CNAME',
    name: hostname,
    content: `${tunnelId}.cfargotunnel.com`,
    ttl: 300,
    proxied: true
  };
  
  if (existing.result && existing.result.length > 0) {
    console.log(`Found existing record, updating: ${existing.result[0].id}`);
    // Update existing record
    const recordId = existing.result[0].id;
    const updateResponse = await fetch(
      `${apiUrl}/${recordId}`,
      {
        method: 'PUT',
        headers: {
          'Authorization': `Bearer ${CF_API_TOKEN}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(recordData)
      }
    );
    
    if (!updateResponse.ok) {
      const error = await updateResponse.text();
      throw new Error(`Failed to update DNS record: ${error}`);
    }
    
    return { action: 'updated', recordId };
  } else {
    console.log(`No existing record found, creating new one for ${hostname}`);
    // Create new record
    const createResponse = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${CF_API_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(recordData)
    });
    
    if (!createResponse.ok) {
      const error = await createResponse.text();
      throw new Error(`Failed to create DNS record: ${error}`);
    }
    
    const result = await createResponse.json();
    return { action: 'created', recordId: result.result.id };
  }
}

/**
 * Log registration (optional)
 */
async function logRegistration(serial, tunnelId, email, timestamp) {
  if (typeof REGISTRATIONS_KV === 'undefined') {
    return; // KV not configured, skip logging
  }
  
  const cleanSerial = serial.replace(/[^a-zA-Z0-9-]/g, '').toLowerCase();
  await REGISTRATIONS_KV.put(
    `device:${cleanSerial}`,
    JSON.stringify({
      tunnel_id: tunnelId,
      email: email,
      registered_at: timestamp || new Date().toISOString()
    })
  );
}

/**
 * Main request handler
 */
async function handleRequest(request) {
  // Only accept POST requests
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { 
      status: 405,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
  
  try {
    // Verify certificate (optional)
    const certHeader = request.headers.get('X-Device-Certificate');
    if (!await verifyCertificate(certHeader)) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Invalid certificate'
      }), { 
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Parse request body
    const data = await request.json();
    const { serial, tunnel_id, email, timestamp } = data;
    
    // Validate input
    if (!serial || !tunnel_id || !email) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Missing required fields'
      }), { 
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Check rate limit
    if (!await checkRateLimit(serial)) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Rate limited. Please wait before retrying.'
      }), { 
        status: 429,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Sanitize serial for DNS
    const cleanSerial = serial.replace(/[^a-zA-Z0-9-]/g, '').toLowerCase();
    const hostname = `pi-${cleanSerial}.nestdb.io`.substring(0, 63); // DNS label limit
    
    // Create or update DNS record
    const dnsResult = await createOrUpdateDNSRecord(hostname, tunnel_id);
    
    // Log registration (optional)
    await logRegistration(serial, tunnel_id, email, timestamp);
    
    // Return success response
    return new Response(JSON.stringify({
      success: true,
      url: `https://${hostname}`,
      tunnel_id: tunnel_id,
      action: dnsResult.action
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    console.error('Worker error:', error);
    
    return new Response(JSON.stringify({
      success: false,
      error: error.message || 'Internal server error'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}
