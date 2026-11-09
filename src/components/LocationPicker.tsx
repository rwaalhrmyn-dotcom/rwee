import { useEffect, useRef, useState } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import markerIconUrl from 'leaflet/dist/images/marker-icon.png'
import markerIcon2xUrl from 'leaflet/dist/images/marker-icon-2x.png'
import markerShadowUrl from 'leaflet/dist/images/marker-shadow.png'

// Delivery-location picker: Leaflet (bundled, open source) + CARTO/OSM open tiles.
// The customer drops/drags a pin; the exact coordinates are kept for the courier.
// Reverse geocoding is best-effort only — the pin always works and saves coordinates.

export type LatLng = { lat: number; lng: number }

const CITY_CENTER: Record<string, LatLng> = {
  makkah: { lat: 21.4225, lng: 39.8262 },
  madinah: { lat: 24.4672, lng: 39.6111 },
}

const PIN = L.icon({
  iconUrl: markerIconUrl, iconRetinaUrl: markerIcon2xUrl, shadowUrl: markerShadowUrl,
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34], shadowSize: [41, 41],
})

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
  const mapRef = useRef<L.Map | null>(null)
  const markerRef = useRef<L.Marker | null>(null)
  const [ready, setReady] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [located, setLocated] = useState<LatLng | null>(null)

  const place = (lat: number, lng: number, recenter = false) => {
    if (!mapRef.current) return
    if (!markerRef.current) {
      markerRef.current = L.marker([lat, lng], { draggable: true, icon: PIN }).addTo(mapRef.current)
      markerRef.current.on('dragend', () => { const p = markerRef.current!.getLatLng(); commit(p.lat, p.lng) })
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
    if (addr) onChange(addr)
  }

  useEffect(() => {
    if (!mapEl.current || mapRef.current) return
    try {
      const c = CITY_CENTER[city] || CITY_CENTER.makkah
      const map = L.map(mapEl.current, { zoomControl: true }).setView([c.lat, c.lng], 12)

      // Tile layers with automatic fallback. No crossOrigin: for a basemap we
      // only display tiles (never read their pixels), and requiring CORS makes
      // a CDN edge without the header return a blank/grey map. A fallback to
      // OpenStreetMap kicks in if CARTO tiles fail repeatedly.
      // Esri ArcGIS tiles — free, no API key, production-friendly (unlike the
      // public OSM tile server which returns 403 to production sites, and CARTO
      // basemaps which now require an API key). Esri uses {z}/{y}/{x} order.
      const esriAttr = 'Tiles © Esri'
      const providers = [
        { url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}', opts: { maxZoom: 19, attribution: esriAttr } },
        { url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}', opts: { maxZoom: 19, attribution: esriAttr } },
      ]
      let pIdx = 0
      let layer: L.TileLayer | null = null
      const addTiles = () => {
        const p = providers[pIdx]
        layer = L.tileLayer(p.url, p.opts as any)
        let errs = 0
        layer.on('tileerror', () => {
          errs++
          if (errs >= 5 && pIdx < providers.length - 1) {
            pIdx++
            if (layer) map.removeLayer(layer)
            addTiles()
          }
        })
        layer.addTo(map)
      }
      addTiles()

      map.on('click', (e: L.LeafletMouseEvent) => commit(e.latlng.lat, e.latlng.lng))
      mapRef.current = map
      setReady(true)
      // The map lives inside a lazy/Suspense card; make sure Leaflet re-measures
      // the container once it is laid out and whenever it resizes.
      const fix = () => map.invalidateSize()
      ;[120, 400, 900].forEach(ms => setTimeout(fix, ms))
      let ro: ResizeObserver | null = null
      if (typeof ResizeObserver !== 'undefined' && mapEl.current) {
        ro = new ResizeObserver(fix); ro.observe(mapEl.current)
      }
      ;(mapRef as any)._ro = ro
    } catch { setErr('تعذّر تحميل الخريطة. اكتب العنوان يدوياً وسنتواصل لتأكيد الموقع.') }
    return () => {
      try { (mapRef as any)._ro?.disconnect() } catch { /* noop */ }
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
