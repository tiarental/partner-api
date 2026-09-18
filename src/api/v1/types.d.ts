export type Environment = 'test' | 'live';
export type BookingMode = 'request' | 'instant';
export type WebhookEvent = 'booking.created' | 'booking.confirmed' | 'booking.rejected' | 'booking.cancelled' | 'booking.modified' | 'availability.blocked' | 'availability.unblocked' | 'car.updated' | 'price.updated';
export interface ClientOptions { apiKey: string; baseUrl?: string; fetchImpl?: typeof fetch }
export interface RequestOptions { signal?: AbortSignal }
export interface ApiEnvelope<T> { data: T; meta?: Record<string, unknown> }
export interface TiarentalCar { id:string; slug:string; brand:string; model:string; year:number; category:string; transmission:string; fuel:string; seats:number; base_daily_price:number; currency:'EUR'; deposit:number; instant_booking:boolean; images:string[]; pickup_locations:Array<{id:string;name:string;city:string;type:string;is_primary:boolean;pickup_fee:number;dropoff_fee:number}> }
export interface BookingCustomer { first_name:string; last_name:string; email:string; phone:string; age?:number; driving_years?:number; country?:string; notes?:string }
export interface CreateBooking { car_id:string; pickup_at:string; dropoff_at:string; pickup_location_id?:string; dropoff_location_id?:string; pickup_location?:string; dropoff_location?:string; customer:BookingCustomer; booking_mode?:BookingMode; external_reference?:string; cross_border_countries?:string[] }
export interface Booking { id:string; number:string; status:string; mode:string; car:{id:string;brand:string;model:string;year:number}; pickup:{at:string;location:unknown}; dropoff:{at:string;location:unknown}; pricing:{currency:string;total:number;deposit:number}; customer:BookingCustomer|null; source:string; external_reference:string|null; created_at:string; updated_at:string }
export declare class TiarentalApiError extends Error { code:string; status:number; requestId?:string; details?:unknown }
export declare class TiarentalClient {
  constructor(options:ClientOptions);
  request(method:string,path:string,options?:RequestOptions & {query?:Record<string,unknown>;body?:unknown;idempotencyKey?:string}):Promise<any>;
  me(options?:RequestOptions):Promise<ApiEnvelope<unknown>>; cars(query?:Record<string,unknown>,options?:RequestOptions):Promise<ApiEnvelope<TiarentalCar[]>>; car(id:string,options?:RequestOptions):Promise<ApiEnvelope<TiarentalCar>>;
  availability(query:Record<string,unknown>,options?:RequestOptions):Promise<ApiEnvelope<unknown>>; quote(query:Record<string,unknown>,options?:RequestOptions):Promise<ApiEnvelope<unknown>>;
  createBooking(body:CreateBooking,key:string,options?:RequestOptions):Promise<ApiEnvelope<Booking>>; booking(id:string,options?:RequestOptions):Promise<ApiEnvelope<Booking>>; cancelBooking(id:string,body:unknown,key:string,options?:RequestOptions):Promise<ApiEnvelope<Booking>>; modifyBooking(id:string,body:unknown,key:string,options?:RequestOptions):Promise<ApiEnvelope<Booking>>;
  createBlock(body:unknown,key:string,options?:RequestOptions):Promise<ApiEnvelope<unknown>>; deleteBlock(id:string,options?:RequestOptions):Promise<ApiEnvelope<unknown>>; webhooks(options?:RequestOptions):Promise<ApiEnvelope<unknown[]>>; createWebhook(body:unknown,options?:RequestOptions):Promise<ApiEnvelope<unknown>>; deleteWebhook(id:string,options?:RequestOptions):Promise<ApiEnvelope<unknown>>;
}
