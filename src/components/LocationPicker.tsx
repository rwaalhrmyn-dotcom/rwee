import { useEffect, useRef, useState } from 'react'

// Open-source delivery-location picker: Leaflet + OpenStreetMap (no paid key).
// The customer drops/drags a pin; we reverse-geocode it (Nominatim) into an
// address and also hand the parent the exact coordinates for the courier.

export type LatLng = { lat: number; lng: number }

const CITY_CENTER: Record<string, LatLng> = {
  makkah: { lat: 21.4225, lng: 39.8262 },
  madinah: { lat: 24.4672, lng: 39.6111 },
}

let leafletLoading: Promise<void> | null = null
function loadLeaflet(): Promise<void> {
  if ((window as any).L) return Promise.resolve()
  if (leafletLoading) return leafletLoading
  leafletLoading = new Promise((resolve, reject) => {
    const css = document.createElement('link')
    css.rel = 'stylesheet'
    css.href = 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css'
    document.head.appendChild(css)
    const s = document.createElement('script')
    s.src = 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js'
    s.async = true
    s.onload = () => resolve()
    s.onerror = () => reject(new Error('leaflet load failed'))
    document.head.appendChild(s)
  })
  return leafletLoading
}

async function reverseGeocode(lat: number, lng: number): Promise<string> {
  try {
    const r = await fetch(
      `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&accept-language=ar&zoom=18`,
      { headers: { Accept: 'application/json' } },
    )
    const j = await r.json()
    return (j?.display_name as string) || ''
  } catch {
    return ''
  }
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

  const place = async (lat: number, lng: number, recenter = false) => {
    const L = (window as any).L
    if (!L || !mapRef.current) return
    if (!markerRef.current) {
      markerRef.current = L.marker([lat, lng], { draggable: true }).addTo(mapRef.current)
      markerRef.current.on('dragend', () => {
        const p = markerRef.current.getLatLng()
        commit(p.lat, p.lng)
      })
    } else {
      markerRef.current.setLatLng([lat, lng])
    }
    if (recenter) mapRef.current.setView([lat, lng], 16)
    onLocation?.({ lat, lng })
  }

  const commit = async (lat: number, lng: number) => {
    await place(lat, lng)
    setBusy(true)
    const addr = await reverseGeocode(lat, lng)
    setBusy(false)
    if (addr) onChange(addr)
  }

  useEffect(() => {
    let cancelled = false
    loadLeaflet().then(() => {
      if (cancelled || !mapEl.current) return
      const L = (window as any).L
      const c = CITY_CENTER[city] || CITY_CENTER.makkah
      const map = L.map(mapEl.current, { attributionControl: true }).setView([c.lat, c.lng], 12)
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '© OpenStreetMap',
      }).addTo(map)
      map.on('click', (e: any) => commit(e.latlng.lat, e.latlng.lng))
      mapRef.current = map
      setReady(true)
      // Leaflet needs a size recalculation once its container is laid out.
      setTimeout(() => map.invalidateSize(), 200)
    }).catch(() => setErr('تعذّر تحميل الخريطة. يمكنك كتابة العنوان يدوياً.'))
    return () => {
      cancelled = true
      if (mapRef.current) { mapRef.current.remove(); mapRef.current = null; markerRef.current = null }
    }
  }, [])

  // Recenter when the chosen city changes (before a pin is dropped).
  useEffect(() => {
    if (!mapRef.current || markerRef.current) return
    const c = CITY_CENTER[city]
    if (c) mapRef.current.setView([c.lat, c.lng], 12)
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

  return (
    <div>
      <input
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder="الحي، الشارع، رقم المبنى — أو حدّد موقعك على الخريطة"
        style={{ marginBottom: 8 }}
      />
      <div style={{ position: 'relative' }}>
        <div
          ref={mapEl}
          style={{ height: 260, borderRadius: 14, overflow: 'hidden', border: '1px solid var(--line)', background: '#eef3f0' }}
        />
        <button
          type="button"
          onClick={locateMe}
          className="btn ghost"
          style={{ position: 'absolute', zIndex: 500, insetInlineEnd: 10, top: 10, padding: '7px 12px', fontSize: 13, background: '#fff' }}
        >📍 موقعي الحالي</button>
      </div>
      <p className="muted" style={{ fontSize: 12, marginTop: 6 }}>
        {busy ? 'جارٍ تحديد العنوان…' : err ? err : ready ? 'انقر على الخريطة أو اسحب الدبوس لتحديد مكان التوصيل بدقّة.' : 'جارٍ تحميل الخريطة…'}
      </p>
    </div>
  )
}
