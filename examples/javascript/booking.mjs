import { randomUUID } from 'node:crypto';
import { TiarentalClient } from '../../src/api/v1/client.js';

const client = new TiarentalClient({
  apiKey: process.env.TIARENTAL_API_KEY,
  baseUrl: process.env.TIARENTAL_API_URL,
});

const { data: cars } = await client.cars({
  pickup_at: '2026-10-01T08:00:00Z',
  dropoff_at: '2026-10-05T08:00:00Z',
  pickup_location: 'Tirana International Airport',
  dropoff_location: 'Tirana International Airport',
});

const car = cars.find(item => item.availability?.available);
if (!car) throw new Error('No car is currently available.');

const result = await client.createBooking({
  car_id: car.id,
  pickup_at: '2026-10-01T08:00:00Z',
  dropoff_at: '2026-10-05T08:00:00Z',
  pickup_location: 'Tirana International Airport',
  dropoff_location: 'Tirana International Airport',
  booking_mode: 'request',
  customer: {
    first_name: 'Ada', last_name: 'Kola', email: 'ada@example.com',
    phone: '+355690000000', age: 29, driving_years: 8,
  },
}, randomUUID());

console.log(result.data.number, result.data.status);
