(function () {
  'use strict';
  const cfg = window.TRB_CONFIG || {};
  const node = (tag, cls, text) => { const item = document.createElement(tag); if (cls) item.className = cls; if (text !== undefined) item.textContent = text; return item; };
  const money = value => new Intl.NumberFormat(undefined, { style: 'currency', currency: cfg.currency || 'EUR' }).format(Number(value || 0));
  const idempotency = () => window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'wp-' + Date.now() + '-' + Math.random().toString(36).slice(2);
  const time12 = value => { const parts = String(value || '00:00').split(':').map(Number); return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit', hour12: true }).format(new Date(2020, 0, 1, parts[0], parts[1])); };
  const tiranaFormatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Tirane', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
  const tiranaParts = milliseconds => { const values = {}; tiranaFormatter.formatToParts(new Date(milliseconds)).forEach(part => { if (part.type !== 'literal') values[part.type] = Number(part.value); }); return values; };
  const localEpoch = milliseconds => { const part = tiranaParts(milliseconds); return Date.UTC(part.year, part.month - 1, part.day, part.hour, part.minute, part.second); };
  const iso = (date, time) => {
    const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(String(date) + 'T' + String(time));
    if (!match) throw new Error('Choose a valid pickup and drop-off date and time.');
    const values = match.slice(1).map(Number), year = values[0], month = values[1], day = values[2], hour = values[3], minute = values[4];
    const target = Date.UTC(year, month - 1, day, hour, minute, 0), normalized = new Date(target);
    if (normalized.getUTCFullYear() !== year || normalized.getUTCMonth() !== month - 1 || normalized.getUTCDate() !== day || normalized.getUTCHours() !== hour || normalized.getUTCMinutes() !== minute) throw new Error('Choose a valid pickup and drop-off date and time.');
    let actual = target - (localEpoch(target) - target);
    actual = target - (localEpoch(actual) - actual);
    const roundTrip = tiranaParts(actual);
    if (roundTrip.year !== year || roundTrip.month !== month || roundTrip.day !== day || roundTrip.hour !== hour || roundTrip.minute !== minute) throw new Error('This local time does not exist in Albania because of the daylight-saving time change.');
    return new Date(actual).toISOString();
  };
  const errorMessage = body => body && body.error && body.error.message ? body.error.message : 'The request could not be completed.';

  document.querySelectorAll('[data-trb-widget]').forEach(widget => {
    const search = widget.querySelector('[data-trb-search]');
    const results = widget.querySelector('[data-trb-results]');
    const status = widget.querySelector('[data-trb-status]');
    const customer = widget.querySelector('[data-trb-customer]');
    const customerForm = widget.querySelector('[data-trb-customer-form]');
    let selected = null;
    let period = null;
    let requestKey = idempotency();

    widget.querySelectorAll('input[type="time"]').forEach(input => {
      const preview = input.parentElement.querySelector('[data-trb-time-preview]');
      const show = () => { if (preview) preview.textContent = time12(input.value); };
      input.addEventListener('input', show); show();
    });

    function setStatus(message, type) { status.textContent = message || ''; status.className = 'trb-status ' + (type || ''); }
    function renderCars(cars) {
      results.replaceChildren();
      if (!cars.length) { setStatus('No available cars were found for this search.', 'empty'); return; }
      setStatus(cars.length + ' cars found.', 'success');
      cars.forEach(car => {
        const card = node('article', 'trb-car');
        const image = node('div', 'trb-car-image');
        if (Array.isArray(car.images) && car.images[0] && /^https:\/\//i.test(car.images[0])) { const img = node('img'); img.src = car.images[0]; img.alt = car.brand + ' ' + car.model; img.loading = 'lazy'; image.append(img); }
        const body = node('div', 'trb-car-body');
        const title = node('h3', '', car.brand + ' ' + car.model + ' ' + car.year);
        const specs = node('p', 'trb-specs', [car.transmission, car.fuel, car.seats + ' seats'].join(' · '));
        const source = car.quote && typeof car.quote === 'object' ? (Array.isArray(car.quote) ? car.quote[0] : car.quote) : {};
        const total = source.total_price || source.total || null;
        const price = node('div', 'trb-price'); price.append(node('strong', '', total ? money(total) + ' total' : money(car.base_daily_price) + ' / day'), node('span', '', 'Deposit ' + money(car.deposit)));
        const button = node('button', 'trb-primary', 'Book now'); button.type = 'button'; button.disabled = car.availability && car.availability.available === false;
        button.addEventListener('click', () => { selected = car; customer.hidden = false; search.hidden = true; results.hidden = true; widget.querySelector('[data-trb-selected]').textContent = car.brand + ' ' + car.model + ' · ' + (total ? money(total) : money(car.base_daily_price) + '/day'); customer.scrollIntoView({ behavior: 'smooth', block: 'start' }); });
        body.append(title, specs, price, button); card.append(image, body); results.append(card);
      });
    }

    search.addEventListener('submit', async event => {
      event.preventDefault(); setStatus('Checking live availability…', 'loading'); results.replaceChildren();
      const form = new FormData(search);
      try {
        period = { pickup_at: iso(form.get('pickup_date'), form.get('pickup_time')), dropoff_at: iso(form.get('dropoff_date'), form.get('dropoff_time')), pickup_location: form.get('pickup_location'), dropoff_location: form.get('dropoff_location') };
        if (new Date(period.dropoff_at) <= new Date(period.pickup_at)) throw new Error('Drop-off must be after pickup.');
        const url = new URL(cfg.carsUrl, window.location.href); Object.entries(period).forEach(([key, value]) => url.searchParams.set(key, value)); url.searchParams.set('limit', '100');
        const response = await fetch(url, { credentials: 'same-origin', headers: { Accept: 'application/json' } }); const body = await response.json();
        if (!response.ok) throw new Error(errorMessage(body));
        renderCars(Array.isArray(body.data) ? body.data.filter(car => !car.availability || car.availability.available !== false) : []);
      } catch (error) { setStatus(error.message || 'Search failed.', 'error'); }
    });

    widget.querySelector('[data-trb-back]').addEventListener('click', () => { customer.hidden = true; search.hidden = false; results.hidden = false; });
    customerForm.addEventListener('submit', async event => {
      event.preventDefault(); if (!selected || !period) return; setStatus('Creating your booking securely…', 'loading');
      const form = new FormData(customerForm);
      const payload = { ...period, car_id: selected.id, booking_mode: selected.instant_booking ? 'instant' : 'request', website: form.get('website'), idempotency_key: requestKey, customer: { first_name: form.get('first_name'), last_name: form.get('last_name'), email: form.get('email'), phone: form.get('phone'), age: Number(form.get('age')), driving_years: Number(form.get('driving_years')), country: form.get('country'), notes: form.get('notes') } };
      try {
        const response = await fetch(cfg.bookingsUrl, { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, body: JSON.stringify(payload) }); const body = await response.json();
        if (!response.ok) throw new Error(errorMessage(body));
        const booking = body.data || {}; customer.replaceChildren(node('div', 'trb-confirmation', 'Booking ' + (booking.number || '') + ' created. Status: ' + (booking.status || 'pending') + '.')); setStatus('Your request was sent successfully.', 'success'); requestKey = idempotency();
      } catch (error) { setStatus(error.message || 'Booking failed.', 'error'); }
    });
  });
}());
