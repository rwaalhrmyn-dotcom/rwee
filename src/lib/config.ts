// Google services config. Values injected at build via Vite env; empty = feature dormant.
export const GA_ID = import.meta.env.VITE_GA_ID ?? ''            // e.g. G-XXXXXXX
export const MAPS_KEY = import.meta.env.VITE_GOOGLE_MAPS_KEY ?? '' // Google Maps JS API key
