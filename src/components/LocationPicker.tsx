import { useEffect, useRef, useState } from 'react'

// Open-source delivery-location picker: Leaflet + OpenStreetMap (no paid key).
// The customer drops/drags a pin; we keep the exact coordinates for the courier.
// Reverse geocoding (address from coordinates) is best-effort only — if the
// public geocoder is unavailable the pin still works and the coordinates are saved.

export type LatLng = { lat: number; lng: number }

const CITY_CENTER: Record<string, LatLng> = {
  makkah: { lat: 21.4225, lng: 39.8262 },
  madinah: { lat: 24.4672, lng: 39.6111 },
}

const CDN = 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4'
const FALLBACK = 'https://unpkg.com/leaflet@1.9.4/dist'

let leafletLoading: Promise<void> | null = null
function addScript(src: string) {
  return new Promise<void>((resolve, reject) => {
    const s = document.createElement('script'); s.src = src; s.async = true
    s.onload = () => resolve(); s.onerror = () => reject(new Error('load failed'))
    document.head.appendChild(s)
  })
}
function loadLeaflet(): Promise<void> {
  if ((window as any).L) return Promise.resolve()
  if (leafletLoading) return leafletLoading
  leafletLoading = (async () => {
    const css = document.createElement('link')
    css.rel = 'stylesheet'; css.href = `${CDN}/leaflet.min.css`
    css.onerror = () => { css.href = `${FALLBACK}/leaflet.css` }
    document.head.appendChild(css)
    try { await addScript(`${CDN}/leaflet.min.js`) }
    catch { await addScript(`${FALLBACK}/leaflet.js`) }
  })()
  return leafletLoading
}

function markerIcon(L: any) {
  // Explicit icon URLs so the pin is always visible with CDN-hosted Leaflet.
  return L.icon({
    iconUrl: `${CDN}/images/marker-icon.png`,
    iconRetinaUrl: `${CDN}/images/marker-icon-2x.png`,
    shadowUrl: `${CDN}/images/marker-shadow.png`,
    iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34], shadowSize: [41, 41],
  })
}

async function reverseGeocode(lat: number, lng: number): Promise<string> {
  try {
    const r = await fetch(
      `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&accept-language=ar&zoom=18`,
      { headers: { Accept: 'application/json' } },
    )
    if (!r.ok) return ''
    const j = await r.json()
    return (j?.display_name as string) || ''
  } catch { return '' }
}

export default function LocationPicker({
  value, onChange, onLocation, city = 'makkah',
}: {
  value: string
  onChange: (v: string) => void
  onLocation?: (c: LatLng | null) => void
  city?: string
}) {
  const mapEl = useRef<HTMLDivElement>(null)
  const mapRef = useRef<any>(null)
  const markerRef = useRef<any>(null)
  const [ready, setReady] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [located, setLocated] = useState<LatLng | null>(null)

  const place = (lat: number, lng: number, recenter = false) => {
    const L = (window as any).L
    if (!L || !mapRef.current) return
    if (!markerRef.current) {
      markerRef.current = L.marker([lat, lng], { draggable: true, icon: markerIcon(L) }).addTo(mapRef.current)
      markerRef.current.on('dragend', () => { const p = markerRef.current.getLatLng(); commit(p.lat, p.lng) })
    } else { markerRef.current.setLatLng([lat, lng]) }
    if (recenter) mapRef.current.setView([lat, lng], 16)
  }

  const commit = async (lat: number, lng: number) => {
    place(lat, lng)
    setLocated({ lat, lng })
    onLocation?.({ lat, lng })
    setBusy(true)
    const addr = await reverseGeocode(lat, lng)
    setBusy(false)
    if (addr) onChange(addr) // only fills when the geocoder is available; otherwise the pin + coords are enough
  }

  useEffect(() => {
    let cancelled = false
    loadLeaflet().then(() => {
      if (cancelled || !mapEl.current || (window as any).L == null) return
      const L = (window as any).L
      const c = CITY_CENTER[city] || CITY_CENTER.makkah
      const map = L.map(mapEl.current).setView([c.lat, c.lng], 12)
      // CARTO Voyager — open basemap built on OpenStreetMap data, reliable for production.
      L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
        maxZoom: 20, crossOrigin: true, subdomains: 'abcd',
        attribution: '© OpenStreetMap, © CARTO',
      }).addTo(map)
      map.on('click', (e: any) => commit(e.latlng.lat, e.latlng.lng))
      mapRef.current = map
      setReady(true)
      setTimeout(() => map.invalidateSize(), 200)
    }).catch(() => setErr('تعذّر تحميل الخريطة. اكتب العنوان يدوياً وسنتواصل لتأكيد الموقع.'))
    return () => {
      cancelled = true
      if (mapRef.current) { mapRef.current.remove(); mapRef.current = null; markerRef.current = null }
    }
  }, [])

  useEffect(() => {
    if (!mapRef.current || markerRef.current) return
    const c = CITY_CENTER[city]; if (c) mapRef.current.setView([c.lat, c.lng], 12)
  }, [city])

  const locateMe = () => {
    if (!navigator.geolocation) { setErr('المتصفح لا يدعم تحديد الموقع.'); return }
    setErr(null); setBusy(true)
    navigator.geolocation.getCurrentPosition(
      (pos) => { setBusy(false); place(pos.coords.latitude, pos.coords.longitude, true); commit(pos.coords.latitude, pos.coords.longitude) },
      () => { setBusy(false); setErr('تعذّر الوصول لموقعك. فعّل إذن الموقع أو حدّده على الخريطة.') },
      { enableHighAccuracy: true, timeout: 10000 },
    )
  }

  const status = busy ? 'جارٍ التحديد…'
    : err ? err
    : located ? '✓ تم تحديد موقعك على الخريطة — أضف تفاصيل المبنى/الشقة في الحقل أعلاه إن رغبت.'
    : ready ? 'انقر على الخريطة أو اسحب الدبوس أو اضغط «موقعي الحالي» لتحديد مكان التوصيل بدقّة.'
    : 'جارٍ تحميل الخريطة…'

  return (
    <div>
      <input
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder="الحي، الشارع، رقم المبنى — أو حدّد موقعك على الخريطة"
        style={{ marginBottom: 8 }}
      />
      <div style={{ position: 'relative' }}>
        <div ref={mapEl} style={{ height: 260, borderRadius: 14, overflow: 'hidden', border: '1px solid var(--line)', background: '#eef3f0' }} />
        <button type="button" onClick={locateMe} className="btn ghost"
          style={{ position: 'absolute', zIndex: 500, insetInlineEnd: 10, top: 10, padding: '7px 12px', fontSize: 13, background: '#fff' }}>📍 موقعي الحالي</button>
      </div>
      <p className="muted" style={{ fontSize: 12, marginTop: 6, color: located ? 'var(--green)' : undefined }}>{status}</p>
    </div>
  )
}
