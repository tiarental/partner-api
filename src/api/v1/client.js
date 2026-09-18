export class TiarentalApiError extends Error {
  constructor(code, message, status, requestId, details) {
    super(message);
    this.name = 'TiarentalApiError';
    this.code = code;
    this.status = status;
    this.requestId = requestId;
    this.details = details;
  }
}

export class TiarentalClient {
  constructor({ apiKey, baseUrl = 'https://api.tiarental.com/v1', fetchImpl = globalThis.fetch } = {}) {
    if (!/^tr_(test|live)_[A-Za-z0-9_-]{32,}$/.test(apiKey || '')) throw new TypeError('A valid TIARENTAL Partner API key is required.');
    if (typeof fetchImpl !== 'function') throw new TypeError('A fetch implementation is required.');
    this.apiKey = apiKey;
    this.baseUrl = String(baseUrl).replace(/\/$/, '');
    this.fetch = fetchImpl;
  }

  async request(method, path, { query, body, idempotencyKey, signal } = {}) {
    const url = new URL(this.baseUrl + '/' + String(path).replace(/^\//, ''));
    for (const [key, value] of Object.entries(query || {})) {
      if (value !== undefined && value !== null && value !== '') url.searchParams.set(key, Array.isArray(value) ? value.join(',') : String(value));
    }
    const headers = { Accept: 'application/json', Authorization: `Bearer ${this.apiKey}` };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;
    const response = await this.fetch(url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = payload.error || {};
      throw new TiarentalApiError(error.code || 'INTERNAL_ERROR', error.message || 'TIARENTAL API request failed.', response.status, error.request_id || response.headers.get('x-request-id'), error.details);
    }
    return payload;
  }

  me(options) { return this.request('GET', '/me', options); }
  cars(query, options = {}) { return this.request('GET', '/cars', { ...options, query }); }
  car(carId, options) { return this.request('GET', `/cars/${encodeURIComponent(carId)}`, options); }
  availability(query, options = {}) { return this.request('GET', '/availability', { ...options, query }); }
  quote(query, options = {}) { return this.request('GET', '/pricing/quote', { ...options, query }); }
  createBooking(body, idempotencyKey, options = {}) { return this.request('POST', '/bookings', { ...options, body, idempotencyKey }); }
  booking(bookingId, options) { return this.request('GET', `/bookings/${encodeURIComponent(bookingId)}`, options); }
  cancelBooking(bookingId, body, idempotencyKey, options = {}) { return this.request('POST', `/bookings/${encodeURIComponent(bookingId)}/cancel`, { ...options, body, idempotencyKey }); }
  modifyBooking(bookingId, body, idempotencyKey, options = {}) { return this.request('POST', `/bookings/${encodeURIComponent(bookingId)}/modify`, { ...options, body, idempotencyKey }); }
  createBlock(body, idempotencyKey, options = {}) { return this.request('POST', '/availability/blocks', { ...options, body, idempotencyKey }); }
  deleteBlock(blockId, options) { return this.request('DELETE', `/availability/blocks/${encodeURIComponent(blockId)}`, options); }
  webhooks(options) { return this.request('GET', '/webhooks', options); }
  createWebhook(body, options = {}) { return this.request('POST', '/webhooks', { ...options, body }); }
  deleteWebhook(webhookId, options) { return this.request('DELETE', `/webhooks/${encodeURIComponent(webhookId)}`, options); }
}
